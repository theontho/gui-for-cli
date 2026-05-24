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
            artifact = tmp_dir / "WGSExtract Web.app.tar.gz"
            artifact.write_text("archive\n", encoding="utf-8")
            (tmp_dir / "WGSExtract Web.app.tar.gz.sig").write_text("signature\n", encoding="utf-8")
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
                payload["platforms"]["darwin-aarch64"]["url"],
                "https://github.com/theontho/gui-for-cli/releases/download/v0.1.4/WGSExtract.Web.app.tar.gz",
            )
            self.assertEqual(payload["platforms"]["darwin-aarch64"]["signature"], "signature")
            self.assertNotIn("darwin-x86_64", payload["platforms"])

    def test_tauri_feed_maps_named_macos_archives_to_arch_platforms(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir_name:
            tmp_dir = Path(tmp_dir_name)
            for arch in ("x64", "aarch64"):
                artifact = tmp_dir / f"WGSExtract Web_{arch}.app.tar.gz"
                artifact.write_text("archive\n", encoding="utf-8")
                (tmp_dir / f"WGSExtract Web_{arch}.app.tar.gz.sig").write_text(
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

            self.assertTrue(wrote)
            payload = json.loads(output_path.read_text(encoding="utf-8"))
            self.assertEqual(payload["platforms"]["darwin-x86_64"]["signature"], "x64-signature")
            self.assertEqual(payload["platforms"]["darwin-aarch64"]["signature"], "aarch64-signature")

    def test_sparkle_appcast_uses_dmg_with_sparkle_signature(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir_name:
            tmp_dir = Path(tmp_dir_name)
            (tmp_dir / "WGSExtract Web_0.1.4_aarch64.dmg").write_text("tauri\n", encoding="utf-8")
            swiftui_dmg = tmp_dir / "WGSExtract-0.1.4.dmg"
            swiftui_dmg.write_text("swiftui\n", encoding="utf-8")
            (tmp_dir / "WGSExtract-0.1.4.dmg.sparkle-signature").write_text(
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
            self.assertIn("WGSExtract-0.1.4.dmg", appcast)
            self.assertNotIn("WGSExtract.Web_0.1.4_aarch64.dmg", appcast)

    def test_collect_artifacts_rejects_duplicate_names(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir_name:
            tmp_dir = Path(tmp_dir_name)
            (tmp_dir / "a").mkdir()
            (tmp_dir / "b").mkdir()
            (tmp_dir / "a" / "same.dmg").write_text("a\n", encoding="utf-8")
            (tmp_dir / "b" / "same.dmg").write_text("b\n", encoding="utf-8")

            with self.assertRaisesRegex(ValueError, "Duplicate release artifact names"):
                generate_update_feeds.collect_artifacts(tmp_dir)

    def test_release_asset_name_replaces_spaces(self) -> None:
        self.assertEqual(
            generate_update_feeds.release_asset_name("WGSExtract Web.app.tar.gz.sig"),
            "WGSExtract.Web.app.tar.gz.sig",
        )


if __name__ == "__main__":
    unittest.main()
