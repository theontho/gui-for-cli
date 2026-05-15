#!/usr/bin/env python3
"""Benchmark an iOS simulator app after the simulator is booted and ready."""

from __future__ import annotations

import argparse
import json
import os
import re
import select
import socket
import statistics
import subprocess
import sys
import tempfile
import time
from pathlib import Path

METRIC_RE = re.compile(r"(?:^|\s)([A-Za-z0-9_.-]+)_ms=([0-9]+(?:\.[0-9]+)?)", re.IGNORECASE)


def main() -> int:
    parser = argparse.ArgumentParser(description="Benchmark GUI for CLI in an iOS simulator.")
    parser.add_argument("--app", required=True, type=Path)
    parser.add_argument("--bundle-id", required=True)
    parser.add_argument("--simulator", default="booted")
    parser.add_argument("--samples", type=int, default=7)
    parser.add_argument("--timeout", type=float, default=30.0)
    parser.add_argument("--settle", type=float, default=0.5)
    parser.add_argument("--ready-metric", default="window_appeared")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--artifact", action="append", default=[], type=Path)
    args = parser.parse_args()

    if sys.platform != "darwin":
        parser.error("benchmark-ios-sim.py is intended for macOS runs.")
    if args.samples < 1:
        parser.error("--samples must be at least 1.")
    if args.timeout <= 0:
        parser.error("--timeout must be greater than 0.")
    if args.settle < 0:
        parser.error("--settle must be greater than or equal to 0.")
    if not args.app.is_dir():
        parser.error(f"iOS app does not exist: {args.app}")
    for artifact in args.artifact:
        if not artifact.exists():
            parser.error(f"artifact does not exist: {artifact}")

    setup_started_at = time.monotonic()
    simulator = resolve_simulator(args.simulator)
    run(["xcrun", "simctl", "bootstatus", simulator, "-b"], timeout=180)
    run(["xcrun", "simctl", "install", simulator, str(args.app)], timeout=120)
    setup_seconds = time.monotonic() - setup_started_at

    runs = [
        run_sample(
            simulator=simulator,
            bundle_id=args.bundle_id,
            ready_metric=args.ready_metric,
            timeout=args.timeout,
            settle=args.settle,
        )
        for _ in range(args.samples)
    ]
    payload = {
        "app": str(args.app),
        "bundleID": args.bundle_id,
        "simulator": simulator,
        "artifacts": artifact_metadata(args.artifact or [args.app]),
        "artifactSizeMB": artifact_size_mb(args.artifact or [args.app]),
        "samples": args.samples,
        "setup": {
            "simulatorReadyBeforeSamples": True,
            "setupSeconds": round(setup_seconds, 3),
            "excludedFromMetrics": ["simulator boot", "simulator bootstatus wait", "app install"],
        },
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


def resolve_simulator(value: str) -> str:
    if value != "booted":
        run(["xcrun", "simctl", "boot", value], check=False, timeout=30)
        return value
    result = run(["xcrun", "simctl", "list", "devices", "booted", "-j"], capture=True)
    booted = json.loads(result.stdout)
    for devices in booted.get("devices", {}).values():
        for device in devices:
            if device.get("isAvailable") and device.get("udid"):
                return device["udid"]
    result = run(["xcrun", "simctl", "list", "devices", "available", "-j"], capture=True)
    available = json.loads(result.stdout)
    for runtime, devices in available.get("devices", {}).items():
        if "iOS" not in runtime:
            continue
        for device in devices:
            name = device.get("name", "")
            if device.get("isAvailable") and device.get("udid") and ("iPhone" in name or "iPad" in name):
                udid = device["udid"]
                run(["xcrun", "simctl", "boot", udid], check=False, timeout=30)
                return udid
    raise RuntimeError("No booted or available iOS simulator found.")


def run_sample(
    *,
    simulator: str,
    bundle_id: str,
    ready_metric: str,
    timeout: float,
    settle: float,
) -> dict:
    with tempfile.TemporaryDirectory(prefix="gui-for-cli-ios-bench-") as temp_dir:
        stdout_path = Path(temp_dir) / "stdout.log"
        stderr_path = Path(temp_dir) / "stderr.log"
        listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        listener.bind(("127.0.0.1", 0))
        listener.listen(1)
        listener.setblocking(False)
        port = listener.getsockname()[1]
        terminate_app(simulator, bundle_id)
        try:
            result = run(
                [
                    "xcrun",
                    "simctl",
                    "launch",
                    "--terminate-running-process",
                    f"--stdout={stdout_path}",
                    f"--stderr={stderr_path}",
                    simulator,
                    bundle_id,
                    "--benchmark",
                ],
                capture=True,
                timeout=30,
                env={
                    **os.environ,
                    "SIMCTL_CHILD_GFC_BENCHMARK_STARTUP": "1",
                    "SIMCTL_CHILD_GFC_BENCHMARK_PORT": str(port),
                },
            )
            pid = parse_launch_pid(result.stdout)
            started_at = time.monotonic()
            metrics: dict[str, float] = {}
            lines: list[str] = []
            while time.monotonic() - started_at < timeout:
                for line in receive_marker_lines(listener):
                    lines.append(line)
                    for metric_name, value in METRIC_RE.findall(line):
                        try:
                            metrics[metric_name] = float(value)
                        except ValueError:
                            continue
                file_lines = read_lines(stdout_path) + read_lines(stderr_path)
                for line in file_lines:
                    if line not in lines:
                        lines.append(line)
                    for metric_name, value in METRIC_RE.findall(line):
                        try:
                            metrics[metric_name] = float(value)
                        except ValueError:
                            continue
                if ready_metric in metrics:
                    time.sleep(settle)
                    break
                time.sleep(0.05)
            rss_kb = process_rss_kb(pid) if pid is not None else None
        finally:
            listener.close()
            terminate_app(simulator, bundle_id)
        return {
            "pid": pid,
            "metrics": metrics,
            "rssMB": round(rss_kb / 1024, 3) if rss_kb is not None else None,
            "output": lines,
        }


def parse_launch_pid(output: str) -> int | None:
    match = re.search(r":\s*(\d+)\s*$", output.strip())
    return int(match.group(1)) if match else None


def receive_marker_lines(listener: socket.socket) -> list[str]:
    ready, _, _ = select.select([listener], [], [], 0)
    if not ready:
        return []
    connection, _ = listener.accept()
    with connection:
        request = connection.recv(1024).decode("utf-8", errors="replace")
        connection.sendall(
            b"HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        )
    request_parts = request.split(" ", 2)
    path = request_parts[1] if len(request_parts) > 1 else ""
    query = path.partition("?")[2] if "?" in path else ""
    return [f"metric {item}" for item in query.split("&") if item]


def read_lines(path: Path) -> list[str]:
    if not path.exists():
        return []
    return path.read_text(errors="replace").splitlines()


def terminate_app(simulator: str, bundle_id: str) -> None:
    run(["xcrun", "simctl", "terminate", simulator, bundle_id], capture=True, check=False, timeout=30)


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
        resolved = path.resolve()
        size_bytes = path_size_bytes(resolved)
        artifacts.append(
            {
                "path": str(resolved),
                "kind": "app bundle" if resolved.is_dir() and resolved.suffix == ".app" else "directory"
                if resolved.is_dir()
                else "file",
                "sizeBytes": size_bytes,
                "sizeMB": round(size_bytes / 1_000_000, 3),
            }
        )
    return artifacts


def artifact_size_mb(paths: list[Path]) -> float | None:
    if not paths:
        return None
    return round(sum(path_size_bytes(path.resolve()) for path in paths) / 1_000_000, 3)


def path_size_bytes(path: Path) -> int:
    if path.is_file() or path.is_symlink():
        return path.stat().st_size
    total = 0
    for child in path.rglob("*"):
        if child.is_file() or child.is_symlink():
            total += child.stat().st_size
    return total


def run(
    command: list[str],
    *,
    capture: bool = False,
    check: bool = True,
    timeout: float | None = None,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        check=check,
        timeout=timeout,
        env=env,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None,
        text=True,
    )


if __name__ == "__main__":
    raise SystemExit(main())
