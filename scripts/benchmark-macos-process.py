#!/usr/bin/env python3
"""Benchmark a macOS process by waiting for metric lines on stdout."""

from __future__ import annotations

import argparse
import json
import os
import re
import select
import signal
import statistics
import subprocess
import sys
import time
from pathlib import Path

METRIC_RE = re.compile(r"(?:^|\s)([A-Za-z0-9_.-]+)_ms=([0-9]+(?:\.[0-9]+)?)", re.IGNORECASE)


def main() -> int:
    parser = argparse.ArgumentParser(description="Benchmark a process that prints *_ms metrics.")
    parser.add_argument("--name", required=True, help="Human-readable benchmark name.")
    parser.add_argument("--samples", type=int, default=7)
    parser.add_argument("--timeout", type=float, default=20.0)
    parser.add_argument("--settle", type=float, default=0.5)
    parser.add_argument("--ready-metric", required=True, help="Metric name without the _ms suffix.")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--cwd", type=Path)
    parser.add_argument("--env", action="append", default=[], help="Environment override in KEY=VALUE form.")
    parser.add_argument("command", nargs=argparse.REMAINDER, help="Command to run after --.")
    args = parser.parse_args()

    if sys.platform != "darwin":
        parser.error("benchmark-macos-process.py is intended for macOS runs.")
    if args.samples < 1:
        parser.error("--samples must be at least 1.")
    if args.timeout <= 0:
        parser.error("--timeout must be greater than 0.")
    if args.settle < 0:
        parser.error("--settle must be greater than or equal to 0.")

    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command:
        parser.error("a command is required after --")

    env = os.environ.copy()
    for item in args.env:
        key, separator, value = item.partition("=")
        if not separator or not key:
            parser.error(f"--env must be KEY=VALUE, got: {item}")
        env[key] = value

    runs = [
        run_sample(
            command=command,
            cwd=args.cwd,
            env=env,
            ready_metric=args.ready_metric,
            timeout=args.timeout,
            settle=args.settle,
        )
        for _ in range(args.samples)
    ]
    payload = {
        "name": args.name,
        "command": command,
        "samples": args.samples,
        "medians": median_metrics(runs),
        "runs": runs,
    }
    text = json.dumps(payload, indent=2)
    print(text)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text + "\n", encoding="utf-8")
    if any(args.ready_metric not in run["metrics"] for run in runs):
        print(f"error: one or more runs did not report {args.ready_metric}_ms", file=sys.stderr)
        return 1
    return 0


def run_sample(
    *,
    command: list[str],
    cwd: Path | None,
    env: dict[str, str],
    ready_metric: str,
    timeout: float,
    settle: float,
) -> dict:
    started_at = time.monotonic()
    process = subprocess.Popen(
        command,
        cwd=str(cwd) if cwd else None,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )
    metrics: dict[str, float] = {}
    lines: list[str] = []
    try:
        assert process.stdout is not None
        while True:
            remaining = timeout - (time.monotonic() - started_at)
            if remaining <= 0:
                break
            ready, _, _ = select.select([process.stdout], [], [], min(remaining, 0.1))
            if not ready:
                if process.poll() is not None:
                    break
                continue
            line = process.stdout.readline()
            if not line:
                if process.poll() is not None:
                    break
                continue
            line = line.rstrip("\n")
            lines.append(line)
            for metric_name, value in METRIC_RE.findall(line):
                try:
                    metrics[metric_name] = float(value)
                except ValueError:
                    continue
            if ready_metric in metrics:
                time.sleep(settle)
                break
        rss_kb = process_rss_kb(process.pid)
    finally:
        terminate_process(process)
    return {
        "pid": process.pid,
        "metrics": metrics,
        "rssMB": round(rss_kb / 1024, 3) if rss_kb is not None else None,
        "output": lines,
        "exitCode": process.poll(),
    }


def process_rss_kb(pid: int) -> int | None:
    result = subprocess.run(
        ["/bin/ps", "-o", "rss=", "-p", str(pid)],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    value = result.stdout.strip()
    if result.returncode != 0 or not value:
        return None
    rss = int(value.splitlines()[-1])
    return rss if rss > 0 else None


def terminate_process(process: subprocess.Popen[str]) -> None:
    if process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=3)
    except subprocess.TimeoutExpired:
        os.kill(process.pid, signal.SIGKILL)
        process.wait(timeout=3)


def median_metrics(runs: list[dict]) -> dict:
    names = sorted({name for run in runs for name in run["metrics"]})
    medians = {}
    for name in names:
        values = [run["metrics"][name] for run in runs if name in run["metrics"]]
        if values:
            medians[f"{name}Ms"] = statistics.median(values)
    rss_values = [run["rssMB"] for run in runs if run["rssMB"] is not None]
    if rss_values:
        medians["rssMB"] = statistics.median(rss_values)
    return medians


if __name__ == "__main__":
    raise SystemExit(main())
