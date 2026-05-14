from __future__ import annotations

from contextlib import redirect_stdout
from pathlib import Path
import io
import json
import shutil
import stat
import tarfile
import tempfile
import unittest
import zipfile

from gui_for_cli_toga.benchmark import run_benchmark
from gui_for_cli_toga.bundle_loader import load_bundle
from gui_for_cli_toga.cli import main as cli_main
from gui_for_cli_toga.commands import context_value
from gui_for_cli_toga.runtime import RuntimeModel

REPO_ROOT = Path(__file__).resolve().parents[4]


class HeadlessRuntimeTests(unittest.TestCase):
    def setUp(self) -> None:
        self._temp_dir = tempfile.TemporaryDirectory(prefix="python-toga-tests-")
        self.case_dir = Path(self._temp_dir.name)
        self.bundle_dir = self.case_dir / "FixtureBundle"
        write_fixture_bundle(self.bundle_dir)
        self.workspace = self.case_dir / "workspace"

    def tearDown(self) -> None:
        self._temp_dir.cleanup()
        shutil.rmtree(REPO_ROOT / "tmp" / "python-toga-tests", ignore_errors=True)

    def load_model(self, locale: str = "en") -> RuntimeModel:
        bundle = load_bundle(
            self.bundle_dir,
            repo_root=REPO_ROOT,
            locale=locale,
            workspace_root=self.workspace,
        )
        model = RuntimeModel(bundle)
        model.bootstrap()
        return model

    def test_bundle_loading_and_localization_keep_missing_keys_visible(self) -> None:
        bundle = load_bundle(
            self.bundle_dir,
            repo_root=REPO_ROOT,
            locale="ar",
            workspace_root=self.workspace,
        )

        self.assertEqual(bundle.display_name, "حزمة الاختبار")
        self.assertEqual(bundle.layout_direction, "rtl")
        self.assertEqual(bundle.terminal_text_direction, "ltr")
        self.assertEqual(bundle.pages[0]["title"], "الرئيسية")
        self.assertEqual(bundle.pages[0]["summary"], "pages.main.summary")
        self.assertTrue(self.workspace.is_dir())

        archive_path = self.case_dir / "fixture-bundle.zip"
        with zipfile.ZipFile(archive_path, "w") as archive:
            for path in self.bundle_dir.rglob("*"):
                if path.is_file():
                    archive.write(path, Path("FixtureBundle") / path.relative_to(self.bundle_dir))
        archived = load_bundle(
            archive_path,
            repo_root=self.case_dir,
            locale="en",
            workspace_root=self.workspace,
        )
        self.assertEqual(archived.display_name, "Fixture Bundle")
        self.assertEqual(archived.pages[0]["id"], "main")

    def test_rejects_unsafe_archive_paths(self) -> None:
        zip_path = self.case_dir / "unsafe.zip"
        with zipfile.ZipFile(zip_path, "w") as archive:
            archive.writestr("../outside.txt", "bad")

        with self.assertRaisesRegex(ValueError, "Unsafe path in archive"):
            load_bundle(zip_path, repo_root=self.case_dir, workspace_root=self.workspace)

        tar_path = self.case_dir / "unsafe.tar"
        with tarfile.open(tar_path, "w") as archive:
            target = self.case_dir / "outside.txt"
            target.write_text("bad", encoding="utf-8")
            archive.add(target, arcname="../outside.txt")

        with self.assertRaisesRegex(ValueError, "Unsafe path in archive"):
            load_bundle(tar_path, repo_root=self.case_dir, workspace_root=self.workspace)

    def test_rejects_page_references_outside_pages_directory(self) -> None:
        manifest_path = self.bundle_dir / "manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["pages"] = ["../manifest.json"]
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

        with self.assertRaisesRegex(ValueError, "Page reference escapes expected root"):
            load_bundle(self.bundle_dir, repo_root=REPO_ROOT, workspace_root=self.workspace)

    def test_required_placeholders_action_disabling_and_command_interpolation(self) -> None:
        model = self.load_model()
        actions = actions_by_id(model)

        missing = model.action_state(actions["run"])
        self.assertFalse(missing.enabled)
        self.assertEqual(missing.missing_inputs, ["input_path"])
        self.assertEqual(missing.reason, "Missing: input_path")

        model.state.field_values["input_path"] = "/data/sample one.bam"
        ready = model.action_state(actions["run"])
        self.assertTrue(ready.enabled)
        self.assertIn("--input '/data/sample one.bam'", ready.command_line or "")
        self.assertNotIn("--extra", ready.command_line or "")

        model.state.field_values["extra"] = "with space"
        with_optional = model.action_state(actions["run"])
        self.assertTrue(with_optional.enabled)
        self.assertIn("--extra 'with space'", with_optional.command_line or "")

        disabled = model.action_state(actions["disabled-fast"])
        self.assertFalse(disabled.enabled)
        self.assertEqual(disabled.reason, "Disabled while mode is fast")

        hidden = model.action_state(actions["hidden-slow"])
        self.assertFalse(hidden.visible)
        self.assertEqual(hidden.reason, "hidden")

    def test_config_loading_saving_and_render_snapshot(self) -> None:
        model = self.load_model()
        settings_control = config_editor(model)
        config_path = self.workspace / "settings" / "config.toml"

        self.assertTrue(config_path.exists())
        config_path.write_text('alpha = "old"\nunrelated = "keep"\n', encoding="utf-8")
        model.state.field_values["alpha"] = "changed"
        model.save_config(settings_control)
        self.assertIn('unrelated = "keep"', config_path.read_text(encoding="utf-8"))

        reloaded = self.load_model()
        self.assertEqual(reloaded.state.config_values["settings.alpha"], "changed")
        self.assertEqual(reloaded.state.field_values["alpha"], "changed")

        unsafe_control = {
            **settings_control,
            "configFile": {"path": "{{bundleWorkspace}}/../escaped.toml", "bootstrap": {"mode": "createIfMissing"}},
        }
        with self.assertRaisesRegex(ValueError, "Config file path escapes expected root"):
            reloaded.load_config(unsafe_control)

        relative_control = {
            **settings_control,
            "configFile": {"path": "relative/settings.toml", "bootstrap": {"mode": "createIfMissing"}},
        }
        reloaded.load_config(relative_control)
        self.assertTrue((self.workspace / "relative" / "settings.toml").exists())

        snapshot = reloaded.render_snapshot()
        self.assertEqual(snapshot["display_name"], "Fixture Bundle")
        self.assertEqual(snapshot["page_count"], 2)
        self.assertEqual(snapshot["setup_steps"], 1)
        self.assertIn("configEditor", snapshot["control_kinds"])
        self.assertIn("path", snapshot["control_kinds"])
        settings_sections = snapshot["pages"][1]["sections"]
        self.assertEqual(settings_sections[0]["kind"], "settings")

    def test_empty_payload_collections_replace_previous_state(self) -> None:
        model = self.load_model()
        section = {"id": "dynamic", "actions": [{"id": "old"}]}

        model._apply_section_payload(
            section,
            {"values": {"sample": "present"}, "actions": [{"id": "new"}]},
        )
        self.assertEqual(model.state.section_values["dynamic"], {"sample": "present"})
        self.assertEqual(model.state.field_values["sample"], "present")
        self.assertEqual(section["actions"], [{"id": "new"}])

        model._apply_section_payload(section, {"values": {}, "actions": []})
        self.assertEqual(model.state.section_values["dynamic"], {})
        self.assertNotIn("sample", model.state.field_values)
        self.assertEqual(section["actions"], [])

        settings_control = config_editor(model)
        setting = settings_control["settings"][0]
        setting["dataSource"] = {"path": "scripts/options.py"}
        setting["options"] = [{"id": "old"}]
        model.run_data_source = (  # type: ignore[method-assign]
            lambda data_source, row_values=None: {"options": []}
        )
        settings_page = next(page for page in model.bundle.pages if page.get("id") == "settings")
        model._refresh_page(settings_page)
        self.assertEqual(setting["options"], [])

    def test_bundle_paths_stay_inside_bundle_root_and_file_size_race_is_safe(self) -> None:
        model = self.load_model()

        with self.assertRaisesRegex(ValueError, "Bundle path escapes expected root"):
            model.resolve_bundle_path("../outside.sh")

        missing_size = context_value({"fieldValues": {"input": self.case_dir / "missing.bam"}}, "input.fileSize")
        self.assertIsNone(missing_size)

    def test_benchmark_and_cli_once_are_headless(self) -> None:
        output = REPO_ROOT / "tmp" / "python-toga-tests" / "benchmark.txt"
        output.parent.mkdir(parents=True, exist_ok=True)
        line = run_benchmark(
            str(self.bundle_dir),
            repo_root=str(REPO_ROOT),
            locale="en",
            output=str(output),
            full=False,
            workspace_root=str(self.workspace),
        )
        self.assertIn("gfc-toga benchmark", line)
        self.assertIn("pages=2", line)
        self.assertEqual(output.read_text(encoding="utf-8").strip(), line)

        describe_stdout = io.StringIO()
        with redirect_stdout(describe_stdout):
            code = cli_main([
                "--bundle",
                str(self.bundle_dir),
                "--repo-root",
                str(REPO_ROOT),
                "--workspace-root",
                str(self.workspace),
                "--describe",
            ])
        self.assertEqual(code, 0)
        described = json.loads(describe_stdout.getvalue())
        self.assertEqual(described["display_name"], "Fixture Bundle")

        once_stdout = io.StringIO()
        once_output = output.parent / "once-benchmark.txt"
        with redirect_stdout(once_stdout):
            code = cli_main([
                "--bundle",
                str(self.bundle_dir),
                "--repo-root",
                str(REPO_ROOT),
                "--workspace-root",
                str(self.workspace),
                "--once",
                "--benchmark-output",
                str(once_output),
            ])
        self.assertEqual(code, 0)
        self.assertIn("gfc-toga benchmark", once_stdout.getvalue())
        self.assertTrue(once_output.is_file())


