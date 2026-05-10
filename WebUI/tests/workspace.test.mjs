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
