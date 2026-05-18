import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import nodePath from "node:path";
import test from "node:test";

const { effectiveWebUIFont, isAppleOperatingSystem } = await import("../dist/web/src/client/platform.js");
const { createDevReload } = await import("../dist/web/src/server/dev-reload.js");
const { distModulePath } = await import("../dist/web/src/server/paths.js");

test("detects Apple operating systems for WebUI font selection", () => {
  assert.equal(isAppleOperatingSystem({ platform: "MacIntel", userAgent: "Mozilla/5.0" }), true);
  assert.equal(isAppleOperatingSystem({ platform: "iPhone", userAgent: "Mozilla/5.0" }), true);
  assert.equal(isAppleOperatingSystem({ platform: "Linux x86_64", userAgent: "Mozilla/5.0" }), false);
});

test("uses SF Pro automatically on Apple operating systems", () => {
  assert.equal(effectiveWebUIFont("system", { platform: "MacIntel" }), "sf-pro");
  assert.equal(effectiveWebUIFont("system", { platform: "iPad" }), "sf-pro");
  assert.equal(effectiveWebUIFont("system", { platform: "Linux x86_64" }), "system");
  assert.equal(effectiveWebUIFont("sfPro", { platform: "Linux x86_64" }), "sf-pro");
});

test("resolves nested compiled WebUI modules safely", () => {
  assert.equal(
    distModulePath("/client/view/actions.js", "dist-root"),
    joinedPath("dist-root", "web", "src", "client", "view", "actions.js"),
  );
  assert.equal(
    distModulePath("/shared/rendering.js", "dist-root"),
    joinedPath("dist-root", "shared", "rendering.js"),
  );
  assert.equal(distModulePath("/client/../server/main.js", "dist-root"), undefined);
});

test("dev reload watches nested compiled source directories", async () => {
  const tempRoot = await mkdtemp(nodePath.join(tmpdir(), "gui-for-cli-dev-reload-"));
  let closeWatcher = () => {};
  try {
    const distRoot = nodePath.join(tempRoot, "dist");
    const webRoot = nodePath.join(tempRoot, "web");
    const nestedClientRoot = nodePath.join(distRoot, "web", "src", "client", "view");
    await mkdir(nestedClientRoot, { recursive: true });
    await mkdir(nodePath.join(distRoot, "shared"), { recursive: true });
    await mkdir(webRoot, { recursive: true });

    const response = new MockSseResponse();
    const devReload = createDevReload({ enabled: true, distRoot, webRoot });
    devReload.addClient(response);
    closeWatcher = devReload.installWatcher();

    const reloadEvent = response.nextWriteContaining("event: reload");
    await new Promise((resolve) => setTimeout(resolve, 25));
    await writeFile(nodePath.join(nestedClientRoot, "actions.js"), "changed\n");

    assert.match(await reloadEvent, /data: changed/);
  } finally {
    closeWatcher();
    await rm(tempRoot, { recursive: true, force: true });
  }
});

test("loads bundle distribution metadata", async () => {
  const directory = await mkdtemp(joinedPath(tmpdir(), "gui-for-cli-bundle-metadata-"));
  try {
    await writeFile(joinedPath(directory, "manifest.json"), JSON.stringify({
      id: "metadata-bundle",
      displayName: "Metadata Bundle",
      version: "3.2.1",
    }));
    const { loadBundleMetadata, packageFileStem } = await import("../scripts/bundle-metadata.mjs");

    assert.deepEqual(await loadBundleMetadata(directory), {
      id: "metadata-bundle",
      displayName: "Metadata Bundle",
      version: "3.2.1",
    });
    assert.equal(packageFileStem("WGS Extract 0.3"), "WGS-Extract-0.3");
  } finally {
    await rm(directory, { force: true, recursive: true });
  }
});

test("platform script resolution rejects paths that escape the bundle root", async () => {
  const directory = await mkdtemp(joinedPath(tmpdir(), "gui-for-cli-platform-script-safe-"));
  try {
    await mkdir(joinedPath(directory, "scripts", "windows"), { recursive: true });
    await mkdir(joinedPath(directory, "scripts", "posix"), { recursive: true });
    await writeFile(joinedPath(directory, "scripts", "windows", "safe.ps1"), "Write-Output safe\n");
    await writeFile(joinedPath(directory, "scripts", "posix", "safe.sh"), "echo safe\n");
    const { resolvePlatformScriptPath } = await import("../dist/web/src/server/platform-scripts.js");

    await assert.rejects(
      () => resolvePlatformScriptPath("scripts/../../outside.sh", directory),
      /Bundle script path escapes bundle root/
    );
    const resolvedScript = await resolvePlatformScriptPath("scripts/safe.sh", directory);
    assert.equal(nodePath.basename(nodePath.dirname(resolvedScript)), process.platform === "win32" ? "windows" : "posix");
    assert.equal(nodePath.basename(resolvedScript), process.platform === "win32" ? "safe.ps1" : "safe.sh");
    assert.equal(await readFile(resolvedScript, "utf8"), process.platform === "win32" ? "Write-Output safe\n" : "echo safe\n");
  } finally {
    await rm(directory, { force: true, recursive: true });
  }
});

function joinedPath(...parts) {
  return parts.join(process.platform === "win32" ? "\\" : "/");
}

class MockSseResponse extends EventEmitter {
  writeHead() {}

  write(chunk) {
    this.emit("write", String(chunk));
    return true;
  }

  nextWriteContaining(fragment) {
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.off("write", onWrite);
        reject(new Error(`Timed out waiting for ${fragment}`));
      }, 1_000);
      const onWrite = (chunk) => {
        if (!chunk.includes(fragment)) {
          return;
        }
        clearTimeout(timer);
        this.off("write", onWrite);
        resolve(chunk);
      };
      this.on("write", onWrite);
    });
  }
}
