#!/usr/bin/env node
/**
 * Runs a bundle's uninstall steps on the app's workspace for it, without the app: the Windows
 * uninstaller calls this so that uninstalling the app also removes what its setup installed (the
 * same steps as /api/uninstall/stream). Prints the steps' output; exits 1 if any step failed.
 *
 * Usage: bundle-uninstall-cli.js --app-support-name <app identifier> <bundle>
 * GUI_FOR_CLI_UNINSTALL_RESULT_FILE, if set, receives the result as JSON (as from the macOS app).
 */
import { existsSync } from "node:fs";
import { writeFile } from "node:fs/promises";
import path from "node:path";
import { loadManifestFromRoot } from "./bundle-loader.js";
import { errorMessage } from "./errors.js";
import { appSupportDirectory, safePathComponent } from "./paths.js";
import { createProcessManager } from "./process-runner.js";
import { runUninstall, type SetupSummary } from "./setup-runner.js";

function bundleWorkspacePath(bundleID: string | undefined) {
    // Where the app keeps the bundle's workspace (prepareBundleWorkspace's default).
    return path.join(appSupportDirectory(), "BundleWorkspaces", safePathComponent(bundleID));
}

async function main(argv: string[]): Promise<number> {
    const nameIndex = argv.indexOf("--app-support-name");
    const appSupportName = nameIndex >= 0 ? argv[nameIndex + 1] : undefined;
    const bundle = argv.filter((_, index) => index !== nameIndex && index !== nameIndex + 1)[0];
    if (!appSupportName || !bundle) {
        throw new Error("Usage: bundle-uninstall-cli.js --app-support-name <app identifier> <bundle>");
    }
    process.env.GUI_FOR_CLI_APP_SUPPORT_NAME = appSupportName;
    const manifest = await loadManifestFromRoot(path.resolve(bundle));
    const workspace = bundleWorkspacePath(manifest.id);
    let summary: SetupSummary;
    if (!existsSync(workspace)) {
        console.log(`No workspace at ${workspace}; setup never ran, nothing to remove.`);
        summary = { status: "ok", results: [] };
    }
    else {
        const processManager = createProcessManager({ maxOutputBytes: 1_048_576, maxErrorBytes: 65_536 });
        // The workspace's own copy of the bundle: the scripts setup ran.
        summary = await runUninstall(await loadManifestFromRoot(workspace), workspace, processManager.runProcess, (event) => {
            if (event.type === "step-start") {
                console.log(`==> ${event.step.label ?? event.step.id}`);
            }
            else if (event.type === "output") {
                process.stdout.write(event.text);
            }
            else if (event.type === "step-complete") {
                console.log(`<== ${event.result.id}: ${event.result.status} (exit code ${event.result.exitCode})`);
            }
        });
    }
    await writeResult(summary);
    return summary.status === "ok" ? 0 : 1;
}

async function writeResult(summary: SetupSummary) {
    const resultFile = process.env.GUI_FOR_CLI_UNINSTALL_RESULT_FILE;
    if (resultFile) {
        await writeFile(resultFile, `${JSON.stringify(summary, null, 2)}\n`, "utf8");
    }
}

main(process.argv.slice(2)).then(
    (code) => {
        process.exitCode = code;
    },
    async (error) => {
        console.error(`Uninstall failed: ${errorMessage(error)}`);
        process.exitCode = 1;
        await writeResult({ status: "failed", results: [], error: errorMessage(error) });
    },
);
