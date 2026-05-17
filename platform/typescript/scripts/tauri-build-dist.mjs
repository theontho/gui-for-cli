#!/usr/bin/env node
import os from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const runnerPath = path.join(scriptDir, "run-tauri.mjs");
const defaultBundles = platformBundles(os.platform());
const configuredBundles = (process.env.TAURI_DIST_BUNDLES || process.env.TAURI_BUNDLES || "")
  .split(",")
  .map((value) => value.trim())
  .filter(Boolean);
const bundles = configuredBundles.length > 0 ? configuredBundles : defaultBundles;

if (bundles.length === 0) {
  throw new Error(`No Tauri distribution bundle targets configured for ${os.platform()}`);
}

console.log(`Building Tauri distribution bundles: ${bundles.join(", ")}`);
await run(process.execPath, [runnerPath, "build", "--bundles", bundles.join(","), ...process.argv.slice(2)]);

function platformBundles(platform) {
  switch (platform) {
    case "darwin":
      return ["app", "dmg"];
    case "linux":
      return ["deb", "appimage"];
    case "win32":
      return ["nsis"];
    default:
      return [];
  }
}

function run(command, args) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { stdio: "inherit" });
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
