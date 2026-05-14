#!/usr/bin/env python3
"""Benchmark the Android Compose app after a device or emulator is booted and ready."""

from __future__ import annotations

import argparse
import json
import os
import re
import statistics
import subprocess
import sys
import time
from pathlib import Path

METRIC_RE = re.compile(r"ui_ready_ms=([0-9]+(?:\.[0-9]+)?)")


def main() -> int:
    parser = argparse.ArgumentParser(description="Benchmark GUI for CLI Android Compose startup.")
    parser.add_argument("--apk", required=True, type=Path)
    parser.add_argument("--package", default="dev.guiforcli.compose.android")
    parser.add_argument("--activity", default="dev.guiforcli.compose.android/.MainActivity")
    parser.add_argument("--samples", type=int, default=7)
    parser.add_argument("--timeout", type=float, default=45.0)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--adb", type=Path, default=default_android_tool("platform-tools/adb"))
    parser.add_argument("--emulator", type=Path, default=default_android_tool("emulator/emulator"))
    parser.add_argument("--avd", default=os.environ.get("ANDROID_AVD"))
    args = parser.parse_args()

    if args.samples < 1:
        parser.error("--samples must be at least 1.")
    if not args.apk.is_file():
        parser.error(f"APK does not exist: {args.apk}")
    if not args.adb.is_file():
        parser.error(f"adb does not exist: {args.adb}")

    setup_started_at = time.monotonic()
    setup = ensure_device(args)
    run([str(args.adb), "install", "-r", str(args.apk)], timeout=120)
    setup["setupSeconds"] = round(time.monotonic() - setup_started_at, 3)
    setup["deviceReadyBeforeSamples"] = True
    setup["excludedFromMetrics"] = ["emulator launch", "emulator boot wait", "APK install"]
    runs = [run_sample(args) for _ in range(args.samples)]
    payload = {
        "apk": str(args.apk),
        "package": args.package,
        "activity": args.activity,
        "samples": args.samples,
        "setup": setup,
        "medians": median_metrics(runs),
        "runs": runs,
    }
    text = json.dumps(payload, indent=2)
    print(text)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text + "\n", encoding="utf-8")
    if any("uiReadyMs" not in run for run in runs):
        print("error: one or more Android runs did not report ui_ready_ms", file=sys.stderr)
        return 1
    return 0


def default_android_tool(relative: str) -> Path:
    root = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT") or str(Path.home() / "Library/Android/sdk")
    return Path(root) / relative


def ensure_device(args: argparse.Namespace) -> dict:
    if connected_device(args.adb):
        return {"emulatorStarted": False, "deviceAlreadyConnected": True, "avd": None}
    avd = args.avd or first_avd(args.emulator)
    if not avd:
        raise RuntimeError("No attached Android device and no AVD available.")
    subprocess.Popen(
        [str(args.emulator), "-avd", avd, "-no-snapshot-save", "-no-audio", "-no-boot-anim"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    run([str(args.adb), "wait-for-device"], timeout=180)
    deadline = time.monotonic() + 240
    while time.monotonic() < deadline:
        result = run([str(args.adb), "shell", "getprop", "sys.boot_completed"], capture=True, check=False, timeout=10)
        if result.stdout.strip() == "1":
            return {"emulatorStarted": True, "deviceAlreadyConnected": False, "avd": avd}
        time.sleep(2)
    raise TimeoutError(f"Timed out waiting for Android emulator {avd} to boot.")


def connected_device(adb: Path) -> bool:
    result = run([str(adb), "devices"], capture=True, check=False)
    return any(line.strip().endswith("\tdevice") for line in result.stdout.splitlines())


def first_avd(emulator: Path) -> str | None:
    if not emulator.is_file():
        return None
    result = run([str(emulator), "-list-avds"], capture=True, check=False)
    return next((line.strip() for line in result.stdout.splitlines() if line.strip()), None)


def run_sample(args: argparse.Namespace) -> dict:
    run([str(args.adb), "shell", "am", "force-stop", args.package], check=False, timeout=30)
    run([str(args.adb), "logcat", "-c"], check=False, timeout=30)
    run(
        [
            str(args.adb),
            "shell",
            "am",
            "start",
            "-W",
            "-n",
            args.activity,
            "--es",
            "benchmark",
            "true",
            "--es",
            "benchmark_once",
            "true",
        ],
        timeout=30,
    )
    deadline = time.monotonic() + args.timeout
    output = ""
    metric: float | None = None
    while time.monotonic() < deadline:
        output = run(
            [str(args.adb), "logcat", "-d", "-s", "GFCBenchmark:I", "*:S"],
            capture=True,
            check=False,
            timeout=10,
        ).stdout
        match = METRIC_RE.search(output)
        if match:
            metric = float(match.group(1))
            break
        time.sleep(0.1)
    rss_mb = read_rss_mb(args.adb, args.package)
    run([str(args.adb), "shell", "am", "force-stop", args.package], check=False, timeout=30)
    return {
        "uiReadyMs": metric,
        "rssMB": rss_mb,
        "output": output.splitlines(),
    }


def read_rss_mb(adb: Path, package: str) -> float | None:
    result = run([str(adb), "shell", "dumpsys", "meminfo", package], capture=True, check=False, timeout=20)
    for line in result.stdout.splitlines():
        stripped = line.strip()
        if stripped.startswith("TOTAL "):
            parts = stripped.split()
            if len(parts) > 1 and parts[1].isdigit():
                return round(int(parts[1]) / 1024, 3)
    return None


def median_metrics(runs: list[dict]) -> dict:
    metrics = {}
    ui_values = [run["uiReadyMs"] for run in runs if run.get("uiReadyMs") is not None]
    if ui_values:
        metrics["uiReadyMs"] = statistics.median(ui_values)
    rss_values = [run["rssMB"] for run in runs if run.get("rssMB") is not None]
    if rss_values:
        metrics["rssMB"] = statistics.median(rss_values)
    return metrics


def run(
    command: list[str],
    *,
    capture: bool = False,
    check: bool = True,
    timeout: float | None = None,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        check=check,
        timeout=timeout,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None,
        text=True,
    )


if __name__ == "__main__":
    raise SystemExit(main())
