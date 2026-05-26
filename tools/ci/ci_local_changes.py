from __future__ import annotations

import argparse
import subprocess
import sys

import ci_changed_paths

try:
    from .ci_local_model import ALL_ZERO_SHA, LOCAL_GROUPS, REPO_ROOT
except ImportError:  # pragma: no cover - script execution path
    from ci_local_model import ALL_ZERO_SHA, LOCAL_GROUPS, REPO_ROOT


def git_stdout(args: list[str]) -> str | None:
    try:
        result = subprocess.run(
            ["git", *args],
            cwd=REPO_ROOT,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
    except subprocess.CalledProcessError:
        return None
    return result.stdout.strip()


def default_branch_ref() -> str | None:
    origin_head = git_stdout(["symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"])
    if origin_head:
        return origin_head
    for candidate in ("origin/main", "origin/master", "main", "master"):
        if git_stdout(["rev-parse", "--verify", "--quiet", candidate]):
            return candidate
    return None


def changed_paths_for_range(base: str, head: str) -> list[str] | None:
    return ci_changed_paths.git_changed_paths(base, head)


def changed_paths_from_pre_push(stdin: str) -> list[str] | None:
    paths: set[str] = set()
    saw_ref = False
    for line in stdin.splitlines():
        parts = line.split()
        if len(parts) < 4:
            continue
        _, local_sha, _, remote_sha = parts[:4]
        if not local_sha or local_sha == ALL_ZERO_SHA:
            continue
        saw_ref = True
        base = remote_sha
        if not base or base == ALL_ZERO_SHA:
            default_ref = default_branch_ref()
            base = git_stdout(["merge-base", local_sha, default_ref]) if default_ref else None
        if not base:
            return None
        changed = changed_paths_for_range(base, local_sha)
        if changed is None:
            return None
        paths.update(changed)
    if not saw_ref:
        return changed_paths_against_upstream()
    return sorted(paths)


def changed_paths_against_upstream() -> list[str] | None:
    upstream = git_stdout(["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"])
    if upstream:
        return changed_paths_for_range(upstream, "HEAD")
    default_ref = default_branch_ref()
    base = git_stdout(["merge-base", "HEAD", default_ref]) if default_ref else None
    return changed_paths_for_range(base, "HEAD") if base else None


def changed_paths_from_args(args: argparse.Namespace) -> list[str] | None:
    if args.path:
        return [ci_changed_paths.normalize_path(path) for path in args.path]
    if args.pre_push:
        if sys.stdin.isatty():
            raise SystemExit(
                "--pre-push expects refs on stdin; use --changed with --path/--base for manual checks."
            )
        return changed_paths_from_pre_push(sys.stdin.read())
    if args.base:
        return changed_paths_for_range(args.base, args.head)
    return changed_paths_against_upstream()


def selected_groups_from_changes(paths: list[str]) -> tuple[str, ...]:
    classified = ci_changed_paths.classify(paths)
    return tuple(group for group in LOCAL_GROUPS if classified.get(group, False))
