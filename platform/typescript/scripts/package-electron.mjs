#!/usr/bin/env node
import { cp, lstat, mkdir, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const webuiRoot = path.resolve(scriptDir, "..");
const repoRoot = path.resolve(webuiRoot, "../..");
const cacheRoot = path.join(webuiRoot, ".cache", "electron-package");
const stageRoot = path.join(cacheRoot, "app");
const defaultOut = path.join(repoRoot, "out", "electron");

const args = parseArgs(process.argv.slice(2));
const outDir = path.resolve(repoRoot, args.out ?? defaultOut);
const platform = args.platform ?? electronPlatform(os.platform());
const arch = args.arch ?? electronArch(os.arch());
const bundleRoot = path.resolve(repoRoot, args.bundle ?? path.join("examples", "WGSExtract"));
const appName = args.name ?? "GUI for CLI Electron";

await stageApp();
await runPackager();
await writeManifest();

async function stageApp() {
  await rm(stageRoot, { recursive: true, force: true });
  await rm(outDir, { recursive: true, force: true });
  await mkdir(stageRoot, { recursive: true });

  await writeFile(
    path.join(stageRoot, "package.json"),
    `${JSON.stringify({ name: "gui-for-cli-electron", version: "0.1.0", private: true, main: "main.cjs" }, null, 2)}\n`
  );
  await cp(path.join(webuiRoot, "web", "packagers", "electron", "main.cjs"), path.join(stageRoot, "main.cjs"));
  await cp(path.join(webuiRoot, "dist"), path.join(stageRoot, "platform", "typescript", "dist"), { recursive: true });
  await cp(path.join(webuiRoot, "web", "vendor"), path.join(stageRoot, "platform", "typescript", "web", "vendor"), { recursive: true });
  await cp(path.join(webuiRoot, "web", "index.html"), path.join(stageRoot, "platform", "typescript", "web", "index.html"));
  await cp(path.join(webuiRoot, "web", "styles.css"), path.join(stageRoot, "platform", "typescript", "web", "styles.css"));
  await cp(bundleRoot, path.join(stageRoot, "examples", "WGSExtract"), { recursive: true });
  await cp(path.join(repoRoot, "resources"), path.join(stageRoot, "resources"), { recursive: true });
}

async function runPackager() {
  const binary = process.platform === "win32"
    ? path.join(webuiRoot, "node_modules", ".bin", "electron-packager.cmd")
    : path.join(webuiRoot, "node_modules", ".bin", "electron-packager");
  await run(binary, [
    stageRoot,
    appName,
    `--platform=${platform}`,
    `--arch=${arch}`,
    `--out=${outDir}`,
    "--overwrite",
    "--quiet",
  ]);
}

async function writeManifest() {
  const artifactPath = packagedArtifactPath(outDir, appName, platform, arch);
  const packageRoot = path.join(outDir, `${appName}-${platform}-${arch}`);
  const manifest = {
    appName,
    platform,
    arch,
    packageRoot: path.relative(repoRoot, packageRoot),
    artifactPath: path.relative(repoRoot, artifactPath),
    stageRoot: path.relative(repoRoot, stageRoot),
    sizes: {
      packageBytes: await directorySize(packageRoot),
      artifactBytes: await directorySize(artifactPath),
      stageBytes: await directorySize(stageRoot),
    },
  };
  await writeFile(path.join(outDir, "electron-package.json"), `${JSON.stringify(manifest, null, 2)}\n`);
  console.log(JSON.stringify(manifest, null, 2));
}

function packagedArtifactPath(outRoot, name, targetPlatform, targetArch) {
  const packageRoot = path.join(outRoot, `${name}-${targetPlatform}-${targetArch}`);
  if (targetPlatform === "darwin") {
    return path.join(packageRoot, `${name}.app`);
  }
  if (targetPlatform === "win32") {
    return path.join(packageRoot, `${name}.exe`);
  }
  return packageRoot;
}

function parseArgs(argv) {
  const parsed = {};
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--out") parsed.out = readValue(argv, ++index, arg);
    else if (arg === "--platform") parsed.platform = readValue(argv, ++index, arg);
    else if (arg === "--arch") parsed.arch = readValue(argv, ++index, arg);
    else if (arg === "--bundle") parsed.bundle = readValue(argv, ++index, arg);
    else if (arg === "--name") parsed.name = readValue(argv, ++index, arg);
    else throw new Error(`Unknown option: ${arg}`);
  }
  return parsed;
}

function readValue(argv, index, flag) {
  const value = argv[index];
  if (!value || value.startsWith("--")) {
    throw new Error(`Missing value for ${flag}`);
  }
  return value;
}

function electronPlatform(value) {
  if (value === "darwin" || value === "win32" || value === "linux") {
    return value;
  }
  throw new Error(`Unsupported Electron platform: ${value}`);
}

function electronArch(value) {
  if (value === "x64" || value === "arm64") {
    return value;
  }
  if (value === "x86_64") {
    return "x64";
  }
  throw new Error(`Unsupported Electron architecture: ${value}`);
}

function run(command, commandArgs) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, commandArgs, { stdio: "inherit" });
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

async function directorySize(target) {
  const info = await lstat(target);
  if (info.isSymbolicLink()) {
    return info.size;
  }
  if (!info.isDirectory()) {
    return info.size;
  }
  const entries = await import("node:fs/promises").then(({ readdir }) => readdir(target, { withFileTypes: true }));
  const sizes = await Promise.all(entries.map((entry) => directorySize(path.join(target, entry.name))));
  return sizes.reduce((total, size) => total + size, 0);
}
