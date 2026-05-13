#!/usr/bin/env python3
"""Benchmark the staged Fyne app by reading startup metric lines."""

from __future__ import annotations

import argparse
import json
import os
import select
import signal
import statistics
import subprocess
import sys
import time
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("app", type=Path)
    parser.add_argument("--samples", type=int, default=7)
    parser.add_argument("--timeout", type=float, default=15.0)
    parser.add_argument("--settle", type=float, default=1.0)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("benchmark-fyne-macos.py is intended for macOS runs.")
    if args.samples < 1:
        parser.error("--samples must be at least 1.")
    app_path = args.app.resolve()
    if not app_path.is_file():
        parser.error(f"app executable does not exist: {app_path}")
    if not os.access(app_path, os.X_OK):
        parser.error(f"app is not executable: {app_path}")
    runs = [run_sample(app_path, args.timeout, args.settle) for _ in range(args.samples)]
    payload = {"app": str(app_path), "samples": args.samples, "medians": median_metrics(runs), "runs": runs}
    text = json.dumps(payload, indent=2)
    print(text)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text + "\n", encoding="utf-8")
    if any("firstFrameRendered" not in run["metrics"] for run in runs):
        print("error: one or more Fyne runs did not report firstFrameRendered", file=sys.stderr)
        return 1
    return 0


def run_sample(app_path: Path, timeout: float, settle: float) -> dict:
    started_at = time.monotonic()
    process = subprocess.Popen(
        [str(app_path)],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        env={**os.environ, "GUI_FOR_CLI_OFFLINE": "1"},
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
            if line.startswith("metric ") and "_ms=" in line:
                name, value = line[len("metric ") :].split("_ms=", 1)
                try:
                    metrics[name] = float(value)
                except ValueError:
                    continue
                if name == "firstFrameRendered":
                    time.sleep(settle)
                    break
        rss_kb = process_rss_kb(process.pid)
        return {"pid": process.pid, "metrics": metrics, "rssMB": round(rss_kb / 1024, 3) if rss_kb else None, "output": lines, "exitCode": process.poll()}
    finally:
        terminate_process(process)


def process_rss_kb(pid: int) -> int | None:
    result = subprocess.run(["/bin/ps", "-o", "rss=", "-p", str(pid)], check=False, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    value = result.stdout.strip()
    return int(value.splitlines()[-1]) if result.returncode == 0 and value else None


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
