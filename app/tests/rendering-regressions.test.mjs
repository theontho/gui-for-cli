import assert from "node:assert/strict";
import test from "node:test";
import { hydrateRows, parseFlatToml } from "../dist/shared/rendering.js";

test("parses flat TOML inline comments outside quoted strings", () => {
  assert.deepEqual({ ...parseFlatToml('plain = value # comment\nquoted = "value # not comment" # comment\n') }, {
    plain: "value",
    quoted: "value # not comment",
  });
});

test("hydrates whitespace-only row metadata as empty", () => {
  const rows = hydrateRows({ rowTemplate: { id: "one", title: "One", status: "   " }, items: [{}] });

  assert.equal(rows[0].status, undefined);
});
