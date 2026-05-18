import assert from "node:assert/strict";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
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
  try {
    await writeFile(
      path.join(directory, "manifest.json"),
      JSON.stringify({
        id: "icon-map-bundle",
        version: "2.3.4",
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
    const bundle = await loadLocalizedBundle(undefined, repoRoot, directory, directory);

    assert.equal(bundle.iconMap["sf-symbols"].fasta, "point.3.connected.trianglepath.dotted");
    assert.equal(bundle.manifest.version, "2.3.4");
    assert.equal(bundle.iconMap.bootstrap.fasta, "diagram-3");
    assert.equal(bundle.iconMap.bootstrap.terminal, "terminal");
  } finally {
    await rm(directory, { force: true, recursive: true });
  }
});

test("bundle loader surfaces invalid bundle icon map errors", async () => {
  const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
  const directory = await mkdtemp(path.join(tmpdir(), "gui-for-cli-icon-map-invalid-"));
  try {
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
    await assert.rejects(
      () => loadLocalizedBundle(undefined, repoRoot, directory, directory),
      /Invalid icon map TOML at line 2/
    );
  } finally {
    await rm(directory, { force: true, recursive: true });
  }
});

test("bundle loader rejects incomplete platform script folders", async () => {
  const directory = await mkdtemp(path.join(tmpdir(), "gui-for-cli-script-platforms-"));
  try {
    await mkdir(path.join(directory, "scripts", "windows"), { recursive: true });
    await writeFile(
      path.join(directory, "manifest.json"),
      JSON.stringify({
        id: "script-platforms",
        displayName: "Script Platforms",
        summary: "Tests platform script validation.",
        pages: [{ id: "main", title: "Main", summary: "Main page.", sections: [] }],
        setup: {
          steps: [
            { id: "install", kind: "setupScript", label: "Install", value: "scripts/install.sh" },
            { id: "verify", kind: "setupScript", label: "Verify", value: "scripts/verify.sh" },
          ],
        },
      })
    );
    await writeFile(path.join(directory, "scripts", "windows", "install.ps1"), "Write-Output install\n");

    const { loadManifestFromRoot } = await import("../dist/web/src/server/bundle-loader.js");
    await assert.rejects(
      () => loadManifestFromRoot(directory),
      /Platform script folder .*scripts.*windows.*missing required scripts: verify/
    );
  } finally {
    await rm(directory, { force: true, recursive: true });
  }
});

test("bundle loader localizes language options and marks AI-translated bundle strings", async () => {
  const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
  const directory = await mkdtemp(path.join(tmpdir(), "gui-for-cli-locales-"));
  try {
    await mkdir(path.join(directory, "strings"), { recursive: true });
    await writeFile(
      path.join(directory, "manifest.json"),
      JSON.stringify({
        id: "localized-options",
        displayName: "Localized Options",
        summary: "Tests localized language names.",
        pages: [{ id: "main", title: "Main", summary: "Main.", sections: [] }],
      })
    );
    await writeFile(path.join(directory, "strings", "strings.en.toml"), `"language.name" = "English"\n`);
    await writeFile(
      path.join(directory, "strings", "strings.es.toml"),
      `"language.aiTranslated" = "true"\n"language.name" = "Español"\n`
    );

    const { loadLocalizedBundle } = await import("../dist/web/src/server/bundle-loader.js");
    const bundle = await loadLocalizedBundle("es", repoRoot, directory, directory);
    const english = bundle.localizationOptions.find((option) => option.code === "en");
    const spanish = bundle.localizationOptions.find((option) => option.code === "es");

    assert.equal(english.displayName, "English (Inglés)");
    assert.equal(spanish.displayName, "Español (Español)");
    assert.equal(spanish.isAITranslated, true);
  } finally {
    await rm(directory, { force: true, recursive: true });
  }
});

test("bundle loader bootstraps first-run config defaults before returning state", async () => {
  const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
  const directory = await mkdtemp(path.join(tmpdir(), "gui-for-cli-config-bootstrap-"));
  try {
    await mkdir(path.join(directory, "scripts"), { recursive: true });
    await writeFile(
      path.join(directory, "scripts", "bootstrap-config.sh"),
      `#!/bin/sh
set -eu
escaped_workspace="$(printf '%s' "$GUI_FOR_CLI_BUNDLE_WORKSPACE" | sed 's/\\\\/\\\\\\\\/g; s/"/\\\\"/g')"
count_file="$GUI_FOR_CLI_BUNDLE_WORKSPACE/bootstrap.count"
count=0
if [ -f "$count_file" ]; then count="$(cat "$count_file")"; fi
printf '%s\n' "$((count + 1))" > "$count_file"
printf '{"values":{"output_directory":"%s/output","reference_library":"%s/reference"}}\\n' "$escaped_workspace" "$escaped_workspace"
`
    );
    await writeFile(
      path.join(directory, "manifest.json"),
      JSON.stringify({
        id: "config-bootstrap",
        displayName: "Config Bootstrap",
        summary: "Tests config bootstrapping.",
        pages: [
          {
            id: "settings",
            title: "Settings",
            summary: "Settings.",
            sections: [
              {
                id: "paths",
                controls: [
                  {
                    id: "tool-settings",
                    label: "Tool Settings",
                    kind: "configEditor",
                    configFile: {
                      path: "{{bundleWorkspace}}/settings/config.toml",
                      format: "toml",
                      bootstrap: {
                        mode: "mergeMissing",
                        script: { path: "scripts/bootstrap-config.sh" },
                      },
                    },
                    settings: [
                      { id: "out_dir", key: "output_directory", label: "Output Directory", kind: "path" },
                      { id: "ref_path", key: "reference_library", label: "Reference Library", kind: "path" },
                    ],
                  },
                ],
              },
            ],
          },
        ],
      })
    );

    const { loadLocalizedBundle } = await import("../dist/web/src/server/bundle-loader.js");
    const bundle = await loadLocalizedBundle(undefined, repoRoot, directory, directory);

    assert.equal(bundle.configValues["tool-settings.out_dir"], `${directory}/output`);
    assert.equal(bundle.configValues["tool-settings.ref_path"], `${directory}/reference`);
    assert.equal((await readFile(path.join(directory, "bootstrap.count"), "utf8")).trim(), "1");

    await loadLocalizedBundle(undefined, repoRoot, directory, directory);
    assert.equal((await readFile(path.join(directory, "bootstrap.count"), "utf8")).trim(), "1");
  } finally {
    await rm(directory, { force: true, recursive: true });
  }
});
