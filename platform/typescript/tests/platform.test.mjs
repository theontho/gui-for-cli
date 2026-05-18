import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
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
    devReload.installWatcher();

    const reloadEvent = response.nextWriteContaining("event: reload");
    await new Promise((resolve) => setTimeout(resolve, 25));
    await writeFile(nodePath.join(nestedClientRoot, "actions.js"), "changed\n");

    assert.match(await reloadEvent, /data: changed/);
  } finally {
    await rm(tempRoot, { recursive: true, force: true });
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
