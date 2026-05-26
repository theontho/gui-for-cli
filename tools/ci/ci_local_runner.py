from __future__ import annotations

import subprocess
import time

try:
    from .ci_local_model import CURRENT_OS, REPO_ROOT, SWIFT_GIT_ENV, Step
except ImportError:  # pragma: no cover - script execution path
    from ci_local_model import CURRENT_OS, REPO_ROOT, SWIFT_GIT_ENV, Step


def filter_supported_steps(plan: list[Step]) -> list[Step]:
    supported: list[Step] = []
    for step in plan:
        if step.platforms and CURRENT_OS not in step.platforms:
            allowed = ", ".join(step.platforms)
            print(f"Skipping {step.name} on {CURRENT_OS}; supported on {allowed}.")
            continue
        supported.append(step)
    return supported


def run_step(step: Step, env: dict[str, str]) -> tuple[bool, float]:
    print(f"\n\033[1;36m▶ {step.name}\033[0m")
    print(f"  $ {' '.join(step.command)}")
    if step.timeout_seconds is not None:
        print(f"  timeout: {step.timeout_seconds}s")
    start = time.monotonic()
    try:
        step_env = env.copy()
        if step.command and step.command[0] == "swift":
            step_env.update(SWIFT_GIT_ENV)
        proc = subprocess.run(
            step.command,
            cwd=REPO_ROOT,
            env=step_env,
            check=False,
            timeout=step.timeout_seconds,
        )
    except FileNotFoundError as exc:
        elapsed = time.monotonic() - start
        print(f"\033[1;31m  missing tool: {exc}\033[0m")
        return False, elapsed
    except subprocess.TimeoutExpired:
        elapsed = time.monotonic() - start
        timeout = step.timeout_seconds if step.timeout_seconds is not None else elapsed
        print(f"\033[1;31m  ✗ timed out after {timeout}s ({elapsed:.1f}s elapsed)\033[0m")
        return False, elapsed
    elapsed = time.monotonic() - start
    if proc.returncode != 0:
        print(f"\033[1;31m  ✗ failed ({elapsed:.1f}s)\033[0m")
        return False, elapsed
    print(f"\033[1;32m  ✓ ok ({elapsed:.1f}s)\033[0m")
    return True, elapsed
