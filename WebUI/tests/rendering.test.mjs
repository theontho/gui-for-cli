import assert from "node:assert/strict";
import test from "node:test";
import { parseTomlStrings } from "../dist/shared/localization.js";
import {
  conditionMatches,
  displayCommand,
  evaluateNumeric,
  hydrateRows,
  missingPlaceholders,
  parseFlatToml,
  shellQuote,
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

test("renders commands with required and optional placeholders", () => {
  const command = {
    executable: "tool",
    arguments: ["run", "{{input}}"],
    optionalArguments: [["--label", "{{label}}"], ["--missing", "{{missing}}"]],
  };
  const context = { fieldValues: { input: "file name.bam", label: "sample" }, checkedOptions: {}, configValues: {}, rowValues: {} };
  assert.deepEqual(missingPlaceholders(command, context), []);
  assert.equal(
    displayCommand(command, context),
    process.platform === "win32" ? 'tool run "file name.bam" --label sample' : "tool run 'file name.bam' --label sample",
  );
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

test("evaluates disk precheck arithmetic expressions", () => {
  assert.equal(evaluateNumeric("1.5 * 6"), 9);
  assert.equal(evaluateNumeric("(2 + 3) * 4"), 20);
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

test("quotes Windows command previews with double quotes", () => {
  assert.equal(shellQuote('C:\\Program Files\\tool.cmd', "win32"), '"C:\\Program Files\\tool.cmd"');
  assert.equal(shellQuote('plain-path.exe', "win32"), "plain-path.exe");
});
