import assert from "node:assert/strict";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { conditionMatches, displayCommand, hydrateRows } from "../dist/shared/rendering.js";
import { loadLocalizedBundle } from "../dist/web/src/server/bundle-loader.js";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
const conformanceBundleRoot = path.join(repoRoot, "tests/conformance/basic-bundle");
const wgsExtractBundleRoot = path.join(repoRoot, "examples/WGSExtract");

test("conformance bundle preserves shared runtime semantics in TypeScript", async () => {
  const bundle = await loadLocalizedBundle("en", repoRoot, conformanceBundleRoot, conformanceBundleRoot);
  const { manifest } = bundle;

  assert.equal(manifest.id, "conformance-basic");
  assert.equal(manifest.displayName, "Conformance Basic");
  assert.equal(manifest.summary, "Exercises common bundle runtime semantics.");
  assert.equal(manifest.textIcon, "🧪");
  assert.equal(manifest.sidebarIconStyle, "emoji");
  assert.equal(manifest.terminalTextDirection, "ltr");
  assert.deepEqual(manifest.pages.map((page) => page.id), ["main"]);
  assert.equal(manifest.pages[0].title, "Main");
  assert.equal(manifest.pages[0].sidebarGroup, "Main Group");
  assert.equal(manifest.setup.steps[0].label, "Install dependencies");

  assert.deepEqual(
    manifest.exitCodeReference.find((entry) => entry.code === 7),
    { code: 7, title: "Custom warning", summary: "A custom warning exit code.", severity: "warning" },
  );
  assert.equal(manifest.exitCodeReference.find((entry) => entry.code === 127).title, "Command not found");

  const section = manifest.pages[0].sections[0];
  const input = section.controls.find((control) => control.id === "input_path");
  const refs = section.controls.find((control) => control.id === "refs");
  const settings = section.controls.find((control) => control.id === "settings");
  const run = section.actions.find((action) => action.id === "run");

  assert.equal(input.label, "Input BAM");
  assert.equal(input.value, "/tmp/input.bam");
  assert.equal(settings.configFile.path, "{{bundleWorkspace}}/settings/config.toml");
  assert.equal(settings.configFile.bootstrap.mode, "createIfMissing");
  assert.equal(settings.settings[0].key, "output_dir");
  assert.equal(bundle.fieldValues.input_path, "/tmp/input.bam");
  assert.equal(bundle.configValues["settings.out_dir"], "out");

  const rows = hydrateRows(refs);
  assert.deepEqual(rows, [
    {
      id: "hg38",
      title: "GRCh38",
      values: { code: "hs38", status: "installed" },
      status: "installed",
      tags: [{ id: "recommended", title: "Recommended", style: "primary" }],
      tooltip: undefined,
    },
  ]);

  const context = {
    fieldValues: { input_path: "/tmp/input.bam", "library.ready": "true" },
    checkedOptions: {},
    configValues: { out_dir: "out" },
    rowValues: { ...rows[0].values, id: rows[0].id, status: rows[0].status, locked: "false" },
    bundleRootPath: conformanceBundleRoot,
  };

  assert.equal(conditionMatches(run.visibleWhen[0], context), true);
  assert.equal(conditionMatches(run.disabledWhen[0], context), false);
  assert.equal(displayCommand(run.command, context), "tool run /tmp/input.bam out");

  const rowAction = refs.rowActions[0];
  assert.equal(conditionMatches(rowAction.visibleWhen[0], context), true);
  assert.equal(conditionMatches(rowAction.disabledWhen[0], context), false);
  assert.equal(displayCommand(rowAction.command, context), "tool verify hs38 /tmp/input.bam");
});

test("conformance bundle applies requested localization overlays in TypeScript", async () => {
  const bundle = await loadLocalizedBundle("es", repoRoot, conformanceBundleRoot, conformanceBundleRoot);

  assert.equal(bundle.localizationCode, "es");
  assert.equal(bundle.manifest.displayName, "Conformidad básica");
  assert.equal(bundle.manifest.pages[0].title, "Principal");
  assert.equal(bundle.manifest.pages[0].sections[0].actions[0].title, "Ejecutar flujo");
  assert.equal(bundle.manifest.summary, "Exercises common bundle runtime semantics.");
});

test("WGSExtract exposes genome library controls in TypeScript", async () => {
  const bundle = await loadLocalizedBundle("en", repoRoot, wgsExtractBundleRoot, wgsExtractBundleRoot);
  const library = bundle.manifest.pages.find((page) => page.id === "library");
  const settingsPage = bundle.manifest.pages.find((page) => page.id === "settings");

  assert.ok(library, "library page exists");
  assert.ok(settingsPage, "settings page exists");
  const libraryPaths = library.sections.find((section) => section.id === "library-paths");
  assert.ok(libraryPaths, "library paths section exists");
  const genomeLibraryControl = libraryPaths.controls.find((control) => control.id === "genome_library");
  assert.ok(genomeLibraryControl, "genome library path control exists");
  assert.equal(genomeLibraryControl.kind, "path");

  const testGenome = library.sections.find((section) => section.id === "test-genome-data");
  assert.ok(testGenome, "test genome section exists");
  assert.equal(testGenome.dataSource.path, "scripts/test-genome-library.py");
  assert.deepEqual(testGenome.dataSource.arguments, ["state", "{{genome_library}}"]);
  const downloadAction = testGenome.actions.find((action) => action.id === "test-genome-download");
  assert.ok(downloadAction, "test genome download action exists");
  assert.deepEqual(
    downloadAction.command.arguments,
    ["download", "{{genome_library}}"],
  );
  const deleteAction = testGenome.actions.find((action) => action.id === "test-genome-delete");
  assert.ok(deleteAction, "test genome delete action exists");
  assert.ok(deleteAction.confirm);

  const settings = settingsPage.sections[0].controls[0];
  const genomeLibrarySetting = settings.settings.find((setting) => setting.id === "genome_library");
  assert.ok(genomeLibrarySetting, "genome library setting exists");
  assert.equal(genomeLibrarySetting.key, "genome_library");
});
