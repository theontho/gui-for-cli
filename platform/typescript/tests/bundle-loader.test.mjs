import assert from "node:assert/strict";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

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

test("icon map TOML parses source-specific aliases", async () => {
  const { parseIconMapToml } = await import("../dist/shared/icon-map.js");
  const iconMap = parseIconMapToml(`
[sf-symbols]
"fasta" = "point.3.connected.trianglepath.dotted"

[windows]
"download" = "\\uE896"
"refresh" = " \\uE72C"

[bootstrap]
"warning" = "exclamation-triangle-fill"

[emoji]
"warning" = "⚠️"
`);

  assert.equal(iconMap["sf-symbols"].fasta, "point.3.connected.trianglepath.dotted");
  assert.equal(iconMap.windows.download, "\uE896");
  assert.equal(iconMap.windows.refresh, " \uE72C");
  assert.equal(iconMap.bootstrap.warning, "exclamation-triangle-fill");
  assert.equal(iconMap.emoji.warning, "⚠️");
});

test("icon map TOML rejects malformed content", async () => {
  const { parseIconMapToml } = await import("../dist/shared/icon-map.js");
  assert.throws(() => parseIconMapToml(`[emoji]\n"warning" = "\\uZZZZ"`), /Invalid icon map TOML at line 2/);
  assert.throws(() => parseIconMapToml(`[emoji]\n"warning" "⚠️"`), /Invalid icon map TOML at line 2/);
  assert.throws(() => parseIconMapToml(`[emoji]\n"warning" = "⚠️" trailing`), /Invalid icon map TOML at line 2/);
});

test("bundle loader merges built-in and bundle icon maps", async () => {
  const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
  const directory = await mkdtemp(path.join(tmpdir(), "gui-for-cli-icon-map-"));
  await writeFile(
    path.join(directory, "manifest.json"),
    JSON.stringify({
      id: "icon-map-bundle",
      displayName: "Icon Map Bundle",
      summary: "Tests bundle icon maps.",
      iconName: "fasta",
      pages: [{ id: "main", title: "Main", summary: "Main page.", sections: [] }],
    })
  );
  await writeFile(
    path.join(directory, "iconmap.toml"),
    `
[sf-symbols]
"fasta" = "point.3.connected.trianglepath.dotted"

[bootstrap]
"fasta" = "diagram-3"
`
  );

  const { loadLocalizedBundle } = await import("../dist/web/src/server/bundle-loader.js");
  try {
    const bundle = await loadLocalizedBundle(undefined, repoRoot, directory, directory);

    assert.equal(bundle.iconMap["sf-symbols"].fasta, "point.3.connected.trianglepath.dotted");
    assert.equal(bundle.iconMap.bootstrap.fasta, "diagram-3");
    assert.equal(bundle.iconMap.bootstrap.terminal, "terminal");
  } finally {
    await rm(directory, { force: true, recursive: true });
  }
});

test("bundle loader surfaces invalid bundle icon map errors", async () => {
  const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
  const directory = await mkdtemp(path.join(tmpdir(), "gui-for-cli-icon-map-invalid-"));
  await writeFile(
    path.join(directory, "manifest.json"),
    JSON.stringify({
      id: "icon-map-bundle-invalid",
      displayName: "Invalid Icon Map Bundle",
      summary: "Tests invalid icon maps.",
      iconName: "fasta",
      pages: [{ id: "main", title: "Main", summary: "Main page.", sections: [] }],
    })
  );
  await writeFile(path.join(directory, "iconmap.toml"), `[emoji]\n"play" = "\\uZZZZ"\n`);

  const { loadLocalizedBundle } = await import("../dist/web/src/server/bundle-loader.js");
  try {
    await assert.rejects(
      () => loadLocalizedBundle(undefined, repoRoot, directory, directory),
      /Invalid icon map TOML at line 2/
    );
  } finally {
    await rm(directory, { force: true, recursive: true });
  }
});
