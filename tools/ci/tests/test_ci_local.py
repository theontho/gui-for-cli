import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import ci_local  # noqa: E402


class CILocalTests(unittest.TestCase):
    def apple_steps(self, skip_tuist_install: bool = True) -> list[ci_local.Step]:
        return [
            step
            for step in ci_local.steps(skip_tuist_install=skip_tuist_install)
            if "apple" in step.groups
        ]

    def test_fast_mode_skips_long_apple_steps(self) -> None:
        apple_steps = self.apple_steps(skip_tuist_install=False)
        fast_step_names = {step.name for step in apple_steps if not step.fast_skip}

        self.assertNotIn("swift test", fast_step_names)
        self.assertNotIn("build CLI release", fast_step_names)
        self.assertNotIn("tuist install", fast_step_names)
        self.assertNotIn("tuist generate", fast_step_names)
        self.assertNotIn("build iOS app", fast_step_names)
        self.assertNotIn("build macOS app", fast_step_names)
        for step in apple_steps:
            if step.name in fast_step_names:
                with self.subTest(step=step.name):
                    self.assertLessEqual(step.timeout_seconds or 0, 300)

    def test_apple_steps_have_timeouts(self) -> None:
        for step in self.apple_steps(skip_tuist_install=False):
            with self.subTest(step=step.name):
                self.assertIsNotNone(step.timeout_seconds)

    def test_apple_source_wiring_validation_runs_in_ci(self) -> None:
        step = next(
            step for step in ci_local.steps(skip_tuist_install=False) if step.name == "validate Apple source wiring"
        )

        self.assertIn("apple", step.groups)
        self.assertIn("meta", step.groups)
        self.assertEqual(step.command[-1], "tools/ci/validate_apple_source_wiring.py")

    def test_apple_swift_test_runs_serially(self) -> None:
        swift_test = next(
            step for step in self.apple_steps(skip_tuist_install=False) if step.name == "swift test"
        )

        self.assertNotIn("--parallel", swift_test.command)

    def test_typescript_step_uses_platform_npm_command(self) -> None:
        typescript_test = next(
            step for step in ci_local.steps(skip_tuist_install=True) if step.name == "typescript tests"
        )
        expected = "npm.cmd" if ci_local.CURRENT_OS == "windows" else "npm"

        self.assertEqual(typescript_test.command[0], expected)

    def test_make_help_step_uses_windows_shim_on_windows(self) -> None:
        make_help = next(
            step for step in ci_local.steps(skip_tuist_install=True) if step.name == "make help"
        )
        expected = "powershell.exe" if ci_local.CURRENT_OS == "windows" else "make"

        self.assertEqual(make_help.command[0], expected)


if __name__ == "__main__":
    unittest.main()
