from __future__ import annotations

import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import tools.sync_apple_built_resources as built_resources


@unittest.skipIf(shutil.which("git") is None, "git is required for resource sync tests")
class TestSyncAppleBuiltResources(unittest.TestCase):
    def test_custom_bundle_uses_branding_source_not_ignored_shared_copy(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir_name:
            repo_root = Path(tmp_dir_name) / "repo"
            custom_bundle = repo_root / "examples/CustomBundle"
            ignored_shared_bundle = (
                repo_root
                / "platform/apple/shared/Sources/GUIForCLICore/Resources/DemoBundles/EmbeddedBundle"
            )
            app_bundle = Path(tmp_dir_name) / "App.app"
            contents_resources = app_bundle / "Contents/Resources"

            (repo_root / "resources/BuiltinStrings").mkdir(parents=True)
            (repo_root / "resources/BuiltinIconMap").mkdir(parents=True)
            (repo_root / "examples/WGSExtract").mkdir(parents=True)
            custom_bundle.mkdir(parents=True)
            ignored_shared_bundle.mkdir(parents=True)
            contents_resources.mkdir(parents=True)

            (custom_bundle / "manifest.json").write_text(
                '{"name":"custom"}\n', encoding="utf-8"
            )
            (ignored_shared_bundle / "manifest.json").write_text(
                '{"name":"ignored"}\n', encoding="utf-8"
            )
            (repo_root / ".gitignore").write_text(
                "platform/apple/shared/Sources/GUIForCLICore/Resources/DemoBundles/EmbeddedBundle\n",
                encoding="utf-8",
            )

            self.run_git(repo_root, "init")
            self.run_git(
                repo_root,
                "add",
                ".gitignore",
                "examples/CustomBundle/manifest.json",
            )

            branding = SimpleNamespace(bundle_path=custom_bundle)
            with patch.object(built_resources, "REPO_ROOT", repo_root), patch.object(
                built_resources, "load_embedded_branding", return_value=branding
            ):
                built_resources.sync_into(app_bundle)

            copied_manifest = (
                contents_resources
                / "Resources/DemoBundles/EmbeddedBundle/manifest.json"
            )
            self.assertEqual(
                copied_manifest.read_text(encoding="utf-8"), '{"name":"custom"}\n'
            )

    @staticmethod
    def run_git(repo_root: Path, *args: str) -> None:
        subprocess.run(
            ["git", *args],
            cwd=repo_root,
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
