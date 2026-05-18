from __future__ import annotations

import os
import shutil
import unittest
from pathlib import Path

from gui_for_cli_runtime.bundle import load_bundle
from gui_for_cli_runtime.interpolation import CommandContext, condition_matches, display_command, row_context
from gui_for_cli_runtime.state import RuntimeState, build_core_state, hydrated_rows

REPO_ROOT = Path(__file__).resolve().parents[4]
CONFORMANCE_BUNDLE_ROOT = REPO_ROOT / "tests" / "conformance" / "basic-bundle"
SCRATCH = REPO_ROOT / "tmp" / "python-conformance-tests"


class ConformanceTests(unittest.TestCase):
    def setUp(self) -> None:
        shutil.rmtree(SCRATCH, ignore_errors=True)
        SCRATCH.mkdir(parents=True, exist_ok=True)
        self._old_workspace = os.environ.get("GUI_FOR_CLI_BUNDLE_WORKSPACE_ROOT")
        os.environ["GUI_FOR_CLI_BUNDLE_WORKSPACE_ROOT"] = str(SCRATCH / "workspaces")

    def tearDown(self) -> None:
        if self._old_workspace is None:
            os.environ.pop("GUI_FOR_CLI_BUNDLE_WORKSPACE_ROOT", None)
        else:
            os.environ["GUI_FOR_CLI_BUNDLE_WORKSPACE_ROOT"] = self._old_workspace
        shutil.rmtree(SCRATCH, ignore_errors=True)

    def test_conformance_bundle_preserves_shared_runtime_semantics(self) -> None:
        bundle = load_bundle(CONFORMANCE_BUNDLE_ROOT, REPO_ROOT, "en")
        manifest = bundle.manifest

        self.assertEqual(bundle.display_name, "Conformance Basic")
        self.assertEqual(manifest["summary"], "bundle.summary")
        self.assertEqual(bundle.strings.text(manifest["summary"]), "Exercises common bundle runtime semantics.")
        self.assertEqual(manifest["textIcon"], "🧪")
        self.assertEqual(manifest["sidebarIconStyle"], "emoji")
        self.assertEqual(bundle.terminal_text_direction, "ltr")
        self.assertEqual([page["id"] for page in manifest["pages"]], ["main"])
        self.assertEqual(bundle.strings.text(manifest["pages"][0]["title"]), "Main")
        self.assertEqual(bundle.strings.text(manifest["setup"]["steps"][0]["label"]), "Install dependencies")
        self.assertEqual(manifest["setup"]["steps"][0]["kind"], "setupScript")
        self.assertEqual(manifest["setup"]["steps"][0]["value"], "scripts/setup.sh")
        self.assertEqual(manifest["exitCodeReference"][0]["code"], 7)
        self.assertEqual(bundle.strings.text(manifest["exitCodeReference"][0]["title"]), "Custom warning")

        section = manifest["pages"][0]["sections"][0]
        input_control = next(control for control in section["controls"] if control["id"] == "input_path")
        refs = next(control for control in section["controls"] if control["id"] == "refs")
        settings = next(control for control in section["controls"] if control["id"] == "settings")
        run = next(action for action in section["actions"] if action["id"] == "run")

        self.assertEqual(bundle.strings.text(input_control["label"]), "Input BAM")
        self.assertEqual(input_control["value"], "/tmp/input.bam")
        self.assertEqual(settings["configFile"]["path"], "{{bundleWorkspace}}/settings/config.toml")
        self.assertEqual(settings["configFile"]["bootstrap"]["mode"], "createIfMissing")
        self.assertEqual(settings["settings"][0]["key"], "output_dir")

        state = RuntimeState.for_bundle(bundle)
        self.assertEqual(state.field_values["input_path"], "/tmp/input.bam")
        self.assertEqual(state.config_values["settings.out_dir"], "out")
        self.assertEqual(state.config_values["out_dir"], "out")

        rows = hydrated_rows(refs)
        self.assertEqual(rows, [{
            "id": "hg38",
            "title": "GRCh38",
            "status": "installed",
            "values": {"code": "hs38", "status": "installed"},
            "tags": [{"id": "recommended", "title": "Recommended", "style": "primary"}],
        }])

        context = CommandContext(
            field_values={"input_path": "/tmp/input.bam", "library.ready": "true"},
            checked_options={},
            config_values={"out_dir": "out"},
            row_values={**rows[0]["values"], "id": rows[0]["id"], "status": rows[0]["status"], "locked": "false"},
            bundle_root_path=str(CONFORMANCE_BUNDLE_ROOT),
            bundle_workspace_path=str(bundle.workspace_root),
            home_path=None,
        )

        self.assertTrue(condition_matches(run["visibleWhen"][0], context))
        self.assertFalse(condition_matches(run["disabledWhen"][0], context))
        self.assertEqual(display_command(run["command"], context), "tool run /tmp/input.bam out")

        row_action = refs["rowActions"][0]
        row_action_context = row_context(context, rows[0])
        self.assertTrue(condition_matches(row_action["visibleWhen"][0], row_action_context))
        self.assertFalse(condition_matches(row_action["disabledWhen"][0], row_action_context))
        self.assertEqual(display_command(row_action["command"], row_action_context), "tool verify hs38 /tmp/input.bam")

        core = build_core_state(bundle, state)
        self.assertEqual(core.control_count, 3)
        self.assertEqual(core.action_count, 2)
        self.assertEqual(core.terminal_text_direction, "ltr")

    def test_conformance_bundle_applies_requested_localization_overlays(self) -> None:
        bundle = load_bundle(CONFORMANCE_BUNDLE_ROOT, REPO_ROOT, "es")
        manifest = bundle.manifest

        self.assertEqual(bundle.locale, "es")
        self.assertEqual(bundle.display_name, "Conformidad básica")
        self.assertEqual(bundle.strings.text(manifest["pages"][0]["title"]), "Principal")
        self.assertEqual(bundle.strings.text(manifest["pages"][0]["sections"][0]["actions"][0]["title"]), "Ejecutar flujo")
        self.assertEqual(
            bundle.strings.text(manifest["summary"]),
            "Ejercita semánticas comunes de ejecución de paquetes.",
        )


if __name__ == "__main__":
    unittest.main()
