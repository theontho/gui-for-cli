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
    macos_swiftui_app_name,
    tauri_webui_app_name,
)


class EmbeddedBrandingTests(unittest.TestCase):
    def test_macos_swiftui_app_name_includes_distribution(self) -> None:
        self.assertEqual(
            macos_swiftui_app_name("WGSExtract"),
            "WGSExtract macOS",
        )
        self.assertEqual(
            macos_swiftui_app_name("WGSExtract macOS"),
            "WGSExtract macOS",
        )

    def test_tauri_webui_app_name_includes_platform_and_distribution(self) -> None:
        self.assertEqual(
            tauri_webui_app_name("WGSExtract", "darwin"),
            "WGSExtract macOS WebUI",
        )
        self.assertEqual(
            tauri_webui_app_name("WGSExtract", "linux"),
            "WGSExtract Linux WebUI",
        )
        self.assertEqual(
            tauri_webui_app_name("WGSExtract", "linux-appimage"),
            "WGSExtract Linux AppImage WebUI",
        )
        self.assertEqual(
            tauri_webui_app_name("WGSExtract", "ubuntu"),
            "WGSExtract Ubuntu WebUI",
        )
        self.assertEqual(
            tauri_webui_app_name("WGSExtract", "fedora"),
            "WGSExtract Fedora WebUI",
        )
        self.assertEqual(
            tauri_webui_app_name("WGSExtract", "arch"),
            "WGSExtract Arch WebUI",
        )
        self.assertEqual(
            tauri_webui_app_name("WGSExtract", "win32"),
            "WGSExtract Windows WebUI",
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

            self.assertEqual(identity["displayName"], "WGSExtract macOS")
            self.assertEqual(identity["productName"], "WGSExtract macOS")
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

            self.assertEqual(identity["displayName"], "WGSExtract macOS")
            self.assertEqual(identity["productName"], "WGSExtract macOS")
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


if __name__ == "__main__":
    unittest.main()
