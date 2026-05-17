import assert from "node:assert/strict";
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

function path(...parts) {
  return parts.join(process.platform === "win32" ? "\\" : "/");
}
