import assert from "node:assert/strict";
import { chmod, lstat, mkdir, mkdtemp, readdir, readFile, rm, stat, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";

const { loadBundleState, saveBundleState, takeBundleStateWarning, writeFileAtomically } = await import("../dist/web/src/server/config-store.js");

async function tempDirectory(t) {
  const directory = await mkdtemp(path.join(tmpdir(), "gui-for-cli-config-store-"));
  t.after(() => rm(directory, { force: true, recursive: true }));
  return directory;
}

test("a truncated state.json is backed up and reported instead of silently reset", async (t) => {
  const bundleRoot = await tempDirectory(t);
  await writeFile(path.join(bundleRoot, "state.json"), '{"selectedPageID": "vcf", "fieldValues": {"sam');

  const state = await loadBundleState(bundleRoot);

  assert.equal(state.selectedPageID, null);
  const backups = (await readdir(bundleRoot)).filter((name) => name.startsWith("state.json.corrupt-"));
  assert.equal(backups.length, 1);
  assert.equal(await readFile(path.join(bundleRoot, backups[0]), "utf8"), '{"selectedPageID": "vcf", "fieldValues": {"sam');
  assert.match(takeBundleStateWarning(bundleRoot), /could not be read.*state\.json\.corrupt-/);
  assert.equal(takeBundleStateWarning(bundleRoot), undefined);
});

test("state.json read errors other than a missing file are not swallowed", async (t) => {
  const bundleRoot = await tempDirectory(t);
  await mkdir(path.join(bundleRoot, "state.json"));

  await assert.rejects(loadBundleState(bundleRoot), /EISDIR/);
});

test("state saves go through a temp file and leave no partial files behind", async (t) => {
  const bundleRoot = await tempDirectory(t);

  await Promise.all([
    saveBundleState({ selectedPageID: "a" }, bundleRoot),
    saveBundleState({ fieldValues: { sample: "HG001" } }, bundleRoot),
  ]);

  const saved = JSON.parse(await readFile(path.join(bundleRoot, "state.json"), "utf8"));
  assert.equal(saved.selectedPageID, "a");
  assert.deepEqual(saved.fieldValues, { sample: "HG001" });
  assert.deepEqual(await readdir(bundleRoot), ["state.json"]);
});

test("atomic writes follow symlinks and keep file permissions", { skip: process.platform === "win32" }, async (t) => {
  const directory = await tempDirectory(t);
  const target = path.join(directory, "real.toml");
  const link = path.join(directory, "linked.toml");
  await writeFile(target, "old\n");
  await chmod(target, 0o600);
  await symlink(target, link);

  await writeFileAtomically(link, "new\n");

  assert.equal(await readFile(target, "utf8"), "new\n");
  assert.equal((await stat(target)).mode & 0o777, 0o600);
  assert.ok((await lstat(link)).isSymbolicLink());
});
