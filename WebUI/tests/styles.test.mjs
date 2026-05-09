import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const styles = await readFile(new URL("../styles.css", import.meta.url), "utf8");

test("light-mode buttons use explicit readable text and background variables", () => {
  assert.match(styles, /--button-bg-top:\s*#ffffff;/);
  assert.match(styles, /--button-bg-bottom:\s*#ececf0;/);
  assert.match(styles, /--button-text:\s*#1d1d1f;/);
  assert.match(styles, /button\s*\{[^}]*background:\s*linear-gradient\(var\(--button-bg-top\), var\(--button-bg-bottom\)\);/s);
  assert.match(styles, /button\s*\{[^}]*color:\s*var\(--button-text\);/s);
});

test("light-mode primary action buttons do not depend on system AccentColor contrast", () => {
  assert.match(styles, /--primary-button-bg-top:\s*#0a84ff;/);
  assert.match(styles, /--primary-button-bg-bottom:\s*#006edb;/);
  assert.match(styles, /--primary-button-text:\s*#ffffff;/);
  assert.match(styles, /\.action-button\.primary\s*\{[^}]*background:\s*linear-gradient\(var\(--primary-button-bg-top\), var\(--primary-button-bg-bottom\)\);/s);
  assert.match(styles, /\.action-button\.primary\s*\{[^}]*color:\s*var\(--primary-button-text\);/s);
});
