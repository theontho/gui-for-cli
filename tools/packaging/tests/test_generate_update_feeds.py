from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from tools.packaging import generate_update_feeds


class GenerateUpdateFeedsTests(unittest.TestCase):
    def test_tauri_feed_uses_github_release_asset_names(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir_name:
            tmp_dir = Path(tmp_dir_name)
            artifact = tmp_dir / "WGSExtract Windows WebUI_0.1.4_x64-setup.exe"
            artifact.write_text("archive\n", encoding="utf-8")
            (tmp_dir / "WGSExtract Windows WebUI_0.1.4_x64-setup.exe.sig").write_text(
                "signature\n",
                encoding="utf-8",
            )
            output_path = tmp_dir / "latest.json"

            wrote = generate_update_feeds.write_tauri_latest_json(
                output_path,
                generate_update_feeds.collect_artifacts(tmp_dir),
                "0.1.4",
                "https://github.com/theontho/gui-for-cli/releases/download/v0.1.4",
            )

            self.assertTrue(wrote)
            payload = json.loads(output_path.read_text(encoding="utf-8"))
            self.assertEqual(
                payload["platforms"]["windows-x86_64"]["url"],
                "https://github.com/theontho/gui-for-cli/releases/download/v0.1.4/WGSExtract.Windows.WebUI_0.1.4_x64-setup.exe",
            )
            self.assertEqual(payload["platforms"]["windows-x86_64"]["signature"], "signature")
            self.assertNotIn("darwin-aarch64", payload["platforms"])

    def test_tauri_feed_ignores_macos_archives(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir_name:
            tmp_dir = Path(tmp_dir_name)
            for arch in ("x64", "aarch64"):
                artifact = tmp_dir / f"WGSExtract macOS WebUI_{arch}.app.tar.gz"
                artifact.write_text("archive\n", encoding="utf-8")
                (tmp_dir / f"WGSExtract macOS WebUI_{arch}.app.tar.gz.sig").write_text(
                    f"{arch}-signature\n",
                    encoding="utf-8",
                )
            output_path = tmp_dir / "latest.json"

            wrote = generate_update_feeds.write_tauri_latest_json(
                output_path,
                generate_update_feeds.collect_artifacts(tmp_dir),
                "0.1.4",
                "https://github.com/theontho/gui-for-cli/releases/download/v0.1.4",
            )

            self.assertFalse(wrote)
            self.assertFalse(output_path.exists())

    def test_sparkle_appcast_uses_dmg_with_sparkle_signature(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir_name:
            tmp_dir = Path(tmp_dir_name)
            (tmp_dir / "WGSExtract macOS WebUI_0.1.4_aarch64.dmg").write_text("tauri\n", encoding="utf-8")
            swiftui_dmg = tmp_dir / "WGSExtract macOS-0.1.4.dmg"
            swiftui_dmg.write_text("swiftui\n", encoding="utf-8")
            (tmp_dir / "WGSExtract macOS-0.1.4.dmg.sparkle-signature").write_text(
                'sparkle:edSignature="abc" length="8"',
                encoding="utf-8",
            )
            output_path = tmp_dir / "appcast.xml"

            wrote = generate_update_feeds.write_sparkle_appcast(
                output_path,
                generate_update_feeds.collect_artifacts(tmp_dir),
                "0.1.4",
                "https://github.com/theontho/gui-for-cli/releases/download/v0.1.4",
            )

            self.assertTrue(wrote)
            appcast = output_path.read_text(encoding="utf-8")
            self.assertIn("WGSExtract.macOS-0.1.4.dmg", appcast)
            self.assertNotIn("WGSExtract.macOS.WebUI_0.1.4_aarch64.dmg", appcast)

    def test_collect_artifacts_rejects_duplicate_names(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir_name:
            tmp_dir = Path(tmp_dir_name)
            (tmp_dir / "a").mkdir()
            (tmp_dir / "b").mkdir()
            (tmp_dir / "a" / "same.dmg").write_text("a\n", encoding="utf-8")
            (tmp_dir / "b" / "same.dmg").write_text("b\n", encoding="utf-8")

            with self.assertRaisesRegex(ValueError, "Duplicate release artifact names"):
                generate_update_feeds.collect_artifacts(tmp_dir)

    def test_collect_artifacts_ignores_unpacked_app_bundle_contents(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir_name:
            tmp_dir = Path(tmp_dir_name)
            app_contents = tmp_dir / "swiftui-macos" / "WGSExtract macOS.app" / "Contents"
            framework_contents = (
                tmp_dir
                / "swiftui-macos"
                / "WGSExtract macOS.app"
                / "Contents"
                / "Frameworks"
                / "Sparkle.framework"
                / "Versions"
                / "B"
            )
            app_contents.mkdir(parents=True)
            framework_contents.mkdir(parents=True)
            (app_contents / "Info.plist").write_text("app\n", encoding="utf-8")
            (framework_contents / "Info.plist").write_text("framework\n", encoding="utf-8")
            dmg = tmp_dir / "swiftui-macos" / "WGSExtract macOS-0.1.4.dmg"
            dmg.write_text("dmg\n", encoding="utf-8")

            artifacts = generate_update_feeds.collect_artifacts(tmp_dir)

            self.assertEqual(artifacts, {"WGSExtract macOS-0.1.4.dmg": dmg})

    def test_release_asset_name_replaces_spaces(self) -> None:
        self.assertEqual(
            generate_update_feeds.release_asset_name("WGSExtract Windows WebUI_0.1.4_x64-setup.exe.sig"),
            "WGSExtract.Windows.WebUI_0.1.4_x64-setup.exe.sig",
        )


if __name__ == "__main__":
    unittest.main()
