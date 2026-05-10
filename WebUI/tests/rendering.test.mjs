import assert from "node:assert/strict";
import test from "node:test";
import { parseTomlStrings } from "../dist/shared/localization.js";
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
