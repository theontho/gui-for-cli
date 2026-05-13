import assert from "node:assert/strict";
import test from "node:test";

test("one-shot bundle preload starts immediately and serves the first matching request", async () => {
  const calls = [];
  const { createOneShotBundlePreload } = await import("../dist/web/src/server/bundle-loader.js");
  const loader = createOneShotBundlePreload(async (locale) => {
    calls.push(locale ?? null);
    return { locale: locale ?? null, callCount: calls.length };
  }, undefined, true);

  assert.deepEqual(calls, [null]);
  assert.deepEqual(await loader.load(undefined), { locale: null, callCount: 1 });
  assert.deepEqual(calls, [null]);
  assert.deepEqual(await loader.load(undefined), { locale: null, callCount: 2 });
  assert.deepEqual(calls, [null, null]);
});

test("one-shot bundle preload is skipped when no bundle was explicitly requested", async () => {
  const calls = [];
  const { createOneShotBundlePreload } = await import("../dist/web/src/server/bundle-loader.js");
  const loader = createOneShotBundlePreload(async (locale) => {
    calls.push(locale ?? null);
    return { locale: locale ?? null };
  }, "en", false);

  assert.equal(loader.preloaded, undefined);
  assert.deepEqual(calls, []);
  assert.deepEqual(await loader.load("en"), { locale: "en" });
  assert.deepEqual(calls, ["en"]);
});

