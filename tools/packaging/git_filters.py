from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path


def copy_git_filtered(src: Path, dest: Path, repo_root: Path) -> bool:
    """Copy src to dest using only git-tracked and unignored files."""
    src = Path(src).resolve()
    dest = Path(dest).resolve()
    repo_root = Path(repo_root).resolve()

    if not src.exists():
        return False

    if not src.is_dir():
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dest)
        return True

    try:
        rel_src = src.relative_to(repo_root)
    except ValueError:
        return False

    files = git_visible_files(rel_src, repo_root)
    if not files:
        return False

    if dest.exists() or dest.is_symlink():
        if dest.is_dir() and not dest.is_symlink():
            shutil.rmtree(dest)
        else:
            dest.unlink()

    for repo_path in files:
        file_src = (repo_root / repo_path).resolve()
        if not file_src.is_file():
            continue
        try:
            rel_to_src = file_src.relative_to(src)
        except ValueError:
            continue
        file_dest = dest / rel_to_src
        file_dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(file_src, file_dest)
    return True


def git_visible_files(rel_src: Path, repo_root: Path) -> list[Path]:
    try:
        result = subprocess.run(
            [
                "git",
                "ls-files",
                "--cached",
                "--others",
                "--exclude-standard",
                "--",
                str(rel_src),
            ],
            cwd=repo_root,
            capture_output=True,
            text=True,
            check=True,
        )
    except FileNotFoundError:
        print("Git-filtered copy unavailable: git was not found", file=sys.stderr)
        return []
    except subprocess.CalledProcessError as error:
        stderr = error.stderr.strip()
        message = f": {stderr}" if stderr else ""
        print(
            f"Git-filtered copy failed for {repo_root / rel_src}{message}",
            file=sys.stderr,
        )
        return []
    return [Path(line) for line in result.stdout.splitlines() if line.strip()]
