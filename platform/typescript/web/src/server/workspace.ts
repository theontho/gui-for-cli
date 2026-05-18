import { chmod, cp, mkdir, readFile, readdir, rm, stat, writeFile } from "node:fs/promises";
import path from "node:path";
import { appSupportDirectory, relativeTopLevelName, resolveUserPath, safePathComponent } from "./paths.js";

const syncMetadataFileName = ".workspace-sync.json";
const syncMetadataVersion = 1;

export async function prepareBundleWorkspace(manifest, sourceRoot) {
    const workspaceRoot = path.join(appSupportDirectory(), "BundleWorkspaces", safePathComponent(manifest.id));
    await mkdir(workspaceRoot, { recursive: true });
    const sourceEntries = (await readdir(sourceRoot, { withFileTypes: true })).filter((entry) => !entry.name.startsWith("."));
    const sourceNames = new Set(sourceEntries.map((entry) => entry.name));
    const preservedNames = preservedWorkspaceEntryNames(manifest, workspaceRoot);
    const fingerprint = await workspaceSyncFingerprint(manifest, sourceRoot, sourceEntries, preservedNames);
    await removeStaleWorkspaceEntries(workspaceRoot, sourceNames, preservedNames);
    if (await isWorkspaceCurrent(workspaceRoot, fingerprint)) {
        await markDemoScriptsExecutable(workspaceRoot);
        return workspaceRoot;
    }
    await syncSourceEntries(sourceRoot, workspaceRoot, sourceEntries);
    await markDemoScriptsExecutable(workspaceRoot);
    await writeWorkspaceSyncMetadata(workspaceRoot, fingerprint);
    return workspaceRoot;
}

async function syncSourceEntries(sourceRoot, workspaceRoot, sourceEntries) {
    for (const entry of sourceEntries) {
        const source = path.join(sourceRoot, entry.name);
        const destination = path.join(workspaceRoot, entry.name);
        if (entry.name === "runtime" && (await pathExists(destination))) {
            continue;
        }
        await rm(destination, { recursive: true, force: true });
        await cp(source, destination, { recursive: true });
    }
}

async function pathExists(candidate) {
    try {
        await stat(candidate);
        return true;
    }
    catch (error) {
        if (error.code === "ENOENT") {
            return false;
        }
        throw error;
    }
}

async function removeStaleWorkspaceEntries(workspaceRoot, sourceNames, preservedNames) {
    for (const existing of await readdir(workspaceRoot, { withFileTypes: true })) {
        if (existing.name === syncMetadataFileName || preservedNames.has(existing.name) || sourceNames.has(existing.name)) {
            continue;
        }
        await rm(path.join(workspaceRoot, existing.name), { recursive: true, force: true });
    }
}

async function isWorkspaceCurrent(workspaceRoot, fingerprint) {
    try {
        const current = JSON.parse(await readFile(workspaceSyncMetadataPath(workspaceRoot), "utf8"));
        return JSON.stringify(current) === JSON.stringify(fingerprint) && (await copiedSourceEntriesExist(workspaceRoot, fingerprint.entries));
    }
    catch (error) {
        if (error.code === "ENOENT") {
            return false;
        }
        throw error;
    }
}

async function copiedSourceEntriesExist(workspaceRoot, entries) {
    for (const entry of entries) {
        if (entry.kind === "directory") {
            continue;
        }
        if (entry.path === "runtime" || entry.path.startsWith(`runtime${path.sep}`)) {
            continue;
        }
        try {
            const info = await stat(path.join(workspaceRoot, entry.path));
            if (!info.isFile() || info.size !== entry.size) {
                return false;
            }
        }
        catch (error) {
            if (error.code === "ENOENT") {
                return false;
            }
            throw error;
        }
    }
    return true;
}

async function writeWorkspaceSyncMetadata(workspaceRoot, fingerprint) {
    await writeFile(workspaceSyncMetadataPath(workspaceRoot), `${JSON.stringify(fingerprint, null, 2)}\n`, "utf8");
}

function workspaceSyncMetadataPath(workspaceRoot) {
    return path.join(workspaceRoot, syncMetadataFileName);
}

async function workspaceSyncFingerprint(manifest, sourceRoot, sourceEntries, preservedNames) {
    return {
        version: syncMetadataVersion,
        manifestID: manifest.id,
        sourceRoot: path.resolve(sourceRoot),
        preservedNames: [...preservedNames].sort(),
        entries: await sourceEntryFingerprints(sourceRoot, sourceEntries),
    };
}

async function sourceEntryFingerprints(root, entries, prefix = "") {
    const fingerprints = [];
    const visibleEntries = entries
        .filter((entry) => !entry.name.startsWith("."))
        .sort((first, second) => first.name.localeCompare(second.name));
    for (const entry of visibleEntries) {
        const relativePath = prefix ? path.join(prefix, entry.name) : entry.name;
        const filePath = path.join(root, relativePath);
        const info = await stat(filePath);
        if (entry.isDirectory()) {
            fingerprints.push({
                path: relativePath,
                kind: "directory",
                mode: info.mode,
                mtimeMs: Math.trunc(info.mtimeMs),
            });
            fingerprints.push(...(await sourceEntryFingerprints(root, await readdir(filePath, { withFileTypes: true }), relativePath)));
            continue;
        }
        if (entry.isFile()) {
            fingerprints.push({
                path: relativePath,
                kind: "file",
                size: info.size,
                mode: info.mode,
                mtimeMs: Math.trunc(info.mtimeMs),
            });
        }
    }
    return fingerprints;
}

export function preservedWorkspaceEntryNames(manifest, workspaceRoot) {
    const names = new Set(["runtime", "state.json"]);
    for (const control of configEditorControls(manifest)) {
        const rawPath = control.configFile?.path;
        if (!rawPath) {
            continue;
        }
        const topLevelName = relativeTopLevelName(workspaceRoot, resolveUserPath(rawPath, workspaceRoot));
        if (topLevelName) {
            names.add(topLevelName);
        }
    }
    return names;
}
function configEditorControls(manifest) {
    return (manifest.pages ?? []).flatMap((page) => (page.sections ?? []).flatMap((section) => (section.controls ?? []).filter((control) => control.kind === "configEditor")));
}
async function markDemoScriptsExecutable(root) {
    for (const scriptName of [
        "check-preinstalled-pixi.sh",
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
