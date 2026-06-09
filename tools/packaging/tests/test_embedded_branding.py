from __future__ import annotations

import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from tools.packaging.embedded_branding import (
    apple_embedded_branding,
    app_name_without_distribution_suffix,
    load_embedded_branding,
    macos_swiftui_app_name,
    tauri_webui_app_name,
)


class EmbeddedBrandingTests(unittest.TestCase):
    def test_macos_swiftui_app_name_uses_base_name(self) -> None:
        self.assertEqual(
            macos_swiftui_app_name("WGSExtract"),
            "WGSExtract",
        )
        self.assertEqual(
            macos_swiftui_app_name("WGSExtract macOS"),
            "WGSExtract",
        )

    def test_tauri_webui_app_name_only_marks_macos_webui(self) -> None:
        self.assertEqual(
            tauri_webui_app_name("WGSExtract", "darwin"),
            "WGSExtract WebUI",
        )
        self.assertEqual(
            tauri_webui_app_name("WGSExtract", "linux"),
            "WGSExtract",
        )
        self.assertEqual(
            tauri_webui_app_name("WGSExtract", "linux-appimage"),
            "WGSExtract",
        )
        self.assertEqual(
            tauri_webui_app_name("WGSExtract", "ubuntu"),
            "WGSExtract",
        )
        self.assertEqual(
            tauri_webui_app_name("WGSExtract", "fedora"),
            "WGSExtract",
        )
        self.assertEqual(
            tauri_webui_app_name("WGSExtract", "arch"),
            "WGSExtract",
        )
        self.assertEqual(
            tauri_webui_app_name("WGSExtract", "win32"),
            "WGSExtract",
        )

    def test_apple_identity_keeps_base_bundle_identifier_name(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir_name:
            repo_root = Path(tmp_dir_name)
            bundle = repo_root / "examples/WGSExtract"
            bundle.mkdir(parents=True)
            (bundle / "manifest.json").write_text(
                json.dumps({"id": "wgs-extract", "version": "0.1.4"}),
                encoding="utf-8",
            )
            env = {
                "EMBEDDED_APP_NAME": "",
                "EMBEDDED_BUNDLE_PATH": "",
                "PACKAGE_BUNDLE_PATH": "examples/WGSExtract",
                "PACKAGE_APP_NAME": "WGSExtract",
            }

            with patch.dict(os.environ, env, clear=False):
                with apple_embedded_branding(repo_root):
                    identity = json.loads(
                        (repo_root / "tmp/app-identity.json").read_text(encoding="utf-8")
                    )

            self.assertEqual(identity["displayName"], "WGSExtract")
            self.assertEqual(identity["productName"], "WGSExtract")
            self.assertEqual(identity["bundleIdentifierName"], "WGSExtract")

    def test_apple_identity_strips_distribution_suffix_from_bundle_identifier_name(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir_name:
            repo_root = Path(tmp_dir_name)
            bundle = repo_root / "examples/WGSExtract"
            bundle.mkdir(parents=True)
            (bundle / "manifest.json").write_text(
                json.dumps({"id": "wgs-extract", "version": "0.1.4"}),
                encoding="utf-8",
            )
            env = {
                "EMBEDDED_APP_NAME": "",
                "EMBEDDED_BUNDLE_PATH": "",
                "PACKAGE_BUNDLE_PATH": "examples/WGSExtract",
                "PACKAGE_APP_NAME": "WGSExtract macOS",
            }

            with patch.dict(os.environ, env, clear=False):
                with apple_embedded_branding(repo_root):
                    identity = json.loads(
                        (repo_root / "tmp/app-identity.json").read_text(encoding="utf-8")
                    )

            self.assertEqual(identity["displayName"], "WGSExtract")
            self.assertEqual(identity["productName"], "WGSExtract")
            self.assertEqual(identity["bundleIdentifierName"], "WGSExtract")

    def test_app_name_without_distribution_suffix_strips_known_suffixes(self) -> None:
        self.assertEqual(
            app_name_without_distribution_suffix("WGSExtract macOS WebUI"),
            "WGSExtract",
        )
        self.assertEqual(
            app_name_without_distribution_suffix("WGSExtract Linux AppImage WebUI"),
            "WGSExtract",
        )
        self.assertEqual(
            app_name_without_distribution_suffix("WGSExtract"),
            "WGSExtract",
        )

    def test_load_embedded_branding_accepts_manifest_comments(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir_name:
            repo_root = Path(tmp_dir_name)
            bundle = repo_root / "examples/WGSExtract"
            bundle.mkdir(parents=True)
            (bundle / "manifest.json").write_text(
                """
                {
                  "id": "wgs-extract",
                  // Keep bundle and tool versions in sync.
                  "version": "0.3.8",
                  "summary": "https://example.com/not-a-comment"
                }
                """,
                encoding="utf-8",
            )
            env = {
                "EMBEDDED_APP_NAME": "",
                "EMBEDDED_BUNDLE_PATH": "",
                "PACKAGE_BUNDLE_PATH": "examples/WGSExtract",
                "PACKAGE_APP_NAME": "",
                "PACKAGE_APP_VERSION": "",
                "EMBEDDED_APP_VERSION": "",
            }

            with patch.dict(os.environ, env, clear=False), patch(
                "tools.packaging.embedded_branding.get_path", return_value=""
            ):
                branding = load_embedded_branding(repo_root)

            self.assertEqual(branding.effective_app_version, "0.3.8")


if __name__ == "__main__":
    unittest.main()
