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

    def test_release_asset_name_replaces_spaces(self) -> None:
        self.assertEqual(
            generate_update_feeds.release_asset_name("WGSExtract Web.app.tar.gz.sig"),
            "WGSExtract.Web.app.tar.gz.sig",
        )


if __name__ == "__main__":
    unittest.main()
