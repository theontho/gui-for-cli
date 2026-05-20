#!/usr/bin/env node
import { cp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { loadBundleMetadata } from "./bundle-metadata.mjs";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const webuiRoot = path.resolve(scriptDir, "..");
const repoRoot = path.resolve(webuiRoot, "../..");
const devConfigPath = path.join(repoRoot, ".devconfig.toml");
const tauriDir = path.join(webuiRoot, "web", "packagers", "tauri");
const tauriScript = path.join(
  webuiRoot,
  "node_modules",
  "@tauri-apps",
  "cli",
  "tauri.js"
);
const generatedConfigPath = path.join(repoRoot, "tmp", "tauri.conf.generated.json");
const generatedBundlePath = path.join(tauriDir, "resources", "EmbeddedBundle");
const generatedBrandingPath = path.join(tauriDir, "resources", "branding.json");
const generatedDebugIconPath = path.join(repoRoot, "tmp", "tauri.debug.icon.png");
const tauriReleaseBundlePath = path.join(tauriDir, "target", "release", "bundle");
const args = process.argv.slice(2);
const devConfig = await loadDevConfig();

if (args.length === 0) {
  throw new Error("Usage: node scripts/run-tauri.mjs <tauri args...>");
}

const branding = await prepareBranding();
try {
  await run(process.execPath, [tauriScript, ...args, "-c", generatedConfigPath], { cwd: tauriDir });
} finally {
  await cleanupGeneratedFiles();
}

async function prepareBranding() {
  const baseConfigPath = path.join(tauriDir, "tauri.conf.json");
  const baseConfig = JSON.parse(await readFile(baseConfigPath, "utf8"));
  const bundlePath = resolveEmbeddedBundlePath();
  const bundleMetadata = await loadBundleMetadata(bundlePath);
  const appName = resolveAppName(bundlePath, baseConfig.productName);
  const appVersion = resolveAppVersion(bundleMetadata, baseConfig.version);

  await mkdir(path.dirname(generatedConfigPath), { recursive: true });
  await rm(generatedBundlePath, { recursive: true, force: true });
  await rm(generatedBrandingPath, { force: true });
  await rm(generatedDebugIconPath, { force: true });
  await rm(tauriReleaseBundlePath, { recursive: true, force: true });
  const bundleConfig = await resolveBundleConfig(baseConfig);

  await copyEmbeddedBundle(bundlePath, generatedBundlePath);
  await writeFile(
    generatedBrandingPath,
    `${JSON.stringify(
      {
        appName,
        appVersion,
        embeddedBundlePath: path.relative(repoRoot, bundlePath),
        embeddedBundleResourcePath: "examples/EmbeddedBundle",
      },
      null,
      2
    )}\n`,
    "utf8"
  );

  const generatedConfig = {
    ...baseConfig,
    productName: appName,
    version: appVersion,
    bundle: bundleConfig,
  };
  await writeFile(generatedConfigPath, `${JSON.stringify(generatedConfig, null, 2)}\n`, "utf8");
  return { appName, appVersion, bundlePath };
}

async function resolveBundleConfig(baseConfig) {
  if (!shouldBadgeDebugDockIcon()) {
    return baseConfig.bundle;
  }

  await run("swift", [
    path.join(repoRoot, "tools", "generate_badged_app_icon.swift"),
    "--base-icon",
    path.join(tauriDir, "icons", "icon.png"),
    "--output-png",
    generatedDebugIconPath,
    "--badge",
    "web",
  ], { cwd: repoRoot });

  return {
    ...baseConfig.bundle,
    icon: [
      generatedDebugIconPath,
      ...baseConfig.bundle.icon.slice(1),
    ],
  };
}

function resolveEmbeddedBundlePath() {
  const configured = process.env.EMBEDDED_BUNDLE_PATH
    || process.env.PACKAGE_BUNDLE_PATH
    || devConfig.packaging?.embedded_bundle_path
    || "examples/WGSExtract";
  return resolveRepoPath(configured);
}

function resolveRepoPath(configuredPath) {
  const resolved = path.resolve(repoRoot, configuredPath);
  const relative = path.relative(repoRoot, resolved);
  if (relative.startsWith("..") || path.isAbsolute(relative)) {
    throw new Error(`Embedded bundle path must stay inside the repository: ${configuredPath}`);
  }
  return resolved;
}

function resolveAppName(bundlePath, defaultName) {
  const explicitAppName = process.env.PACKAGE_APP_NAME
    || process.env.EMBEDDED_APP_NAME
    || devConfig.packaging?.app_name;
  if (explicitAppName) {
    return explicitAppName;
  }
  return path.basename(bundlePath) || defaultName;
}

function resolveAppVersion(bundleMetadata, defaultVersion) {
  return process.env.PACKAGE_APP_VERSION
    || process.env.EMBEDDED_APP_VERSION
    || devConfig.packaging?.app_version
    || bundleMetadata.version
    || defaultVersion;
}

async function cleanupGeneratedFiles() {
  await rm(generatedConfigPath, { force: true });
  await rm(generatedBrandingPath, { force: true });
  await rm(generatedDebugIconPath, { force: true });
  await rm(generatedBundlePath, { recursive: true, force: true });
}

async function copyEmbeddedBundle(sourcePath, destinationPath) {
  await cp(sourcePath, destinationPath, {
    recursive: true,
    filter: (currentSource) => {
      const relative = path.relative(sourcePath, currentSource);
      if (!relative) {
        return true;
      }
      const segments = relative.split(path.sep);
      return !segments.some((segment) => segment === "output" || segment.startsWith("."));
    },
  });
}

function shouldBadgeDebugDockIcon() {
  return process.platform === "darwin" && args[0] === "dev";
}

async function loadDevConfig() {
  try {
    const text = await readFile(devConfigPath, "utf8");
    return parseSimpleToml(text);
  } catch {
    return {};
  }
}

function parseSimpleToml(text) {
  const root = {};
  let section = root;
  for (const rawLine of text.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#")) {
      continue;
    }
    if (line.startsWith("[") && line.endsWith("]")) {
      const parts = line.slice(1, -1).split(".").map((value) => value.trim()).filter(Boolean);
      section = root;
      for (const part of parts) {
        section[part] ??= {};
        section = section[part];
      }
      continue;
    }
    const separator = line.indexOf("=");
    if (separator < 0) {
      continue;
    }
    const key = line.slice(0, separator).trim();
    let value = line.slice(separator + 1).trim();
    if (value.startsWith('"')) {
      section[key] = parseQuotedString(value);
    } else {
      const commentIndex = value.indexOf(" #");
      if (commentIndex >= 0) {
        value = value.slice(0, commentIndex).trim();
      }
      section[key] = value;
    }
  }
  return root;
}

function parseQuotedString(value) {
  let escaped = false;
  for (let index = 1; index < value.length; index += 1) {
    const char = value[index];
    if (escaped) {
      escaped = false;
    } else if (char === "\\") {
      escaped = true;
    } else if (char === '"') {
      return value.slice(1, index).replace(/\\"/g, '"').replace(/\\\\/g, '\\');
    }
  }
  return value;
}

function run(command, commandArgs, options) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, commandArgs, { stdio: "inherit", ...options });
    child.on("error", reject);
    child.on("exit", (code) => {
      if (code === 0) {
        resolve();
      } else {
        reject(new Error(`${command} exited with ${code}`));
      }
    });
  });
}
