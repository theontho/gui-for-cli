from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path

from tools.packaging.git_filters import copy_git_filtered


class TestGitFilters(unittest.TestCase):
    def test_copy_git_filtered_excludes_gitignored_files(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir_name:
            repo_root = Path(tmp_dir_name) / "repo"
            src_dir = repo_root / "bundle"
            dest_dir = Path(tmp_dir_name) / "copied"

            (src_dir / "output").mkdir(parents=True)
            (src_dir / "manifest.json").write_text("{}\n", encoding="utf-8")
            (src_dir / "notes.txt").write_text("include me\n", encoding="utf-8")
            (src_dir / "output/cache.bin").write_text("ignore me\n", encoding="utf-8")
            (repo_root / ".gitignore").write_text("bundle/output/\n", encoding="utf-8")

            self.run_git(repo_root, "init")
            self.run_git(repo_root, "add", ".gitignore", "bundle/manifest.json")

            success = copy_git_filtered(src_dir, dest_dir, repo_root)
            self.assertTrue(success)

            self.assertTrue((dest_dir / "manifest.json").exists())
            self.assertTrue((dest_dir / "notes.txt").exists())
            self.assertFalse((dest_dir / "output").exists())

    def test_copy_git_filtered_returns_false_for_external_directory(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir_name:
            root = Path(tmp_dir_name)
            repo_root = root / "repo"
            external = root / "external"
            repo_root.mkdir()
            external.mkdir()

            self.run_git(repo_root, "init")

            self.assertFalse(copy_git_filtered(external, root / "copied", repo_root))

    @staticmethod
    def run_git(repo_root: Path, *args: str) -> None:
        subprocess.run(
            ["git", *args],
            cwd=repo_root,
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
