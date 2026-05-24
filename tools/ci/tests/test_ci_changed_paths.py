import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import ci_changed_paths  # noqa: E402


class CIChangedPathsTests(unittest.TestCase):
    def classify(self, *paths: str) -> dict[str, bool]:
        return ci_changed_paths.classify(list(paths))

    def test_webui_source_changes_skip_windows_shell_packaging(self) -> None:
        outputs = self.classify("platform/typescript/web/src/client/view/setup.ts")

        self.assertTrue(outputs["typescript"])
        self.assertTrue(outputs["windows"])
        self.assertTrue(outputs["windows_webui"])
        self.assertFalse(outputs["windows_dioxus"])
        self.assertFalse(outputs["windows_tauri"])

    def test_bundle_changes_skip_windows_shell_packaging(self) -> None:
        outputs = self.classify("examples/WGSExtract/pages/library.json")

        self.assertTrue(outputs["apple"])
        self.assertTrue(outputs["typescript"])
        self.assertTrue(outputs["windows_webui"])
        self.assertFalse(outputs["windows_dioxus"])
        self.assertFalse(outputs["windows_tauri"])

    def test_tauri_packager_changes_run_tauri_installer(self) -> None:
        outputs = self.classify("platform/typescript/web/packagers/tauri/src/main.rs")

        self.assertTrue(outputs["typescript"])
        self.assertTrue(outputs["windows_webui"])
        self.assertTrue(outputs["windows_tauri"])

    def test_windows_tauri_update_validator_changes_run_tauri_installer(self) -> None:
        outputs = self.classify("scripts/validate-windows-tauri-update.ps1")

        self.assertTrue(outputs["windows_tauri"])


if __name__ == "__main__":
    unittest.main()