def write_fixture_bundle(root: Path) -> None:
    (root / "pages").mkdir(parents=True)
    (root / "strings").mkdir()
    (root / "scripts").mkdir()
    run_script = root / "scripts" / "run.sh"
    run_script.write_text("#!/bin/sh\nprintf '%s\\n' \"$@\"\n", encoding="utf-8")
    run_script.chmod(run_script.stat().st_mode | stat.S_IXUSR)

    manifest = {
        "id": "fixture.bundle",
        "displayName": "bundle.displayName",
        "summary": "bundle.summary",
        "terminalTextDirection": "ltr",
        "defaultLocalizationCode": "en",
        "setup": {"steps": [{"id": "python", "kind": "pathTool", "label": "setup.python", "value": "python3"}]},
        "pages": ["main.json", "settings.json"],
    }
    main_page = {
        "id": "main",
        "title": "pages.main.title",
        "summary": "pages.main.summary",
        "sections": [
            {
                "id": "inputs",
                "title": "sections.inputs.title",
                "controls": [
                    {"id": "input_path", "label": "controls.input.label", "kind": "path"},
                    {"id": "mode", "label": "controls.mode.label", "kind": "dropdown", "value": "fast", "options": [{"id": "fast", "title": "Fast", "selected": True}]},
                    {"id": "extra", "label": "controls.extra.label", "kind": "text"},
                ],
                "actions": [
                    {
                        "id": "run",
                        "title": "actions.run.title",
                        "command": {
                            "executable": "{{bundleRoot}}/scripts/run.sh",
                            "arguments": ["--input", "{{input_path}}", "--mode", "{{mode}}"],
                            "optionalArguments": [["--extra", "{{extra}}"]],
                        },
                    },
                    {
                        "id": "disabled-fast",
                        "title": "actions.disabled.title",
                        "disabledTooltip": "Disabled while mode is {{mode}}",
                        "disabledWhen": [{"placeholder": "mode", "equals": "fast"}],
                        "command": {"executable": "{{bundleRoot}}/scripts/run.sh", "arguments": ["noop"]},
                    },
                    {
                        "id": "hidden-slow",
                        "title": "actions.hidden.title",
                        "visibleWhen": [{"placeholder": "mode", "equals": "slow"}],
                        "command": {"executable": "{{bundleRoot}}/scripts/run.sh", "arguments": ["noop"]},
                    },
                ],
            }
        ],
    }
    settings_page = {
        "id": "settings",
        "title": "pages.settings.title",
        "sections": [
            {
                "id": "settings-section",
                "title": "sections.settings.title",
                "controls": [
                    {
                        "id": "settings",
                        "label": "controls.settings.label",
                        "kind": "configEditor",
                        "configFile": {"path": "{{bundleWorkspace}}/settings/config.toml", "format": "toml", "bootstrap": {"mode": "createIfMissing"}},
                        "settings": [{"id": "alpha", "key": "alpha", "label": "Alpha", "kind": "text", "value": "default"}],
                    }
                ],
            }
        ],
    }
    (root / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
    (root / "pages" / "main.json").write_text(json.dumps(main_page), encoding="utf-8")
    (root / "pages" / "settings.json").write_text(json.dumps(settings_page), encoding="utf-8")
    (root / "strings" / "strings.en.toml").write_text(
        '\n'.join([
            '"bundle.displayName" = "Fixture Bundle"',
            '"bundle.summary" = "Fixture summary"',
            '"setup.python" = "Python"',
            '"pages.main.title" = "Main"',
            '"pages.main.summary" = "Main summary"',
            '"pages.settings.title" = "Settings"',
            '"sections.inputs.title" = "Inputs"',
            '"sections.settings.title" = "Settings section"',
            '"controls.input.label" = "Input"',
            '"controls.mode.label" = "Mode"',
            '"controls.extra.label" = "Extra"',
            '"controls.settings.label" = "Settings"',
            '"actions.run.title" = "Run"',
            '"actions.disabled.title" = "Disabled"',
            '"actions.hidden.title" = "Hidden"',
        ]) + '\n',
        encoding="utf-8",
    )
    (root / "strings" / "strings.ar.toml").write_text(
        '\n'.join([
            '"language.layoutDirection" = "rtl"',
            '"bundle.displayName" = "حزمة الاختبار"',
            '"bundle.summary" = "ملخص"',
            '"setup.python" = "بايثون"',
            '"pages.main.title" = "الرئيسية"',
            '"pages.settings.title" = "الإعدادات"',
            '"sections.inputs.title" = "المدخلات"',
            '"sections.settings.title" = "قسم الإعدادات"',
            '"controls.input.label" = "إدخال"',
            '"controls.mode.label" = "الوضع"',
            '"controls.extra.label" = "إضافي"',
            '"controls.settings.label" = "الإعدادات"',
            '"actions.run.title" = "تشغيل"',
            '"actions.disabled.title" = "معطل"',
            '"actions.hidden.title" = "مخفي"',
        ]) + '\n',
        encoding="utf-8",
    )


def actions_by_id(model: RuntimeModel) -> dict[str, dict]:
    return {
        action["id"]: action
        for page in model.bundle.pages
        for section in page.get("sections", [])
        for action in section.get("actions", [])
    }


def config_editor(model: RuntimeModel) -> dict:
    for page in model.bundle.pages:
        for section in page.get("sections", []) or []:
            for control in section.get("controls", []) or []:
                if control.get("kind") == "configEditor":
                    return control
    raise AssertionError("fixture config editor missing")


if __name__ == "__main__":
    unittest.main()
