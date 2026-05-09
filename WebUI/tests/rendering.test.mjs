import assert from "node:assert/strict";
import test from "node:test";
import { resizedSidebarWidth } from "../dist/client/dom.js";
import { parseTomlStrings } from "../dist/shared/localization.js";
import {
  conditionMatches,
  displayCommand,
  evaluateNumeric,
  hydrateRows,
  missingPlaceholders,
  parseFlatToml,
  serializeFlatToml,
  setupCommandPreview,
  setupResultLine,
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

test("evaluates numeric action conditions", () => {
  assert.equal(
    conditionMatches(
      { placeholder: "size", greaterThanOrEqual: "2 * 5" },
      { fieldValues: { size: "10" }, checkedOptions: {}, configValues: {}, rowValues: {} },
    ),
    true,
  );
});

test("evaluates all action condition operators", () => {
  const context = { fieldValues: { mode: "fast", output: "/tmp/out" }, checkedOptions: {}, configValues: {}, rowValues: {} };
  assert.equal(conditionMatches({ placeholder: "mode", equals: "fast" }, context), true);
  assert.equal(conditionMatches({ placeholder: "mode", notEquals: "slow" }, context), true);
  assert.equal(conditionMatches({ placeholder: "mode", in: ["fast", "safe"] }, context), true);
  assert.equal(conditionMatches({ placeholder: "mode", notIn: ["slow", "unsafe"] }, context), true);
  assert.equal(conditionMatches({ placeholder: "output", exists: true }, context), true);
  assert.equal(conditionMatches({ placeholder: "missing", exists: false }, context), true);
});

test("evaluates disk precheck arithmetic expressions", () => {
  assert.equal(evaluateNumeric("1.5 * 6"), 9);
  assert.equal(evaluateNumeric("(2 + 3) * 4"), 20);
});

test("round trips flat TOML config values", () => {
  const text = serializeFlatToml({ output_dir: "/tmp/out", quoted: 'a "value"' });
  assert.deepEqual({ ...parseFlatToml(text) }, { output_dir: "/tmp/out", quoted: 'a "value"' });
});

test("previews setup commands with bundle path interpolation", () => {
  assert.equal(
    setupCommandPreview(
      { kind: "setupScript", value: "scripts/setup.sh", arguments: ["--prefix", "{{bundleRoot}}/runtime"], label: "Install" },
      "/bundle",
    ),
    "/bin/sh /bundle/scripts/setup.sh --prefix /bundle/runtime",
  );
  assert.equal(
    setupCommandPreview({ kind: "pixiRun", value: "deps-check", arguments: ["--verbose"], label: "Check" }, "/bundle"),
    "/usr/bin/env pixi run deps-check --verbose",
  );
});

test("formats setup results like the app terminal setup log", () => {
  assert.equal(setupResultLine({ status: "ok", label: "Install", exitCode: 0 }), "[ok] Install");
  assert.equal(setupResultLine({ status: "warning", label: "Optional tool", exitCode: 127 }), "[exit 127] Optional tool");
  assert.equal(setupResultLine({ status: "error", label: "Install", error: "boom" }), "[error] Install: boom");
  assert.equal(setupResultLine({ status: "cancelled", label: "Install" }), "[cancelled] setup stopped");
});

test("resizes sidebar with visual mouse direction in LTR and RTL", () => {
  assert.equal(resizedSidebarWidth(220, 100, 140, "ltr"), 260);
  assert.equal(resizedSidebarWidth(220, 100, 140, "rtl"), 180);
  assert.equal(resizedSidebarWidth(220, 100, 60, "rtl"), 260);
});

test("parses quoted TOML keys with separators safely", () => {
  const parsed = parseFlatToml('"a=b" = "value"\n"__proto__" = "safe"\n');
  assert.equal(Object.getPrototypeOf(parsed), null);
  assert.equal(parsed["a=b"], "value");
  assert.equal(parsed.__proto__, "safe");
});
