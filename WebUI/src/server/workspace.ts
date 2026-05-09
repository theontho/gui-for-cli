import { chmod, cp, mkdir, readdir, rm, stat } from "node:fs/promises";
import path from "node:path";
import { applicationSupportDirectory, safePathComponent } from "./paths.js";
export async function prepareBundleWorkspace(manifest, sourceRoot) {
    const workspaceRoot = path.join(applicationSupportDirectory(), "gui-for-cli", "BundleWorkspaces", safePathComponent(manifest.id));
    await mkdir(workspaceRoot, { recursive: true });
    const sourceEntries = (await readdir(sourceRoot, { withFileTypes: true })).filter((entry) => !entry.name.startsWith("."));
    const sourceNames = new Set(sourceEntries.map((entry) => entry.name));
    for (const existing of await readdir(workspaceRoot, { withFileTypes: true })) {
        if (existing.name === "runtime" || sourceNames.has(existing.name)) {
            continue;
        }
        await rm(path.join(workspaceRoot, existing.name), { recursive: true, force: true });
    }
    for (const entry of sourceEntries) {
        const source = path.join(sourceRoot, entry.name);
        const destination = path.join(workspaceRoot, entry.name);
        if (entry.name === "runtime") {
            try {
                await stat(destination);
                continue;
            }
            catch (error) {
                if (error.code !== "ENOENT")
                    throw error;
            }
        }
        await rm(destination, { recursive: true, force: true });
        await cp(source, destination, { recursive: true });
    }
    await markDemoScriptsExecutable(workspaceRoot);
    return workspaceRoot;
}
async function markDemoScriptsExecutable(root) {
    for (const scriptName of [
        "setup-wgsextract-pixi.sh",
        "bootstrap-wgsextract-config.sh",
        "run-wgsextract.sh",
        "list-reference-genomes.py",
        "delete-reference-genome.sh",
    ]) {
        try {
            await chmod(path.join(root, "scripts", scriptName), 0o755);
        }
        catch (error) {
            if (error.code !== "ENOENT")
                throw error;
        }
    }
}
