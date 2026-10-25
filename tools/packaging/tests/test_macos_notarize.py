from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "posix"))
import macos_notarize  # noqa: E402

API_KEY_ENV = {"APPLE_API_KEY": "KEY123", "APPLE_API_ISSUER": "issuer-uuid", "APPLE_API_KEY_PATH": "/tmp/AuthKey.p8"}


class NotarytoolCredentialTests(unittest.TestCase):
    def test_prefers_the_api_key(self) -> None:
        env = {**API_KEY_ENV, "APPLE_ID": "me@example.com", "APPLE_PASSWORD": "pw", "APPLE_TEAM_ID": "TEAM"}
        self.assertEqual(
            macos_notarize.notarytool_credentials(env),
            ["--key", "/tmp/AuthKey.p8", "--key-id", "KEY123", "--issuer", "issuer-uuid"],
        )

    def test_falls_back_to_apple_id(self) -> None:
        env = {"APPLE_ID": "me@example.com", "APPLE_PASSWORD": "pw", "APPLE_TEAM_ID": "TEAM"}
        self.assertEqual(
            macos_notarize.notarytool_credentials(env),
            ["--apple-id", "me@example.com", "--password", "pw", "--team-id", "TEAM"],
        )

    def test_incomplete_credentials_are_none(self) -> None:
        self.assertIsNone(macos_notarize.notarytool_credentials({"APPLE_API_KEY": "KEY123"}))


class NotarizeDmgTests(unittest.TestCase):
    def test_submits_then_staples_each_dmg(self) -> None:
        with mock.patch.object(macos_notarize, "run") as run:
            macos_notarize.notarize_dmgs([Path("/out/App_1.0_aarch64.dmg")], API_KEY_ENV)
        self.assertEqual(
            [call.args[0][:3] for call in run.call_args_list],
            [["xcrun", "notarytool", "submit"], ["xcrun", "stapler", "staple"]],
        )
        self.assertIn("--wait", run.call_args_list[0].args[0])

    def test_skips_without_credentials_unless_required(self) -> None:
        with mock.patch.object(macos_notarize, "run") as run:
            macos_notarize.notarize_dmgs([Path("/out/App.dmg")], {})
        run.assert_not_called()
        with self.assertRaises(SystemExit):
            macos_notarize.notarize_dmgs([Path("/out/App.dmg")], {"PACKAGE_REQUIRE_MACOS_SIGNING": "1"})


if __name__ == "__main__":
    unittest.main()
