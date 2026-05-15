#!/usr/bin/env python3
import argparse
import json
import os
import pathlib
import statistics
import subprocess
import sys
import tempfile
import time


def app_size_mb(app_path: pathlib.Path) -> float:
    output = subprocess.check_output(["du", "-sk", str(app_path)], text=True)
    return int(output.split()[0]) / 1024


def read_rss_mb(pid: int) -> float | None:
    try:
        output = subprocess.check_output(["ps", "-o", "rss=", "-p", str(pid)], text=True)
    except subprocess.CalledProcessError:
        return None
    output = output.strip()
    return int(output) / 1024 if output else None


def parse_internal_ms(marker_path: pathlib.Path, metric: str) -> float:
    for line in reversed(marker_path.read_text().splitlines()):
        if line.startswith(f"{metric}="):
            return float(line.split("=", 1)[1])
    raise RuntimeError(f"missing {metric} in {marker_path}")


def terminate(process: subprocess.Popen[str]) -> None:
    if process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=2)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=2)


def benchmark_run(
    executable: pathlib.Path,
    timeout_seconds: float,
    marker_override: pathlib.Path | None,
    metric: str,
) -> tuple[float, float, float | None]:
    with tempfile.TemporaryDirectory(prefix="gui-for-cli-flutter-bench-") as temp_dir:
        marker_path = marker_override or pathlib.Path(temp_dir) / "benchmark.txt"
        marker_path.parent.mkdir(parents=True, exist_ok=True)
        marker_path.unlink(missing_ok=True)
        log_path = pathlib.Path(temp_dir) / "stderr.log"
        env = dict(os.environ)
        env["GFC_BENCHMARK_OUTPUT"] = str(marker_path)
        started = time.perf_counter()
        with log_path.open("w") as stderr:
            process = subprocess.Popen([str(executable)], stdout=subprocess.DEVNULL, stderr=stderr, env=env, text=True)
        try:
            while time.perf_counter() - started < timeout_seconds:
                if marker_path.exists() and f"{metric}=" in marker_path.read_text():
                    external_ms = (time.perf_counter() - started) * 1000
                    rss_mb = read_rss_mb(process.pid)
                    internal_ms = parse_internal_ms(marker_path, metric)
                    return external_ms, internal_ms, rss_mb
                if process.poll() is not None:
                    stderr_text = log_path.read_text(errors="replace")
                    raise RuntimeError(f"Flutter app exited before writing benchmark marker:\n{stderr_text}")
                time.sleep(0.005)
            stderr_text = log_path.read_text(errors="replace")
            raise TimeoutError(
                f"Timed out waiting for Flutter benchmark marker after {timeout_seconds:.1f}s:\n{stderr_text}"
            )
        finally:
            terminate(process)


def median(values: list[float]) -> float:
    return statistics.median(values)


def main() -> int:
    parser = argparse.ArgumentParser(description="Benchmark Flutter macOS first-frame startup.")
    parser.add_argument("app", type=pathlib.Path, help="Path to gui_for_cli_flutter.app")
    parser.add_argument("--runs", type=int, default=7)
    parser.add_argument("--timeout", type=float, default=10)
    parser.add_argument("--marker", type=pathlib.Path, help="Benchmark marker path baked into the app")
    parser.add_argument("--metric", default="flutter.contentReadyMs")
    parser.add_argument("--output", type=pathlib.Path)
    args = parser.parse_args()

    executable = args.app / "Contents" / "MacOS" / "gui_for_cli_flutter"
    if not executable.exists():
        print(f"Missing Flutter app executable: {executable}", file=sys.stderr)
        return 2

    external_values: list[float] = []
    internal_values: list[float] = []
    rss_values: list[float] = []
    runs: list[dict] = []
    print(f"metric={args.metric}")
    for run in range(1, args.runs + 1):
        external_ms, internal_ms, rss_mb = benchmark_run(
            executable, args.timeout, args.marker, args.metric
        )
        external_values.append(external_ms)
        internal_values.append(internal_ms)
        if rss_mb is not None:
            rss_values.append(rss_mb)
        runs.append(
            {
                "externalContentReadyMs": round(external_ms, 3),
                "metrics": {args.metric: round(internal_ms, 3)},
                "rssMB": round(rss_mb, 3) if rss_mb is not None else None,
            }
        )
        rss_text = f"{rss_mb:.1f} MB RSS" if rss_mb is not None else "RSS unavailable"
        print(f"run {run}: external={external_ms:.1f} ms internal={internal_ms:.1f} ms {rss_text}")

    print(f"median_external_ms={median(external_values):.1f}")
    print(f"median_internal_ms={median(internal_values):.1f}")
    if rss_values:
        print(f"median_rss_mb={median(rss_values):.1f}")
    print(f"app_size_mb={app_size_mb(args.app):.1f}")
    artifact_size_bytes = path_size_bytes(args.app)
    payload = {
        "app": str(args.app.resolve()),
        "executable": str(executable.resolve()),
        "artifacts": [
            {
                "path": str(args.app.resolve()),
                "kind": "app bundle",
                "sizeBytes": artifact_size_bytes,
                "sizeMB": round(artifact_size_bytes / 1_000_000, 3),
            }
        ],
        "artifactSizeMB": round(artifact_size_bytes / 1_000_000, 3),
        "samples": args.runs,
        "medians": {
            "externalContentReadyMs": median(external_values),
            args.metric: median(internal_values),
            **({"rssMB": median(rss_values)} if rss_values else {}),
        },
        "runs": runs,
    }
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    return 0


def path_size_bytes(path: pathlib.Path) -> int:
    if path.is_file() or path.is_symlink():
        return path.stat().st_size
    total = 0
    for child in path.rglob("*"):
        if child.is_file() or child.is_symlink():
            total += child.stat().st_size
    return total


if __name__ == "__main__":
    raise SystemExit(main())
