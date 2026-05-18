import assert from "node:assert/strict";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import test from "node:test";

const { effectiveWebUIFont, isAppleOperatingSystem } = await import("../dist/web/src/client/platform.js");
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
    path("dist-root", "web", "src", "client", "view", "actions.js"),
  );
  assert.equal(
    distModulePath("/shared/rendering.js", "dist-root"),
    path("dist-root", "shared", "rendering.js"),
  );
  assert.equal(distModulePath("/client/../server/main.js", "dist-root"), undefined);
});

test("loads bundle distribution metadata", async () => {
  const directory = await mkdtemp(path(tmpdir(), "gui-for-cli-bundle-metadata-"));
  try {
    await writeFile(path(directory, "manifest.json"), JSON.stringify({
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
  const directory = await mkdtemp(path(tmpdir(), "gui-for-cli-platform-script-safe-"));
  try {
    await mkdir(path(directory, "scripts", "windows"), { recursive: true });
    await mkdir(path(directory, "scripts", "posix"), { recursive: true });
    await writeFile(path(directory, "scripts", "windows", "safe.ps1"), "Write-Output safe\n");
    await writeFile(path(directory, "scripts", "posix", "safe.sh"), "echo safe\n");
    const { resolvePlatformScriptPath } = await import("../dist/web/src/server/platform-scripts.js");

    await assert.rejects(
      () => resolvePlatformScriptPath("scripts/../../outside.sh", directory),
      /Bundle script path escapes bundle root/
    );
    assert.equal(
      await resolvePlatformScriptPath("scripts/safe.sh", directory),
      process.platform === "win32"
        ? path(directory, "scripts", "windows", "safe.ps1")
        : path(directory, "scripts", "posix", "safe.sh")
    );
  } finally {
    await rm(directory, { force: true, recursive: true });
  }
});

function path(...parts) {
  return parts.join(process.platform === "win32" ? "\\" : "/");
}
