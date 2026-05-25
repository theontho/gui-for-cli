import assert from "node:assert/strict";
import path from "node:path";
import test from "node:test";

const { expandPathTokens } = await import("../dist/web/src/server/paths.js");

test("path token expansion preserves unset environment variables", () => {
  const key = "GUI_FOR_CLI_MISSING_TEST_PATH_TOKEN";
  const previous = process.env[key];
  try {
    delete process.env[key];
    assert.equal(
      expandPathTokens(`\${${key}}/output`, "/bundle"),
      `\${${key}}/output`,
    );
  } finally {
    if (previous === undefined) {
      delete process.env[key];
    } else {
      process.env[key] = previous;
    }
  }
});

test("path token expansion resolves set environment variables", () => {
  const key = "GUI_FOR_CLI_SET_TEST_PATH_TOKEN";
  const previous = process.env[key];
  try {
    process.env[key] = "/resolved";
    assert.equal(
      expandPathTokens(`\${${key}}/output`, "/bundle"),
      "/resolved/output",
    );
  } finally {
    if (previous === undefined) {
      delete process.env[key];
    } else {
      process.env[key] = previous;
    }
  }
});

test("path token expansion normalizes token path separators on Windows", (t) => {
  if (process.platform !== "win32") {
    t.skip("Windows path separator behavior is platform-specific.");
    return;
  }

  assert.equal(
    expandPathTokens("{{bundleWorkspace}}/reference/genomes/hg19.fa.gz", "C:\\bundle\\workspace"),
    path.join("C:\\bundle\\workspace", "reference", "genomes", "hg19.fa.gz"),
  );
});
