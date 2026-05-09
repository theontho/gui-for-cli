import { chmod, cp, mkdir, readdir, rm, stat } from "node:fs/promises";
import path from "node:path";
import { applicationSupportDirectory, safePathComponent } from "./paths.js";
export async function prepareBundleWorkspace(manifest, sourceRoot) {
    const workspaceRoot = path.join(applicationSupportDirectory(), "gui-for-cli", "BundleWorkspaces", safePathComponent(manifest.id));
    await mkdir(workspaceRoot, { recursive: true });
    for (const entry of await readdir(sourceRoot, { withFileTypes: true })) {
        if (entry.name.startsWith("."))
            continue;
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
