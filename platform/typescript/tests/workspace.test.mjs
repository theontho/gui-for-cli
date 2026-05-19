import assert from "node:assert/strict";
import { mkdtemp, mkdir, readFile, rm, stat, utimes, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";

test("bundle workspace sync preserves runtime, state, and bundle-local config", async () => {
  const tempRoot = await mkdtemp(path.join(tmpdir(), "gui-for-cli-webui-workspace-"));
  const originalHome = process.env.HOME;
  const originalAppSupportName = process.env.GUI_FOR_CLI_APP_SUPPORT_NAME;
  process.env.HOME = tempRoot;
  process.env.GUI_FOR_CLI_APP_SUPPORT_NAME = "dev.guiforcli.webui";

  try {
    const { prepareBundleWorkspace } = await import("../dist/web/src/server/workspace.js");
    const { appSupportDirectory } = await import("../dist/web/src/server/paths.js");
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
    assert.equal(
      workspaceRoot,
      path.join(appSupportDirectory(), "BundleWorkspaces", "stateful.bundle"),
    );
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
    if (originalAppSupportName == null) {
      delete process.env.GUI_FOR_CLI_APP_SUPPORT_NAME;
    } else {
      process.env.GUI_FOR_CLI_APP_SUPPORT_NAME = originalAppSupportName;
    }
    await rm(tempRoot, { recursive: true, force: true });
  }
});

test("bundle workspace sync metadata resyncs changed source files", async () => {
  const tempRoot = await mkdtemp(path.join(tmpdir(), "gui-for-cli-webui-workspace-sync-"));
  const originalHome = process.env.HOME;
  process.env.HOME = tempRoot;

  try {
    const { prepareBundleWorkspace } = await import("../dist/web/src/server/workspace.js");
    const sourceRoot = path.join(tempRoot, "source");
    await mkdir(path.join(sourceRoot, "assets"), { recursive: true });
    await writeFile(path.join(sourceRoot, "manifest.json"), "{\"id\":\"sync.bundle\"}\n");
    await writeFile(path.join(sourceRoot, "assets", "message.txt"), "first\n");
    const manifest = { id: "sync.bundle", pages: [] };

    const workspaceRoot = await prepareBundleWorkspace(manifest, sourceRoot);
    const metadataPath = path.join(workspaceRoot, ".workspace-sync.json");
    const firstMetadata = await readFile(metadataPath, "utf8");
    assert.equal(await readFile(path.join(workspaceRoot, "assets", "message.txt"), "utf8"), "first\n");

    const messagePath = path.join(sourceRoot, "assets", "message.txt");
    const firstMessageMtime = (await stat(messagePath)).mtimeMs;
    await writeFile(messagePath, "second changed\n");
    await forceMtimeAdvance(messagePath, firstMessageMtime);
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

test("bundle workspace sync marks nested scripts executable", async (t) => {
  if (process.platform === "win32") {
    t.skip("POSIX executable bits are platform-specific.");
    return;
  }

  const tempRoot = await mkdtemp(path.join(tmpdir(), "gui-for-cli-webui-workspace-scripts-"));
  const originalHome = process.env.HOME;
  process.env.HOME = tempRoot;

  try {
    const { prepareBundleWorkspace } = await import("../dist/web/src/server/workspace.js");
    const sourceRoot = path.join(tempRoot, "source");
    await mkdir(path.join(sourceRoot, "scripts", "posix"), { recursive: true });
    await writeFile(path.join(sourceRoot, "manifest.json"), "{\"id\":\"script.bundle\"}\n");
    await writeFile(path.join(sourceRoot, "scripts", "posix", "test-genome-library.py"), "#!/usr/bin/env python3\n");
    await writeFile(path.join(sourceRoot, "scripts", "posix", "data.json"), "{}\n");

    const workspaceRoot = await prepareBundleWorkspace({ id: "script.bundle", pages: [] }, sourceRoot);
    const scriptMode = (await stat(path.join(workspaceRoot, "scripts", "posix", "test-genome-library.py"))).mode;
    const dataMode = (await stat(path.join(workspaceRoot, "scripts", "posix", "data.json"))).mode;

    assert.notEqual(scriptMode & 0o111, 0);
    assert.equal(dataMode & 0o111, 0);
  } finally {
    if (originalHome == null) {
      delete process.env.HOME;
    } else {
      process.env.HOME = originalHome;
    }
    await rm(tempRoot, { recursive: true, force: true });
  }
});

test("bundle workspace sync ignores non-directory scripts entries", async (t) => {
  if (process.platform === "win32") {
    t.skip("POSIX executable bits are platform-specific.");
    return;
  }

  const tempRoot = await mkdtemp(path.join(tmpdir(), "gui-for-cli-webui-workspace-scripts-file-"));
  const originalHome = process.env.HOME;
  process.env.HOME = tempRoot;

  try {
    const { prepareBundleWorkspace } = await import("../dist/web/src/server/workspace.js");
    const sourceRoot = path.join(tempRoot, "source");
    await mkdir(sourceRoot, { recursive: true });
    await writeFile(path.join(sourceRoot, "manifest.json"), "{\"id\":\"script-file.bundle\"}\n");
    await writeFile(path.join(sourceRoot, "scripts"), "not a directory\n");

    const workspaceRoot = await prepareBundleWorkspace({ id: "script-file.bundle", pages: [] }, sourceRoot);
    const scriptsMode = (await stat(path.join(workspaceRoot, "scripts"))).mode;

    assert.equal(await readFile(path.join(workspaceRoot, "scripts"), "utf8"), "not a directory\n");
    assert.equal(scriptsMode & 0o111, 0);
  } finally {
    if (originalHome == null) {
      delete process.env.HOME;
    } else {
      process.env.HOME = originalHome;
    }
    await rm(tempRoot, { recursive: true, force: true });
  }
});

test("bundle workspace sync ignores nested hidden files when fingerprinting", async () => {
  const tempRoot = await mkdtemp(path.join(tmpdir(), "gui-for-cli-webui-workspace-hidden-"));
  const originalHome = process.env.HOME;
  process.env.HOME = tempRoot;

  try {
    const { prepareBundleWorkspace } = await import("../dist/web/src/server/workspace.js");
    const sourceRoot = path.join(tempRoot, "source");
    await mkdir(path.join(sourceRoot, "assets"), { recursive: true });
    await writeFile(path.join(sourceRoot, "manifest.json"), "{\"id\":\"hidden.bundle\"}\n");
    await writeFile(path.join(sourceRoot, "assets", "message.txt"), "visible\n");
    await writeFile(path.join(sourceRoot, "assets", ".ignored.txt"), "hidden\n");
    const manifest = { id: "hidden.bundle", pages: [] };

    const workspaceRoot = await prepareBundleWorkspace(manifest, sourceRoot);
    const metadataPath = path.join(workspaceRoot, ".workspace-sync.json");
    const firstMetadata = await readFile(metadataPath, "utf8");
    assert.equal(await readFile(path.join(workspaceRoot, "assets", ".ignored.txt"), "utf8"), "hidden\n");

    const ignoredPath = path.join(sourceRoot, "assets", ".ignored.txt");
    const firstIgnoredMtime = (await stat(ignoredPath)).mtimeMs;
    await writeFile(ignoredPath, "hidden changed\n");
    await forceMtimeAdvance(ignoredPath, firstIgnoredMtime);
    await prepareBundleWorkspace(manifest, sourceRoot);

    assert.equal(await readFile(metadataPath, "utf8"), firstMetadata);
    assert.equal(await readFile(path.join(workspaceRoot, "assets", ".ignored.txt"), "utf8"), "hidden\n");
  } finally {
    if (originalHome == null) {
      delete process.env.HOME;
    } else {
      process.env.HOME = originalHome;
    }
    await rm(tempRoot, { recursive: true, force: true });
  }
});

async function forceMtimeAdvance(filePath, previousMtimeMs) {
  const nextMtime = new Date(Math.max(Date.now(), Math.ceil(previousMtimeMs) + 2_000));
  await utimes(filePath, nextMtime, nextMtime);
}

test("bundle state persists selected page id", async () => {
  const tempRoot = await mkdtemp(path.join(tmpdir(), "gui-for-cli-webui-state-"));

  try {
    const { loadBundleState, saveBundleState } = await import("../dist/web/src/server/config-store.js");
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
