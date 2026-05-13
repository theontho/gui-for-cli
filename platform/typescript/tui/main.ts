#!/usr/bin/env node
import { existsSync } from "node:fs";
import { stdin, stdout } from "node:process";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createOneShotBundlePreload, loadLocalizedBundle, loadManifestFromRoot } from "../web/src/server/bundle-loader.js";
import { parseArgs } from "../web/src/server/paths.js";
import { createProcessManager } from "../web/src/server/process-runner.js";
import { prepareBundleWorkspace } from "../web/src/server/workspace.js";
import { TUIApp } from "./app.js";
import type { TUIThemePreference } from "./theme.js";

const tuiDir = path.dirname(fileURLToPath(import.meta.url));
const distRoot = path.resolve(tuiDir, "..");
const packageRoot = path.resolve(distRoot, "..");
const repoRoot = path.resolve(packageRoot, "../..");
const args = parseArgs(process.argv.slice(2));
let sourceBundleRoot = "";
let bundleRoot = "";
let runProcess;
let terminateAllProcesses = () => {};
let shouldRunInitialSetup = false;

async function main() {
    if (args.help) {
        printHelp();
        return;
    }
    sourceBundleRoot = resolveBundleRoot(args.bundle);
    const defaultLocale = args.locale;
    const sourceManifest = await loadManifestFromRoot(sourceBundleRoot);
    bundleRoot = await prepareBundleWorkspace(sourceManifest, sourceBundleRoot);
    const processManager = createProcessManager({ maxOutputBytes: 1_048_576, maxErrorBytes: 65_536 });
    runProcess = processManager.runProcess;
    terminateAllProcesses = processManager.terminateAllProcesses;
    shouldRunInitialSetup = Boolean(args.bundle) && args.setup !== "false";
    const localizedBundleLoader = createOneShotBundlePreload(loadBundleForTUI, defaultLocale, Boolean(args.bundle));
    const bundle = await localizedBundleLoader.load(defaultLocale);
    const app = new TUIApp(bundle, { runProcess, terminateAllProcesses, theme: terminalTheme(args.theme), autoRunSetup: shouldRunInitialSetup });
    installShutdownHandlers(app);
    await app.run(args.once === "true" || !stdin.isTTY || !stdout.isTTY);
}

async function loadBundleForTUI(locale?: string) {
    return loadLocalizedBundle(locale, repoRoot, bundleRoot, sourceBundleRoot);
}

function installShutdownHandlers(app: TUIApp) {
    process.once("SIGINT", () => app.close(130));
    process.once("SIGTERM", () => app.close(0));
    process.once("SIGHUP", () => app.close(0));
    process.once("beforeExit", () => terminateAllProcesses());
}

function resolveBundleRoot(value?: string) {
    if (!value) {
        return path.join(repoRoot, "examples", "WGSExtract");
    }
    if (path.isAbsolute(value)) {
        return value;
    }
    const cwdCandidate = path.resolve(value);
    if (existsSync(path.join(cwdCandidate, "manifest.json"))) {
        return cwdCandidate;
    }
    return path.resolve(repoRoot, value);
}

function printHelp() {
    console.log(`GUI for CLI TypeScript TUI

Usage:
  npm --prefix platform/typescript run tui -- [--bundle PATH] [--locale CODE] [--theme auto|dark|light] [--once] [--no-setup]

Options:
  --bundle PATH   Bundle source root. Defaults to examples/WGSExtract.
  --locale CODE   Localization code to load.
  --theme MODE    Terminal color theme: auto, dark, or light. Defaults to auto.
  --once          Render a non-interactive snapshot and exit.
  --no-setup      Do not run initial setup automatically for explicit bundles.
`);
}

function terminalTheme(value?: string): TUIThemePreference {
    if (!value) {
        return "auto";
    }
    if (value === "auto" || value === "dark" || value === "light") {
        return value;
    }
    throw new Error(`Invalid --theme value '${value}'. Expected auto, dark, or light.`);
}

await main();
