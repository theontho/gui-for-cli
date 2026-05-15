#!/usr/bin/env python3
"""Benchmark a macOS process by waiting for metric lines on stdout."""

from __future__ import annotations

import argparse
import json
import os
import re
import select
import signal
import shutil
import statistics
import subprocess
import sys
import time
from pathlib import Path

METRIC_RE = re.compile(r"(?:^|\s)([A-Za-z0-9_.-]+)(?:_ms|-ms)=([0-9]+(?:\.[0-9]+)?)", re.IGNORECASE)


def main() -> int:
    parser = argparse.ArgumentParser(description="Benchmark a process that prints *_ms metrics.")
    parser.add_argument("--name", required=True, help="Human-readable benchmark name.")
    parser.add_argument("--samples", type=int, default=7)
    parser.add_argument("--timeout", type=float, default=20.0)
    parser.add_argument("--settle", type=float, default=0.5)
    parser.add_argument("--ready-metric", required=True, help="Metric name without the _ms suffix.")
    parser.add_argument("--output", type=Path)
    parser.add_argument(
        "--artifact",
        action="append",
        default=[],
        type=Path,
        help="Built artifact path to size. May be passed more than once.",
    )
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
    for artifact in args.artifact:
        if not artifact.exists():
            parser.error(f"artifact does not exist: {artifact}")

    env = os.environ.copy()
    for item in args.env:
        key, separator, value = item.partition("=")
        if not separator or not key:
            parser.error(f"--env must be KEY=VALUE, got: {item}")
        env[key] = value

    ready_metric = normalize_metric_name(args.ready_metric)
    artifacts = artifact_metadata(args.artifact)
    runs = [
        run_sample(
            command=command,
            cwd=args.cwd,
            env=env,
            ready_metric=ready_metric,
            timeout=args.timeout,
            settle=args.settle,
        )
        for _ in range(args.samples)
    ]
    payload = {
        "name": args.name,
        "command": command,
        "launcher": launcher_metadata(command[0], args.cwd),
        "artifacts": artifacts,
        "artifactSizeMB": round(sum(item["sizeBytes"] for item in artifacts) / 1_000_000, 3)
        if artifacts
        else None,
        "samples": args.samples,
        "medians": median_metrics(runs),
        "runs": runs,
    }
    text = json.dumps(payload, indent=2)
    print(text)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text + "\n", encoding="utf-8")
    if any(ready_metric not in run["metrics"] for run in runs):
        print(f"error: one or more runs did not report {ready_metric}_ms", file=sys.stderr)
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
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
        start_new_session=True,
    )
    process_group_id = os.getpgid(process.pid)
    metrics: dict[str, float] = {}
    lines: list[str] = []
    peak_rss_kb = process_group_rss_kb(process_group_id)
    try:
        assert process.stdout is not None
        while True:
            current_rss_kb = process_group_rss_kb(process_group_id)
            if current_rss_kb is not None:
                peak_rss_kb = max(peak_rss_kb or 0, current_rss_kb)
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
                    metrics[normalize_metric_name(metric_name)] = float(value)
                except ValueError:
                    continue
            if ready_metric in metrics:
                time.sleep(settle)
                current_rss_kb = process_group_rss_kb(process_group_id)
                if current_rss_kb is not None:
                    peak_rss_kb = max(peak_rss_kb or 0, current_rss_kb)
                break
    finally:
        terminate_process(process)
    return {
        "pid": process.pid,
        "processGroupID": process_group_id,
        "metrics": metrics,
        "rssMB": round(peak_rss_kb / 1024, 3) if peak_rss_kb is not None else None,
        "rssSample": "process-tree peak",
        "output": lines,
        "exitCode": process.poll(),
    }


def normalize_metric_name(metric_name: str) -> str:
    return metric_name.removesuffix("_").replace("-", "_")


def process_group_rss_kb(process_group_id: int) -> int | None:
    result = subprocess.run(
        ["/bin/ps", "-axo", "pgid=,rss="],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    if result.returncode != 0:
        return None
    total = 0
    for line in result.stdout.splitlines():
        parts = line.split()
        if len(parts) != 2:
            continue
        try:
            pgid = int(parts[0])
            rss = int(parts[1])
        except ValueError:
            continue
        if pgid == process_group_id and rss > 0:
            total += rss
    return total or None


def terminate_process(process: subprocess.Popen[str]) -> None:
    if process.poll() is not None:
        return
    try:
        process_group_id = os.getpgid(process.pid)
        os.killpg(process_group_id, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        process.wait(timeout=3)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process_group_id, signal.SIGKILL)
        except ProcessLookupError:
            pass
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


def artifact_metadata(paths: list[Path]) -> list[dict]:
    artifacts = []
    for path in paths:
        absolute = absolute_path(path)
        size_bytes = path_size_bytes(absolute)
        artifacts.append(
            {
                "path": str(absolute),
                "kind": artifact_kind(absolute),
                "sizeBytes": size_bytes,
                "sizeMB": round(size_bytes / 1_000_000, 3),
            }
        )
    return artifacts


def launcher_metadata(command: str, cwd: Path | None) -> dict:
    resolved = shutil.which(command) if "/" not in command else command
    if not resolved:
        return {"command": command, "path": None, "sizeBytes": None, "sizeMB": None}
    path = Path(resolved)
    if not path.is_absolute() and "/" in command and cwd is not None:
        path = cwd / path
    path = absolute_path(path)
    if not path.exists():
        return {"command": command, "path": str(path), "sizeBytes": None, "sizeMB": None}
    size_bytes = path_size_bytes(path)
    return {
        "command": command,
        "path": str(path),
        "kind": artifact_kind(path),
        "sizeBytes": size_bytes,
        "sizeMB": round(size_bytes / 1_000_000, 3),
    }


def artifact_kind(path: Path) -> str:
    if path.is_symlink():
        return "symlink"
    if path.is_dir() and path.suffix == ".app":
        return "app bundle"
    if path.is_dir():
        return "directory"
    return "file"


def path_size_bytes(path: Path) -> int:
    if path.is_symlink():
        return path.lstat().st_size
    if path.is_file():
        return path.stat().st_size
    total = 0
    for child in path.rglob("*"):
        if child.is_symlink():
            total += child.lstat().st_size
        elif child.is_file():
            total += child.stat().st_size
    return total


def absolute_path(path: Path) -> Path:
    expanded = path.expanduser()
    if expanded.is_absolute():
        return expanded
    return Path.cwd() / expanded


if __name__ == "__main__":
    raise SystemExit(main())
