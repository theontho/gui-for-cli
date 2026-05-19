import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { parseIconMapToml } from "../dist/shared/icon-map.js";
import { parseTomlStrings, parseTomlStringValue } from "../dist/shared/localization.js";
import {
  conditionMatches,
  displayCommand,
  evaluateNumeric,
  hydrateRows,
  isPrecheckReady,
  missingPlaceholders,
  parseFlatToml,
  serializeFlatToml,
} from "../dist/shared/rendering.js";

test("parses flat localization TOML with comments and multiline values", () => {
  const table = parseTomlStrings(`
    "language.name" = "English" # translator hint
    key = """ 
first
second
"""
  `);
  assert.equal(table["language.name"], "English");
  assert.equal(table.key, "first\nsecond");
});

test("reads one localization TOML string without parsing the full table", () => {
  const value = parseTomlStringValue(`
    "language.name" = "English" # translator hint
    invalid trailing line without equals
  `, "language.name");

  assert.equal(value, "English");
});

test("rejects malformed trailing content in single-value TOML parsing", () => {
  const value = parseTomlStringValue(`
    "language.name" = "English" trailing junk
  `, "language.name");

  assert.equal(value, undefined);
});

test("single-value TOML boolean parsing follows TOML casing", () => {
  assert.equal(parseTomlStringValue(`ai_translated = true # metadata`, "ai_translated"), "true");
  assert.equal(parseTomlStringValue(`ai_translated = True`, "ai_translated"), undefined);
});

test("critical Bootstrap Icons stylesheet covers every WebUI icon", () => {
  const iconMap = parseIconMapToml(
    readFileSync(
      new URL("../../../resources/BuiltinIconMap/iconmap.toml", import.meta.url),
      "utf8"
    )
  );
  const iconNames = new Set(Object.values(iconMap.bootstrap ?? {}));
  assert.ok(iconNames.size > 0, "No Bootstrap icons found in built-in iconmap.toml");
  iconNames.add("clipboard");
  const criticalCSS = readFileSync(new URL("../web/vendor/bootstrap-icons/bootstrap-icons-critical.css", import.meta.url), "utf8");

  for (const iconName of iconNames) {
    assert.match(criticalCSS, new RegExp(`\\.bi-${iconName.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}::before`));
  }
});

test("renders commands with required and optional placeholders", () => {
  const command = {
    executable: "tool",
    arguments: ["run", "{{input}}"],
    optionalArguments: [["--label", "{{label}}"], ["--missing", "{{missing}}"]],
  };
  const context = { fieldValues: { input: "file name.bam", label: "sample" }, checkedOptions: {}, configValues: {}, rowValues: {} };
  assert.deepEqual(missingPlaceholders(command, context), []);
  assert.equal(displayCommand(command, context), "tool run 'file name.bam' --label sample");
});

test("hydrates list rows from item values and templates", () => {
  const rows = hydrateRows({
    columns: [{ id: "name", title: "Name" }],
    rowTemplate: { id: "{{id}}", title: "{{name}}", values: { build: "{{build}}" }, status: "{{status}}" },
    items: [{ id: "hg38", name: "GRCh38", build: "GRCh38", status: "installed" }],
  });
  assert.deepEqual(rows, [
    { id: "hg38", title: "GRCh38", values: { build: "GRCh38" }, status: "installed", tags: [], tooltip: undefined },
  ]);
});

test("hydrates library row metadata from top-level datasource item fields", () => {
  const rows = hydrateRows({
    columns: [{ id: "name", title: "Name" }],
    rowTemplate: {
      id: "{{id}}",
      title: "{{name}}",
      values: { name: "{{name}}", code: "{{code}}" },
      status: "{{status}}",
      tags: [{ id: "recommended", title: "{{recommended}}", style: "primary" }],
      tooltip: "{{description}}",
    },
    items: [
      {
        id: "hg38",
        title: "GRCh38",
        status: "missing",
        tags: [{ id: "recommended", title: "Recommended", style: "primary" }],
        tooltip: "Reference genome",
        values: { name: "GRCh38", code: "hs38", recommended: "" },
      },
    ],
  });
  assert.equal(rows[0].status, "missing");
  assert.deepEqual(rows[0].tags, [{ id: "recommended", title: "Recommended", style: "primary" }]);
  assert.equal(rows[0].tooltip, "Reference genome");
  assert.equal(rows[0].values.code, "hs38");
});

test("evaluates numeric action conditions", () => {
  assert.equal(
    conditionMatches(
      { placeholder: "size", greaterThanOrEqual: "2 * 5" },
      { fieldValues: { size: "10" }, checkedOptions: {}, configValues: {}, rowValues: {} },
    ),
    true,
  );
});

