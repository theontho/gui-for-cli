from __future__ import annotations

import os
import unittest
from pathlib import Path
from unittest import mock

from tools import worktree


class WorktreeToolTests(unittest.TestCase):
    def test_parse_worktrees_keeps_branch_and_paths_with_spaces(self) -> None:
        entries = worktree.parse_worktrees(
            "\n".join(
                (
                    "worktree /tmp/gui-for-cli",
                    "HEAD abc123",
                    "branch refs/heads/main",
                    "",
                    "worktree /tmp/gui for cli feature",
                    "HEAD def456",
                    "branch refs/heads/feature/worktree-setup",
                    "",
                )
            )
        )

        self.assertEqual(
            entries,
            [
                worktree.WorktreeEntry(Path("/tmp/gui-for-cli"), "main"),
                worktree.WorktreeEntry(Path("/tmp/gui for cli feature"), "feature/worktree-setup"),
            ],
        )

    def test_default_worktree_path_uses_sibling_root_and_safe_branch_name(self) -> None:
        root = Path("/Users/dev/src/gui-for-cli")

        self.assertEqual(
            worktree.default_worktree_path(root, "feature/worktree setup", ""),
            Path("/Users/dev/src/gui-for-cli-worktrees/feature-worktree-setup"),
        )

    def test_env_value_ignores_empty_make_exports(self) -> None:
        with mock.patch.dict(os.environ, {"WORKTREE_BASE": "", "BASE": ""}, clear=False):
            self.assertEqual(
                worktree.env_value("WORKTREE_BASE", "BASE", default="origin/main"),
                "origin/main",
            )


if __name__ == "__main__":
    unittest.main()
