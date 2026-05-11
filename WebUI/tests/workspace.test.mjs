import assert from "node:assert/strict";
import { mkdtemp, mkdir, readFile, rm, stat, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";

test("bundle workspace sync preserves runtime, state, and bundle-local config", async () => {
  const tempRoot = await mkdtemp(path.join(tmpdir(), "gui-for-cli-webui-workspace-"));
  const originalHome = process.env.HOME;
  process.env.HOME = tempRoot;

  try {
    const { prepareBundleWorkspace } = await import("../dist/server/workspace.js");
    const sourceRoot = path.join(tempRoot, "source");
    await mkdir(sourceRoot, { recursive: true });
    await writeFile(path.join(sourceRoot, "manifest.json"), "{\"id\":\"stateful.bundle\"}\n");

    const manifest = {
      id: "stateful.bundle",
      pages: [
        {
          sections: [
            {
              controls: [
                {
                  id: "settings",
                  kind: "configEditor",
                  configFile: { path: "{{bundleWorkspace}}/settings/config.toml" },
                },
              ],
            },
          ],
        },
      ],
    };

    const workspaceRoot = await prepareBundleWorkspace(manifest, sourceRoot);
    await mkdir(path.join(workspaceRoot, "runtime"), { recursive: true });
    await writeFile(path.join(workspaceRoot, "runtime", "installed.txt"), "keep runtime");
    await writeFile(path.join(workspaceRoot, "state.json"), "{\"colorTheme\":\"dark\"}\n");
    await mkdir(path.join(workspaceRoot, "settings"), { recursive: true });
    await writeFile(path.join(workspaceRoot, "settings", "config.toml"), "output_directory = \"/tmp/out\"\n");
    await writeFile(path.join(workspaceRoot, "stale.txt"), "remove me");

    await prepareBundleWorkspace(manifest, sourceRoot);

    assert.equal(await readFile(path.join(workspaceRoot, "runtime", "installed.txt"), "utf8"), "keep runtime");
    assert.equal(await readFile(path.join(workspaceRoot, "state.json"), "utf8"), "{\"colorTheme\":\"dark\"}\n");
    assert.equal(
      await readFile(path.join(workspaceRoot, "settings", "config.toml"), "utf8"),
      "output_directory = \"/tmp/out\"\n",
    );
    await assert.rejects(stat(path.join(workspaceRoot, "stale.txt")), /ENOENT/);
  } finally {
    if (originalHome == null) {
      delete process.env.HOME;
    } else {
      process.env.HOME = originalHome;
    }
    await rm(tempRoot, { recursive: true, force: true });
  }
});

test("bundle workspace sync metadata resyncs changed source files", async () => {
  const tempRoot = await mkdtemp(path.join(tmpdir(), "gui-for-cli-webui-workspace-sync-"));
  const originalHome = process.env.HOME;
  process.env.HOME = tempRoot;

  try {
    const { prepareBundleWorkspace } = await import("../dist/server/workspace.js");
    const sourceRoot = path.join(tempRoot, "source");
    await mkdir(path.join(sourceRoot, "assets"), { recursive: true });
    await writeFile(path.join(sourceRoot, "manifest.json"), "{\"id\":\"sync.bundle\"}\n");
    await writeFile(path.join(sourceRoot, "assets", "message.txt"), "first\n");
    const manifest = { id: "sync.bundle", pages: [] };

    const workspaceRoot = await prepareBundleWorkspace(manifest, sourceRoot);
    const metadataPath = path.join(workspaceRoot, ".workspace-sync.json");
    const firstMetadata = await readFile(metadataPath, "utf8");
    assert.equal(await readFile(path.join(workspaceRoot, "assets", "message.txt"), "utf8"), "first\n");

    await new Promise((resolve) => setTimeout(resolve, 10));
    await writeFile(path.join(sourceRoot, "assets", "message.txt"), "second changed\n");
    await prepareBundleWorkspace(manifest, sourceRoot);

    assert.equal(await readFile(path.join(workspaceRoot, "assets", "message.txt"), "utf8"), "second changed\n");
    assert.notEqual(await readFile(metadataPath, "utf8"), firstMetadata);
  } finally {
    if (originalHome == null) {
      delete process.env.HOME;
    } else {
      process.env.HOME = originalHome;
    }
    await rm(tempRoot, { recursive: true, force: true });
  }
});

test("bundle state persists selected page id", async () => {
  const tempRoot = await mkdtemp(path.join(tmpdir(), "gui-for-cli-webui-state-"));

  try {
    const { loadBundleState, saveBundleState } = await import("../dist/server/config-store.js");
    await saveBundleState(
      {
        localizationCode: "en",
        selectedPageID: "library",
        setupRun: {
          status: "ok",
          results: [{ id: "pixi", label: "Pixi", kind: "pathTool", status: "ok", exitCode: 0 }],
          completedAt: "2026-05-09T18:54:22Z",
        },
        iconSet: "emoji",
        colorTheme: "dark",
        webUIFont: "sfPro",
      },
      tempRoot,
    );

    const state = await loadBundleState(tempRoot);
    assert.equal(state.selectedPageID, "library");
    assert.equal(state.setupRun.status, "ok");
    assert.equal(state.setupRun.results[0].id, "pixi");
    assert.equal(state.localizationCode, "en");
    assert.equal(state.iconSet, "emoji");
    assert.equal(state.colorTheme, "dark");
    assert.equal(state.webUIFont, "sfPro");
  } finally {
    await rm(tempRoot, { recursive: true, force: true });
  }
});
