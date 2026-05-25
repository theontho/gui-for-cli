import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import nodePath from "node:path";
import { Readable } from "node:stream";
import test from "node:test";

const { effectiveWebUIFont, isAppleOperatingSystem, isTauriRuntime, shouldRenderInPageBundleLoader } = await import("../dist/web/src/client/platform.js");
const { createDevReload } = await import("../dist/web/src/server/dev-reload.js");
const { distModulePath } = await import("../dist/web/src/server/paths.js");
const { createRequestHandler } = await import("../dist/web/src/server/routes.js");

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

test("detects Tauri runtime globals for native desktop UI affordances", () => {
  assert.equal(isTauriRuntime({}), false);
  assert.equal(isTauriRuntime({ __GUI_FOR_CLI_TAURI__: true }), true);
  assert.equal(isTauriRuntime({ __TAURI_INTERNALS__: {} }), true);
  assert.equal(isTauriRuntime({ __TAURI__: {} }), true);
  assert.equal(shouldRenderInPageBundleLoader({}), true);
  assert.equal(shouldRenderInPageBundleLoader({ __GUI_FOR_CLI_TAURI__: true }), false);
  assert.equal(shouldRenderInPageBundleLoader({ __TAURI_INTERNALS__: {} }), false);
  assert.equal(shouldRenderInPageBundleLoader({ __TAURI__: {} }), false);
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

test("Tauri distribution defaults include Linux distro packages", async () => {
  const {
    distributionBuildPlans,
    distributionPlanEnv,
    linuxBundleProductSuffix,
    parseBundleList,
    platformBundles,
  } = await import("../scripts/tauri-build-dist.mjs");

  assert.deepEqual(platformBundles("darwin"), ["app", "dmg"]);
  assert.deepEqual(platformBundles("linux"), ["deb", "rpm", "appimage"]);
  assert.deepEqual(platformBundles("win32"), ["nsis"]);
  assert.deepEqual(parseBundleList(" deb, rpm,appimage "), ["deb", "rpm", "appimage"]);
  assert.equal(linuxBundleProductSuffix("deb"), "Ubuntu WebUI");
  assert.equal(linuxBundleProductSuffix("rpm"), "Fedora WebUI");
  assert.equal(linuxBundleProductSuffix("appimage"), "Linux AppImage WebUI");
  assert.deepEqual(distributionBuildPlans(["deb", "rpm"], "linux"), [
    { bundles: ["deb"], env: { TAURI_PRODUCT_SUFFIX: "Ubuntu WebUI" } },
    { bundles: ["rpm"], env: { TAURI_PRODUCT_SUFFIX: "Fedora WebUI" } },
  ]);
  assert.deepEqual(distributionBuildPlans(["app", "dmg"], "darwin"), [
    { bundles: ["app", "dmg"], env: {} },
  ]);
  assert.deepEqual(distributionBuildPlans(["nsis"], "win32"), [
    { bundles: ["nsis"], env: {} },
  ]);
  assert.deepEqual(
    distributionPlanEnv(
      { TAURI_PRODUCT_SUFFIX: "Custom WebUI", TAURI_CLEAN_RELEASE_BUNDLE: "0", EXAMPLE: "caller" },
      { bundles: ["deb"], env: { TAURI_PRODUCT_SUFFIX: "Ubuntu WebUI" } },
      0,
    ),
    { TAURI_PRODUCT_SUFFIX: "Ubuntu WebUI", TAURI_CLEAN_RELEASE_BUNDLE: "1", EXAMPLE: "caller" },
  );
  assert.deepEqual(
    distributionPlanEnv(
      { TAURI_PRODUCT_SUFFIX: "Custom WebUI", EXAMPLE: "caller" },
      { bundles: ["app"], env: {} },
      0,
    ),
    { TAURI_PRODUCT_SUFFIX: "Custom WebUI", TAURI_CLEAN_RELEASE_BUNDLE: "1", EXAMPLE: "caller" },
  );
  assert.deepEqual(
    distributionPlanEnv(
      { TAURI_CLEAN_RELEASE_BUNDLE: "1" },
      { bundles: ["rpm"], env: { TAURI_PRODUCT_SUFFIX: "Fedora WebUI" } },
      1,
    ),
    { TAURI_PRODUCT_SUFFIX: "Fedora WebUI", TAURI_CLEAN_RELEASE_BUNDLE: "0" },
  );
});

test("Tauri product name includes platform and WebUI distribution", async () => {
  const { tauriProductName } = await import("../scripts/run-tauri.mjs");

  assert.equal(tauriProductName("WGSExtract", "darwin"), "WGSExtract macOS WebUI");
  assert.equal(tauriProductName("WGSExtract macOS WebUI", "darwin"), "WGSExtract macOS WebUI");
  assert.equal(tauriProductName("WGSExtract", "win32"), "WGSExtract Windows WebUI");
  assert.equal(tauriProductName("WGSExtract", "linux"), "WGSExtract Linux WebUI");
  assert.equal(tauriProductName("WGSExtract", "linux", "Ubuntu WebUI"), "WGSExtract Ubuntu WebUI");
  assert.equal(tauriProductName(" WGSExtract ", "linux", " Ubuntu WebUI "), "WGSExtract Ubuntu WebUI");
  assert.equal(tauriProductName("WGSExtract", "linux", "   "), "WGSExtract Linux WebUI");
  assert.equal(tauriProductName(null, "darwin"), null);
  assert.equal(tauriProductName("   ", "linux"), null);
});

test("About dialog renders bundle and tool versions with clickable GitHub link", async () => {
  const previousWindow = globalThis.window;
  const previousLocalStorage = globalThis.localStorage;
  const localStorage = memoryStorage();
  globalThis.window = { GUI_FOR_CLI_APPLICATION_NAME: "GUI for CLI", GUI_FOR_CLI_APPLICATION_VERSION: "9.8.7" };
  globalThis.localStorage = localStorage;
  try {
    const { state } = await import("../dist/web/src/client/state.js");
    const { aboutVersionRows, githubURL, renderAboutDialog } = await import(`../dist/web/src/client/view/about.js?about=${Date.now()}`);
    state.manifest = {
      version: "0.3.5",
      setup: { steps: [{ toolName: "WGS Extract CLI", toolVersion: "v0.3.5" }] },
      uninstall: { steps: [] },
    };

    assert.deepEqual(aboutVersionRows({ guiForCliVersion: state.applicationVersion, manifest: state.manifest }), [
      { label: "GUI for CLI version", value: "9.8.7" },
      { label: "Bundle version", value: "0.3.5" },
      { label: "Tool version", value: "WGS Extract CLI v0.3.5" },
    ]);
    const html = renderAboutDialog();
    assert.match(html, /MIT License/);
    assert.match(html, /GUI for CLI version/);
    assert.match(html, /Bundle version/);
    assert.match(html, /Tool version/);
    assert.match(html, /WGS Extract CLI v0\.3\.5/);
    assert.match(html, new RegExp(`href="${githubURL}"[^>]+data-about-github`));
  } finally {
    if (previousWindow === undefined) {
      delete globalThis.window;
    } else {
      globalThis.window = previousWindow;
    }
    if (previousLocalStorage === undefined) {
      delete globalThis.localStorage;
    } else {
      globalThis.localStorage = previousLocalStorage;
    }
  }
});

test("Tauri updater config remains valid when updates are not configured", async () => {
  const { tauriUpdaterPluginConfig } = await import("../scripts/run-tauri.mjs");

  assert.deepEqual(tauriUpdaterPluginConfig({}), { pubkey: "", endpoints: [] });
  assert.deepEqual(
    tauriUpdaterPluginConfig({
      TAURI_UPDATER_PUBKEY: "public-key",
      TAURI_UPDATER_ENDPOINTS: "https://example.test/latest.json,https://example.test/beta.json",
      TAURI_UPDATER_WINDOWS_INSTALL_MODE: "quiet",
    }),
    {
      pubkey: "public-key",
      endpoints: ["https://example.test/latest.json", "https://example.test/beta.json"],
      windows: { installMode: "quiet" },
    },
  );
});

test("Tauri updater IPC commands are allowed for the remote WebUI", async () => {
  const capability = JSON.parse(await readFile(new URL("../web/packagers/tauri/capabilities/main.json", import.meta.url), "utf8"));
  const buildScript = await readFile(new URL("../web/packagers/tauri/build.rs", import.meta.url), "utf8");

  assert.ok(capability.remote?.urls?.includes("http://127.0.0.1:*"), "Updater capability must include the remote WebUI origin scope");

  for (const permission of [
    "allow-gfc-update-check",
    "allow-gfc-update-download",
    "allow-gfc-update-install",
  ]) {
    assert.ok(capability.permissions.includes(permission), `${permission} must be allowed for http://127.0.0.1:*`);
  }

  for (const command of [
    "gfc_update_check",
    "gfc_update_download",
    "gfc_update_install",
  ]) {
    assert.match(buildScript, new RegExp(`"${command}"`));
  }
});

test("Tauri updater menu follows platform menu conventions", async () => {
  const mainRs = await readFile(new URL("../web/packagers/tauri/src/main.rs", import.meta.url), "utf8");

  assert.doesNotMatch(mainRs, /Submenu::with_items\(app, "Updates"/);
  assert.match(mainRs, /#\[cfg\(target_os = "macos"\)\]\s+add_check_for_updates_to_app_menu/);
  assert.match(mainRs, /let app_menu_title = app_menu_title\(app\);/);
  assert.match(mainRs, /find_submenu_by_text\(menu, &app_menu_title\)/);
  assert.match(mainRs, /#\[cfg\(not\(target_os = "macos"\)\)\]\s+add_items_to_file_menu\(app, menu, &\[load_bundle, check_for_updates\]\)/);
});

test("Tauri child env keeps macOS signing identity aligned", async () => {
  const { effectiveMacOSSigningIdentity, tauriChildEnv } = await import("../scripts/run-tauri.mjs");
  const env = {
    APPLE_SIGNING_IDENTITY: "",
    TAURI_MACOS_SIGNING_IDENTITY: "-",
  };

  assert.equal(effectiveMacOSSigningIdentity(env), "-");
  assert.deepEqual(tauriChildEnv(env, "darwin"), {
    APPLE_SIGNING_IDENTITY: "-",
    TAURI_MACOS_SIGNING_IDENTITY: "-",
  });
  assert.deepEqual(tauriChildEnv(env, "linux"), env);

  const appleOnlyEnv = { APPLE_SIGNING_IDENTITY: "Developer ID Application: Example" };
  assert.equal(effectiveMacOSSigningIdentity(appleOnlyEnv), "Developer ID Application: Example");
  assert.deepEqual(tauriChildEnv(appleOnlyEnv, "darwin"), {
    APPLE_SIGNING_IDENTITY: "Developer ID Application: Example",
    TAURI_MACOS_SIGNING_IDENTITY: "Developer ID Application: Example",
  });

  assert.equal(effectiveMacOSSigningIdentity({}), "");
  assert.deepEqual(tauriChildEnv({}, "darwin"), {});
});

test("render scroll state restores only matching containers", async () => {
  const { captureScrollState, restoreScrollState } = await import("../dist/web/src/client/scroll-state.js");
  const original = { scrollLeft: 13, scrollTop: 377 };
  const replacement = { scrollLeft: 0, scrollTop: 0 };
  const other = { scrollLeft: 0, scrollTop: 0 };
  const snapshot = captureScrollState(original, "settings");

  assert.deepEqual(snapshot, { key: "settings", left: 13, top: 377 });
  assert.equal(restoreScrollState(other, snapshot, "fastq"), false);
  assert.deepEqual(other, { scrollLeft: 0, scrollTop: 0 });
  assert.equal(restoreScrollState(replacement, snapshot, "settings"), true);
  assert.deepEqual(replacement, { scrollLeft: 13, scrollTop: 377 });
});

test("Tauri NSIS uninstall app data cleanup includes XDG data roots", async () => {
  const config = JSON.parse(await readFile(new URL("../web/packagers/tauri/tauri.conf.json", import.meta.url), "utf8"));
  const hooks = await readFile(new URL("../web/packagers/tauri/nsis-hooks.nsh", import.meta.url), "utf8");

  assert.equal(config.bundle.windows.nsis.installerHooks, "nsis-hooks.nsh");
  assert.match(hooks, /RmDir \/r "\$PROFILE\\\.local\\share\\\$\{BUNDLEID\}"/);
  assert.match(hooks, /RmDir \/r "\$LOCALAPPDATA\\\$\{BUNDLEID\}"/);
  assert.match(hooks, /RmDir \/r "\$APPDATA\\\$\{BUNDLEID\}"/);
  assert.match(hooks, /ReadEnvStr \$0 "XDG_DATA_HOME"/);
  assert.match(hooks, /RmDir \/r "\$0\\\$\{BUNDLEID\}"/);
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

test("streamed action writes handle client disconnect rejections", async () => {
  const request = Readable.from([JSON.stringify({
    action: { title: "Chatty action", command: { executable: "tool", arguments: [] } },
    context: { fieldValues: {}, checkedOptions: {}, configValues: {}, rowValues: {}, bundleRootPath: "/bundle" },
  })]);
  request.method = "POST";
  request.url = "/api/run/stream";
  request.headers = { host: "localhost" };
  const response = new FailingStreamResponse(2);
  const handler = createRequestHandler({
    maxBodyBytes: 100_000,
    bundleRoot: "/bundle",
    runProcess: async (_executable, _args, options) => {
      options.onStdout("chunk\n");
      return { exitCode: 0, stdout: "", stderr: "" };
    },
  });

  await handler(request, response);

  assert.equal(response.writableEnded, true);
  assert.match(response.body, /client disconnected/);
});

test("manifest API includes configured app version", async () => {
  const request = Readable.from([]);
  request.method = "GET";
  request.url = "/api/manifest";
  request.headers = { host: "localhost", "accept-language": "en" };
  const response = new JsonResponse();
  const handler = createRequestHandler({
    appVersion: "1.2.3",
    defaultLocale: "en",
    localizedBundleLoader: {
      load: async (locale, preferredLocales) => ({
        locale,
        preferredLocales,
        manifest: { displayName: "Example", pages: [] },
      }),
    },
  });

  await handler(request, response);

  assert.equal(response.statusCode, 200);
  assert.equal(response.headers["content-type"], "application/json; charset=utf-8");
  assert.deepEqual(JSON.parse(response.body), {
    appVersion: "1.2.3",
    locale: "en",
    preferredLocales: ["en"],
    manifest: { displayName: "Example", pages: [] },
  });
});

test("manifest API omits blank app version", async () => {
  const request = Readable.from([]);
  request.method = "GET";
  request.url = "/api/manifest";
  request.headers = { host: "localhost" };
  const response = new JsonResponse();
  const handler = createRequestHandler({
    appVersion: " ",
    localizedBundleLoader: {
      load: async () => ({
        manifest: { displayName: "Example", pages: [] },
      }),
    },
  });

  await handler(request, response);

  assert.deepEqual(JSON.parse(response.body), {
    manifest: { displayName: "Example", pages: [] },
  });
});

function joinedPath(...parts) {
  return parts.join(process.platform === "win32" ? "\\" : "/");
}

function memoryStorage() {
  const values = new Map();
  return {
    getItem(key) {
      return values.has(key) ? values.get(key) : null;
    },
    setItem(key, value) {
      values.set(key, String(value));
    },
    removeItem(key) {
      values.delete(key);
    },
  };
}

class JsonResponse extends EventEmitter {
  headersSent = false;
  writableEnded = false;
  destroyed = false;
  statusCode = 0;
  headers = {};
  body = "";

  writeHead(statusCode, headers = {}) {
    this.statusCode = statusCode;
    this.headers = headers;
    this.headersSent = true;
  }

  write(chunk) {
    this.body += String(chunk);
    return true;
  }

  end(chunk = "") {
    if (chunk) {
      this.body += String(chunk);
    }
    this.writableEnded = true;
    this.emit("end");
  }
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

class FailingStreamResponse extends EventEmitter {
  headersSent = false;
  writableEnded = false;
  destroyed = false;
  destroyError = undefined;
  body = "";
  #writeCount = 0;
  #failOnWrite;

  constructor(failOnWrite) {
    super();
    this.#failOnWrite = failOnWrite;
  }

  writeHead() {
    this.headersSent = true;
  }

  write(chunk) {
    this.#writeCount += 1;
    this.body += String(chunk);
    this.emit("write", String(chunk));
    if (this.#writeCount === this.#failOnWrite) {
      setImmediate(() => this.emit("error", new Error("client disconnected")));
      return false;
    }
    return true;
  }

  end() {
    this.writableEnded = true;
    this.emit("end");
  }

  destroy(error) {
    this.destroyed = true;
    this.destroyError = error;
    this.emit("close");
  }
}
