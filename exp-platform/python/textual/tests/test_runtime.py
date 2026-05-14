from __future__ import annotations

import json
import os
import shutil
import unittest
import zipfile
from pathlib import Path

from gui_for_cli_textual.runtime.bundle import load_bundle
from gui_for_cli_textual.runtime.interpolation import CommandContext, display_command, missing_placeholders, rendered_command
from gui_for_cli_textual.runtime.localization import StringTable
from gui_for_cli_textual.runtime.state import RuntimeState, build_core_state

REPO_ROOT = Path(__file__).resolve().parents[4]
SCRATCH = REPO_ROOT / "tmp" / "textual-tests"


class RuntimeTests(unittest.TestCase):
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

    def test_loads_directory_bundle_and_localizes_missing_keys(self) -> None:
        bundle_dir = write_bundle(SCRATCH / "localized-bundle")
        bundle = load_bundle(bundle_dir, REPO_ROOT, "en-US")

        self.assertEqual(bundle.display_name, "Demo Bundle")
        self.assertEqual(bundle.strings.text("missing.key"), "missing.key")
        self.assertEqual(bundle.manifest["pages"][0]["id"], "main")
        self.assertTrue(str(bundle.workspace_root).startswith(str(SCRATCH / "workspaces")))

    def test_loads_archive_bundle_with_top_level_directory(self) -> None:
        bundle_dir = write_bundle(SCRATCH / "source" / "demo")
        archive_path = SCRATCH / "demo.gui-cli.zip"
        with zipfile.ZipFile(archive_path, "w") as archive:
            for path in bundle_dir.rglob("*"):
                archive.write(path, Path("demo") / path.relative_to(bundle_dir))

        bundle = load_bundle(archive_path, REPO_ROOT, "en")

        self.assertEqual(bundle.bundle_root.name, "demo")
        self.assertEqual(bundle.manifest["pages"][0]["sections"][0]["id"], "inputs")

    def test_required_placeholders_disable_actions_with_labels(self) -> None:
        bundle = load_bundle(write_bundle(SCRATCH / "required"), REPO_ROOT, "en")
        state = RuntimeState.for_bundle(bundle)
        action = build_core_state(bundle, state).action_states["inputs:run"]

        self.assertFalse(action.enabled)
        self.assertEqual(action.disabled_reason, "Required: Input file")

        state.field_values["input"] = "reads/sample one.bam"
        action = build_core_state(bundle, state).action_states["inputs:run"]

        self.assertTrue(action.enabled)
        self.assertIn("'reads/sample one.bam'", action.command_display)
        self.assertNotIn("--optional", action.command_display)

    def test_command_interpolation_and_optional_arguments(self) -> None:
        context = CommandContext(
            field_values={"sample": "Sample A", "region": "chr1:1-10"},
            checked_options={"flags": {"dedup", "trim"}},
            config_values={"threads": "4"},
            row_values={"id": "row-1"},
            bundle_root_path="/bundle root",
            bundle_workspace_path="/workspace",
            home_path="/home/me",
        )
        command = {
            "executable": "{{bundleRoot}}/run.sh",
            "arguments": ["--sample", "{{sample}}", "--row", "{{row.id}}"],
            "optionalArguments": [["--region", "{{region}}"], ["--flags", "{{flags}}"], ["--unset", "{{unset}}"]],
        }

        rendered = rendered_command(command, context)

        self.assertEqual(rendered["executable"], "/bundle root/run.sh")
        self.assertEqual(rendered["arguments"], ["--sample", "Sample A", "--row", "row-1", "--region", "chr1:1-10", "--flags", "dedup,trim"])
        self.assertEqual(missing_placeholders(command, context), [])
        self.assertIn("'/bundle root/run.sh'", display_command(command, context))

    def test_core_state_hydrates_rows_and_row_actions(self) -> None:
        bundle = load_bundle(write_bundle(SCRATCH / "rows"), REPO_ROOT, "en")
        bundle = bundle_with_strings(bundle, locale="ar")
        state = RuntimeState.for_bundle(bundle)
        state.data_source_payloads["control:library"] = {
            "items": [{"id": "hg38", "name": "GRCh38", "status": "downloaded", "build": "38"}],
            "rowActions": [{
                "id": "delete",
                "title": "Delete",
                "visibleWhen": [{"placeholder": "row.status", "equals": "downloaded"}],
                "command": {"executable": "echo", "arguments": ["{{row.id}}", "{{row.build}}"]},
            }],
        }

        core = build_core_state(bundle, state)

        self.assertTrue(core.rtl_layout)
        self.assertEqual(core.terminal_text_direction, "ltr")
        self.assertEqual(core.control_count, 2)
        self.assertEqual(core.action_count, 2)
        row_action = core.row_action_states["library:hg38"][0]
        self.assertTrue(row_action.enabled)
        self.assertEqual(row_action.command_display, "echo hg38 38")


def write_bundle(root: Path) -> Path:
    (root / "pages").mkdir(parents=True, exist_ok=True)
    (root / "strings").mkdir(parents=True, exist_ok=True)
    manifest = {"id": "demo", "displayName": "bundle.name", "summary": "bundle.summary", "terminalTextDirection": "ltr", "pages": ["main.json"]}
    page = {
        "id": "main",
        "title": "page.title",
        "summary": "page.summary",
        "sections": [{
            "id": "inputs",
            "title": "section.title",
            "controls": [
                {"id": "input", "label": "control.input", "kind": "path"},
                {"id": "library", "label": "control.library", "kind": "libraryList", "columns": [{"id": "build", "title": "Build"}]},
            ],
            "actions": [{
                "id": "run",
                "title": "action.run",
                "command": {"executable": "echo", "arguments": ["{{input}}"], "optionalArguments": [["--optional", "{{optional}}"]]},
            }],
        }],
    }
    (root / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
    (root / "pages" / "main.json").write_text(json.dumps(page), encoding="utf-8")
    (root / "strings" / "strings.en.toml").write_text(
        '\n'.join([
            'bundle.name = "Demo Bundle"',
            'bundle.summary = "Summary"',
            'page.title = "Main"',
            'page.summary = "Main summary"',
            'section.title = "Inputs"',
            'control.input = "Input file"',
            'control.library = "Library"',
            'action.run = "Run"',
        ]) + '\n',
        encoding="utf-8",
    )
    return root


def bundle_with_strings(bundle, locale: str):
    return type(bundle)(
        repo_root=bundle.repo_root,
        bundle_root=bundle.bundle_root,
        workspace_root=bundle.workspace_root,
        locale=locale,
        manifest=bundle.manifest,
        strings=StringTable(locale=locale, values=bundle.strings.values),
    )


if __name__ == "__main__":
    unittest.main()