test("evaluates disk precheck arithmetic expressions", () => {
  assert.equal(evaluateNumeric("1.5 * 6"), 9);
  assert.equal(evaluateNumeric("(2 + 3) * 4"), 20);
});

test("waits to run disk prechecks until source files are chosen", () => {
  const precheck = { diskSpaceGB: "{{fastq_r1.fileSizeGB}} * 8", diskSpacePath: "{{out_dir}}" };
  assert.equal(isPrecheckReady(precheck, { fieldValues: { out_dir: "/tmp/out" }, configValues: {} }), false);
  assert.equal(isPrecheckReady(precheck, { fieldValues: { fastq_r1: "/tmp/read1.fastq", out_dir: "" }, configValues: {} }), true);
});

test("round trips flat TOML config values", () => {
  const text = serializeFlatToml({ output_dir: "/tmp/out", quoted: 'a "value"' });
  assert.deepEqual({ ...parseFlatToml(text) }, { output_dir: "/tmp/out", quoted: 'a "value"' });
});

test("parses quoted TOML keys with separators safely", () => {
  const parsed = parseFlatToml('"a=b" = "value"\n"__proto__" = "safe"\n');
  assert.equal(Object.getPrototypeOf(parsed), null);
  assert.equal(parsed["a=b"], "value");
  assert.equal(parsed.__proto__, "safe");
});

