#!/usr/bin/env node
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { performance } from "node:perf_hooks";
import {
    createOneShotBundlePreload,
    loadLocalizedBundle,
    loadManifestFromRoot,
} from "../server/bundle-loader.js";
import { saveBundleState } from "../server/config-store.js";
import { parseArgs } from "../server/paths.js";
import { createProcessManager } from "../server/process-runner.js";
import { runInitialSetupIfNeeded } from "../server/setup-runner.js";
import { prepareBundleWorkspace } from "../server/workspace.js";
import { NodeGuiApp, refreshDataSources } from "./app.js";

const bootStartedAt = performance.now();
const nodeguiDir = path.dirname(fileURLToPath(import.meta.url));
const distRoot = path.resolve(nodeguiDir, "..");
const webuiRoot = path.resolve(distRoot, "..");
const repoRoot = path.resolve(webuiRoot, "..");
const args = parseArgs(process.argv.slice(2));

let sourceBundleRoot = "";
let bundleRoot = "";
let runProcess: any;
let terminateAllProcesses = () => {};
let shouldRunInitialSetup = false;

async function main() {
    if (args.help) {
        printHelp();
        return;
    }

    sourceBundleRoot = resolveBundleRoot(args.bundle);
    const sourceManifest = await loadManifestFromRoot(sourceBundleRoot);
    bundleRoot = await prepareBundleWorkspace(sourceManifest, sourceBundleRoot);
    const processManager = createProcessManager({ maxOutputBytes: 1_048_576, maxErrorBytes: 65_536 });
    runProcess = processManager.runProcess;
    terminateAllProcesses = processManager.terminateAllProcesses;
    shouldRunInitialSetup = Boolean(args.bundle) && args.setup !== "false";

    const localizedBundleLoader = createOneShotBundlePreload(loadBundleForNodeGui, args.locale, Boolean(args.bundle));
    if (localizedBundleLoader.preloaded) {
        await localizedBundleLoader.preloaded;
    }
    const bundle = await localizedBundleLoader.load(args.locale);
    const state = createState(bundle);
    await refreshDataSources(state, runProcess);

    if (args.once === "true") {
        printSnapshot(state);
        terminateAllProcesses();
        return;
    }

    const loadStartedAt = performance.now();
    const nodegui = await import("@nodegui/nodegui");
    const app = new NodeGuiApp(nodegui, state, {
        runProcess,
        terminateAllProcesses,
        benchmark: args.benchmark === "true",
        bootStartedAt,
    });
    await app.show({ importedAtMs: loadStartedAt - bootStartedAt });
}

async function loadBundleForNodeGui(locale?: string) {
    const bundle = await loadLocalizedBundle(locale, repoRoot, bundleRoot, sourceBundleRoot);
    const setupRun = await runInitialSetupIfNeeded(
        bundle,
        bundleRoot,
        runProcess,
        (state) => saveBundleState(state, bundleRoot),
        () => {},
        shouldRunInitialSetup,
    );
    return setupRun ? loadLocalizedBundle(locale, repoRoot, bundleRoot, sourceBundleRoot) : bundle;
}

function createState(bundle: Record<string, any>) {
    const selectedPageID = bundle.bundleState?.selectedPageID;
    const pages = bundle.manifest?.pages ?? [];
    const activePageID = pages.some((page) => page.id === selectedPageID) ? selectedPageID : pages[0]?.id ?? "";
    return {
        ...bundle,
        activePageID,
        dataSourcePayloads: new Map(),
        dataSourceErrors: new Map(),
        terminalEntries: [],
        homePath: homedir(),
        setupRun: bundle.bundleState?.setupRun ?? null,
    };
}

function printSnapshot(state: Record<string, any>) {
    const pages = state.manifest?.pages ?? [];
    const controls = pages.flatMap((page) => (page.sections ?? []).flatMap((section) => section.controls ?? []));
    const actions = pages.flatMap((page) => (page.sections ?? []).flatMap((section) => section.actions ?? []));
    console.log(JSON.stringify({
        surface: "nodegui",
        bundle: state.manifest?.displayName ?? "GUI for CLI",
        pages: pages.length,
        controls: controls.length,
        actions: actions.length,
        activePageID: state.activePageID,
    }, null, 2));
}

function resolveBundleRoot(value?: string) {
    if (!value) {
        return path.join(repoRoot, "Examples", "WGSExtract");
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
    console.log(`GUI for CLI NodeGui

Usage:
  npm --prefix WebUI run nodegui -- [--bundle PATH] [--locale CODE] [--benchmark] [--once] [--no-setup]

Options:
  --bundle PATH   Bundle source root. Defaults to Examples/WGSExtract.
  --locale CODE   Localization code to load.
  --benchmark     Print startup timing JSON after showing the native Qt window.
  --once          Load the shared model and print a non-GUI snapshot.
  --no-setup      Do not run initial setup automatically for explicit bundles.
`);
}

process.once("SIGINT", () => terminateAllProcesses());
process.once("SIGTERM", () => terminateAllProcesses());
process.once("beforeExit", () => terminateAllProcesses());

await main();