test("renders setup status for settings bundles with and without setup steps", async () => {
  globalThis.localStorage = {
    getItem() {
      return null;
    },
    setItem() {},
  };
  globalThis.window = { innerHeight: 900 };

  const { createInitialState, state } = await import("../dist/web/src/client/state.js");
  const { renderSetupGlobalStatusBar, renderSetupPromptDialog, renderSetupStatusSection, setupNeedsAttention } = await import("../dist/web/src/client/view.js");
  Object.assign(state, createInitialState(), {
    manifest: {
      displayName: "WGSExtract",
      setup: {
        steps: [
          { id: "install", kind: "setupScript", label: "Install tool", toolName: "Example CLI", toolVersion: "v1.2.3" },
          { id: "check", kind: "pathTool", label: "Check path" },
        ],
      },
    },
    labels: {
      setupTitle: "Setup",
      setupRunButtonTitle: "Run Setup",
      setupRerunButtonTitle: "Rerun Setup",
      setupRunningTitle: "Running setup...",
      setupNoStepsTitle: "No setup needed.",
      setupStatusReadyTitle: "Ready to set up.",
      setupStatusOkTitle: "Setup completed.",
      setupStatusFailedTitle: "Setup failed.",
      setupStepPendingTitle: "Pending",
      setupStepRunningTitle: "Running",
      setupStepOkTitle: "OK",
      openBundleWorkspaceTitle: "Open Bundle Workspace",
      terminalCancelButtonTitle: "Cancel",
    },
    iconMap: {
      bootstrap: {
        folder: "folder",
        "play.fill": "play-fill",
      },
    },
  });

  let html = renderSetupStatusSection();
  assert.match(html, /Ready to set up/);
  assert.match(html, /data-run-setup/);
  assert.match(html, /data-open-bundle-workspace/);
  assert.match(html, /Install tool/);
  assert.match(html, /Tool: Example CLI v1\.2\.3/);
  assert.match(html, /Pending/);
  assert.equal(setupNeedsAttention(), true);
  assert.match(renderSetupGlobalStatusBar(), /data-setup-global-start/);
  assert.match(renderSetupGlobalStatusBar(), /Ready to set up/);
  state.setupPromptVisible = true;
  assert.match(renderSetupPromptDialog(), /role="alertdialog"/);
  assert.match(renderSetupPromptDialog(), /WGSExtract will probably not work properly/);
  assert.match(renderSetupPromptDialog(), /Tool: Example CLI v1\.2\.3/);
  assert.match(renderSetupPromptDialog(), /data-setup-prompt-run/);

  state.setupRun = { status: "running", currentStepID: "install", results: [] };
  html = renderSetupStatusSection();
  assert.match(html, /Running setup/);
  assert.match(html, /setup-step running/);
  assert.match(html, /mini-spinner/);
  assert.doesNotMatch(html, /setup-step-status" aria-hidden="true">…/);

  state.setupRun = {
    status: "ok",
    currentStepID: null,
    results: [
      { id: "install", status: "ok" },
      { id: "check", status: "ok" },
    ],
  };
  html = renderSetupStatusSection();
  assert.match(html, /Setup completed/);
  assert.match(html, /Rerun Setup/);
  assert.match(html, /bi-play-fill/);
  assert.equal((html.match(/OK/g) ?? []).length, 2);
  assert.equal(setupNeedsAttention(), false);
  assert.equal(renderSetupGlobalStatusBar(), "");

  state.setupRun = {
    status: "warning",
    currentStepID: null,
    results: [
      { id: "install", status: "ok" },
      { id: "check", status: "warning" },
    ],
  };
  html = renderSetupStatusSection();
  assert.match(html, /Rerun Setup/);
  assert.equal(setupNeedsAttention(), false);
  assert.equal(renderSetupGlobalStatusBar(), "");

  state.manifest.setup.steps = [];
  state.setupRun = null;
  html = renderSetupStatusSection();
  assert.match(html, /No setup needed/);
  assert.doesNotMatch(html, /data-run-setup/);
});

test("disabled action tooltips use localized missing input labels and keep action help", async () => {
  globalThis.localStorage = {
    getItem() {
      return null;
    },
    setItem() {},
  };
  globalThis.window = { innerHeight: 900 };

  const { createInitialState, state } = await import("../dist/web/src/client/state.js");
  const { renderActions } = await import("../dist/web/src/client/view.js");
  Object.assign(state, createInitialState(), {
    manifest: {
      pages: [
        {
          sections: [
            {
              controls: [
                { id: "realign_bam", kind: "path", label: "Realigned BAM" },
                {
                  id: "wgs_settings",
                  kind: "configEditor",
                  label: "Settings",
                  settings: [
                    {
                      id: "ref_path",
                      key: "reference_library",
                      kind: "path",
                      label: "Reference Library",
                    },
                  ],
                },
              ],
            },
          ],
        },
      ],
    },
    labels: {
      actionMissingInputsFormat: "Missing: %{inputs}",
      actionUnavailableTitle: "Unavailable",
    },
  });

  const html = renderActions(
    [
      {
        id: "run",
        title: "Run",
        tooltip: "Run realignment with the selected inputs.",
        command: {
          executable: "tool",
          arguments: ["{{realign_bam}}", "{{reference_library}}"],
        },
      },
    ],
    { fieldValues: {}, checkedOptions: {}, configValues: {}, rowValues: {} },
  );

  assert.match(html, /Run realignment with the selected inputs\./);
  assert.match(html, /Missing: Realigned BAM, Reference Library/);
  assert.doesNotMatch(html, /Missing: realign_bam/);
});

test("icon-only action buttons omit empty title spans so icons stay centered", async () => {
  globalThis.localStorage = {
    getItem() {
      return null;
    },
    setItem() {},
  };
  globalThis.window = { innerHeight: 900 };

  const { createInitialState, state } = await import("../dist/web/src/client/state.js");
  const { renderActions } = await import("../dist/web/src/client/view.js");
  Object.assign(state, createInitialState(), {
    manifest: { pages: [] },
    labels: {
      actionMissingInputsFormat: "Missing: %{inputs}",
      actionUnavailableTitle: "Unavailable",
    },
  });

  const html = renderActions(
    [
      {
        id: "delete",
        title: "Delete",
        iconOnly: true,
        textIcon: "X",
        command: {
          executable: "tool",
          arguments: ["delete"],
        },
      },
    ],
    { fieldValues: {}, checkedOptions: {}, configValues: {}, rowValues: {} },
    true,
  );

  assert.match(html, /action-button primary compact icon-only/);
  assert.match(html, /<span class="action-icon" aria-hidden="true">/);
  assert.doesNotMatch(html, /<span><\/span>/);
});

test("path text fields stay left-to-right in RTL locales", async () => {
  globalThis.localStorage = {
    getItem() {
      return null;
    },
    setItem() {},
  };
  globalThis.window = { innerHeight: 900 };

  const { createInitialState, state } = await import("../dist/web/src/client/state.js");
  const { renderConfigEditor, renderTextControl } = await import("../dist/web/src/client/view.js");
  Object.assign(state, createInitialState(), {
    labels: {
      layoutDirection: "rtl",
      chooseButtonTitle: "Choose...",
      loadButtonTitle: "Load",
      saveButtonTitle: "Save",
      settingsFileLabel: "Settings file",
    },
    configFilePaths: {
      settings: "/tmp/config.toml",
    },
    configValues: {
      "settings.output_dir": "/tmp/output",
    },
  });

  const pathControlHTML = renderTextControl({ id: "input_bam", kind: "path", label: "Input BAM", value: "/tmp/input.bam" });
  const textControlHTML = renderTextControl({ id: "sample_name", kind: "text", label: "Sample", value: "NA12878" });
  const configHTML = renderConfigEditor({
    id: "settings",
    kind: "configEditor",
    label: "Settings",
    configFile: { path: "/tmp/config.toml" },
    settings: [{ id: "output_dir", kind: "path", label: "Output directory" }],
  });

  assert.match(pathControlHTML, /class="path-input" dir="ltr"/);
  assert.doesNotMatch(textControlHTML, /dir="ltr"/);
  assert.match(configHTML, /class="mono path-input" dir="ltr"/);
  assert.match(configHTML, /class="path-input" dir="ltr"/);
});
