import { execFile } from "node:child_process";
import * as fsPromises from "node:fs/promises";
import { homedir, platform } from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import { displayCommand, evaluateNumeric, interpolate, renderedCommand } from "../shared/rendering.js";
import { decodeXML, environmentKey, formatGB, resolveBundlePath, resolveUserPath } from "./paths.js";
const dataSourceTimeoutMs = 15_000;
const execFileAsync = promisify(execFile);
const { stat } = fsPromises;
export async function runAction(action, context, signal, bundleRoot, runProcess) {
    if (!action?.command) {
        throw new Error("Missing action command.");
    }
    const resolvedContext = await contextWithFileState(context, bundleRoot);
    const rendered = renderedCommand(action.command, resolvedContext);
    const startedAt = new Date().toISOString();
    const result = await runProcess(rendered.executable, rendered.arguments, {
        cwd: bundleRoot,
        env: { ...process.env, GUI_FOR_CLI_BUNDLE_ROOT: bundleRoot, GUI_FOR_CLI_BUNDLE_WORKSPACE: bundleRoot },
        signal,
    });
    return {
        ...result,
        startedAt,
        finishedAt: new Date().toISOString(),
        command: displayCommand(action.command, resolvedContext),
    };
}
export async function runDataSource(dataSource, context, bundleRoot, runProcess) {
    if (!dataSource?.path) {
        throw new Error("Missing data source path.");
    }
    const executable = resolveBundlePath(dataSource.path, bundleRoot);
    const workingDirectory = dataSource.workingDirectory ? resolveBundlePath(dataSource.workingDirectory, bundleRoot) : bundleRoot;
    const resolvedContext = await contextWithFileState(context, bundleRoot);
    const args = (dataSource.arguments ?? []).map((argument) => interpolate(argument, resolvedContext));
    const env = {
        ...process.env,
        GUI_FOR_CLI_BUNDLE_ROOT: bundleRoot,
        GUI_FOR_CLI_BUNDLE_WORKSPACE: bundleRoot,
        GUI_FOR_CLI_DATA_SOURCE: "1",
    };
    for (const [key, value] of Object.entries(context.fieldValues ?? {})) {
        env[`GUI_FOR_CLI_FIELD_${environmentKey(key)}`] = value;
    }
    for (const [key, value] of Object.entries(context.configValues ?? {})) {
        env[`GUI_FOR_CLI_CONFIG_${environmentKey(key)}`] = value;
    }
    for (const [key, value] of Object.entries(dataSource.environment ?? {})) {
        env[key] = interpolate(value, resolvedContext);
    }
    const result = await runProcess(executable, args, { cwd: workingDirectory, env, timeoutMs: dataSourceTimeoutMs });
    if (result.exitCode !== 0) {
        throw new Error(`Data source ${dataSource.path} exited ${result.exitCode}: ${result.stderr || "no stderr"}`);
    }
    try {
        return JSON.parse(result.stdout || "{}");
    }
    catch (error) {
        throw new Error(`Data source ${dataSource.path} did not print valid JSON: ${error.message}`);
    }
}
export async function contextWithFileState(context, bundleRoot) {
    return { ...context, fileStateValues: await fileStateValues(context, bundleRoot) };
}
export async function fileStateValues(context, bundleRoot) {
    const values = {};
    const sourceValues = {
        ...(context.fieldValues ?? {}),
        ...(context.configValues ?? {}),
        ...(context.rowValues ?? {}),
    };
    for (const [id, rawPath] of Object.entries(sourceValues)) {
        Object.assign(values, await fileStateForPath(id, rawPath, bundleRoot));
    }
    return values;
}
async function fileStateForPath(id, rawPath, bundleRoot) {
    const pathText = String(rawPath ?? "").trim();
    const values = {
        [`${id}.pathExtension`]: "",
        [`${id}.isIndexed`]: "false",
        [`${id}.isSorted`]: "false",
        [`${id}.exists`]: "false",
        [`${id}.fileSize`]: "",
        [`${id}.fileSizeGB`]: "",
        [`${id}.parentDir`]: "",
    };
    if (!pathText) {
        return values;
    }
    const resolvedPath = resolveUserPath(pathText, bundleRoot);
    values[`${id}.pathExtension`] = path.extname(resolvedPath).replace(/^\./, "").toLowerCase();
    values[`${id}.parentDir`] = path.dirname(resolvedPath);
    values[`${id}.isIndexed`] = String(await isIndexedAlignment(resolvedPath));
    values[`${id}.isSorted`] = String(await isSortedAlignment(resolvedPath));
    try {
        const info = await stat(resolvedPath);
        values[`${id}.exists`] = "true";
        if (info.isFile()) {
            values[`${id}.fileSize`] = String(info.size);
            values[`${id}.fileSizeGB`] = (Number(info.size) / 1_073_741_824).toFixed(2);
        }
    }
    catch (error) {
        if (error.code !== "ENOENT" && error.code !== "ENOTDIR") {
            throw error;
        }
    }
    return values;
}
async function isIndexedAlignment(resolvedPath) {
    const parsed = path.parse(resolvedPath);
    const withoutExtension = path.join(parsed.dir, parsed.name);
    const indexPaths = [
        `${resolvedPath}.bai`,
        `${resolvedPath}.crai`,
        `${resolvedPath}.csi`,
        `${withoutExtension}.bai`,
        `${withoutExtension}.crai`,
        `${withoutExtension}.csi`,
    ];
    return (await Promise.all(indexPaths.map((candidate) => pathExists(candidate)))).some(Boolean);
}
async function isSortedAlignment(resolvedPath) {
    if (await isIndexedAlignment(resolvedPath)) {
        return true;
    }
    const filename = path.basename(resolvedPath).toLowerCase();
    return (filename.includes(".sorted.") ||
        filename.includes("_sorted.") ||
        filename.endsWith(".sorted.bam") ||
        filename.endsWith(".sorted.cram") ||
        filename.includes(".sort.") ||
        filename.includes("_sort."));
}
async function pathExists(filePath) {
    try {
        await stat(filePath);
        return true;
    }
    catch (error) {
        if (error.code === "ENOENT" || error.code === "ENOTDIR") {
            return false;
        }
        throw error;
    }
}
export async function evaluatePrecheck(precheck, context, labels, bundleRoot, runProcess) {
    if (!precheck?.diskSpaceGB) {
        return null;
    }
    const interpolated = await interpolatePrecheck(precheck.diskSpaceGB, context, bundleRoot);
    const requiredGB = evaluateNumeric(interpolated);
    if (!Number.isFinite(requiredGB) || requiredGB <= 0) {
        return null;
    }
    const pathExpression = precheck.diskSpacePath || "{{out_dir}}";
    let targetPath = (await interpolatePrecheck(pathExpression, context, bundleRoot)).trim();
    if (!targetPath) {
        targetPath = context.bundleRootPath || homedir();
    }
    const expandedPath = resolveUserPath(targetPath, bundleRoot);
    const availableGB = await volumeAvailableGB(expandedPath, bundleRoot);
    if (!Number.isFinite(availableGB)) {
        return null;
    }
    const severity = availableGB < requiredGB ? "warning" : "info";
    const required = formatGB(requiredGB);
    const available = formatGB(availableGB);
    const pathLabel = await diskPathLabel(expandedPath, bundleRoot, runProcess);
    const title = severity === "warning"
        ? labels.actionPrecheckDiskSpaceTitle || "Not enough free disk space"
        : labels.actionPrecheckDiskSpaceInfoTitle || "Disk space estimate";
    const format = severity === "warning" && precheck.warningMessage
        ? await interpolatePrecheck(precheck.warningMessage, context, bundleRoot)
        : severity === "warning"
            ? labels.actionPrecheckDiskSpaceMessageFormat ||
                "Need %{required} GB free at %{path}, only %{available} GB available."
            : labels.actionPrecheckDiskSpaceInfoFormat ||
                "Estimated %{required} GB needed at %{path} (%{available} GB free).";
    return {
        severity,
        title,
        message: String(format)
            .replaceAll("%{required}", required)
            .replaceAll("%{available}", available)
            .replaceAll("%{path}", pathLabel),
        requiredGB,
        availableGB,
        path: expandedPath,
        pathLabel,
    };
}
async function interpolatePrecheck(value, context, bundleRoot) {
    let output = "";
    let cursor = 0;
    for (const match of String(value ?? "").matchAll(/\{\{([^}]+)\}\}/g)) {
        output += String(value).slice(cursor, match.index);
        output += (await precheckContextValue(context, match[1].trim(), bundleRoot)) ?? "";
        cursor = match.index + match[0].length;
    }
    output += String(value ?? "").slice(cursor);
    return output;
}
async function precheckContextValue(context, placeholder, bundleRoot) {
    const separator = placeholder.lastIndexOf(".");
    if (separator > 0 && separator < placeholder.length - 1) {
        const fieldID = placeholder.slice(0, separator);
        const property = placeholder.slice(separator + 1);
        const rawPath = context.fieldValues?.[fieldID] ?? context.configValues?.[fieldID];
        if (property === "fileSizeGB" || property === "fileSize") {
            const bytes = await fileSizeBytes(rawPath, bundleRoot);
            if (!Number.isFinite(bytes)) {
                return "";
            }
            return property === "fileSizeGB" ? String(bytes / 1_073_741_824) : String(bytes);
        }
        if (property === "parentDir") {
            return rawPath ? path.dirname(resolveUserPath(rawPath, bundleRoot)) : "";
        }
    }
    return interpolate(`{{${placeholder}}}`, context);
}
async function fileSizeBytes(rawPath, bundleRoot) {
    if (!rawPath) {
        return Number.NaN;
    }
    try {
        const info = await stat(resolveUserPath(rawPath, bundleRoot));
        return info.isFile() ? info.size : Number.NaN;
    }
    catch (error) {
        if (error.code === "ENOENT") {
            return Number.NaN;
        }
        throw error;
    }
}
async function volumeAvailableGB(rawPath, bundleRoot) {
    let probe = resolveUserPath(rawPath, bundleRoot);
    while (probe && probe !== path.dirname(probe)) {
        try {
            const info = typeof fsPromises.statfs === "function"
                ? await fsPromises.statfs(probe)
                : await fallbackStatFS(probe);
            return Number(info.bavail * info.bsize) / 1_073_741_824;
        }
        catch (error) {
            if (error.code !== "ENOENT" && error.code !== "ENOTDIR") {
                throw error;
            }
            probe = path.dirname(probe);
        }
    }
    return Number.NaN;
}
async function fallbackStatFS(probe) {
    if (platform() === "win32") {
        const drive = path.parse(probe).root.replace(/[\\/]$/, "");
        if (!drive) {
            throw new Error(`Could not determine Windows drive for ${probe}.`);
        }
        const command = `(Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='${drive.replace(/'/g, "''")}'").FreeSpace`;
        const { stdout } = await execFileAsync("powershell.exe", ["-NoProfile", "-Command", command], { timeout: 5000 });
        const freeBytes = Number(stdout.trim());
        if (!Number.isFinite(freeBytes)) {
            throw new Error(`Could not read free disk space for ${drive}.`);
        }
        return { bavail: freeBytes, bsize: 1 };
    }
    const { stdout } = await execFileAsync("df", ["-Pk", probe], { timeout: 5000 });
    const line = stdout.trim().split(/\r?\n/)[1];
    const columns = line?.trim().split(/\s+/);
    const availableKB = Number(columns?.[3]);
    if (!Number.isFinite(availableKB)) {
        throw new Error(`Could not parse free disk space from df output for ${probe}.`);
    }
    return { bavail: availableKB, bsize: 1024 };
}
async function diskPathLabel(rawPath, bundleRoot, runProcess) {
    const expanded = resolveUserPath(rawPath, bundleRoot);
    const folderName = path.basename(expanded) || expanded;
    const volumeName = await volumeNameForPath(expanded, bundleRoot, runProcess);
    return volumeName && volumeName !== folderName ? `${folderName} (${volumeName})` : folderName;
}
async function volumeNameForPath(rawPath, bundleRoot, runProcess) {
    const probe = await existingAncestor(rawPath, bundleRoot);
    if (platform() === "win32") {
        const root = path.parse(probe).root;
        return root ? root.replace(/[\\/]$/, "") : undefined;
    }
    if (platform() === "darwin") {
        try {
            const result = await runProcess("/usr/sbin/diskutil", ["info", "-plist", probe], {
                cwd: bundleRoot,
                env: process.env,
                maxOutputBytes: 262_144,
                maxErrorBytes: 16_384,
            });
            if (result.exitCode === 0) {
                const match = /<key>VolumeName<\/key>\s*<string>([^<]+)<\/string>/.exec(result.stdout);
                if (match?.[1]) {
                    return decodeXML(match[1]);
                }
            }
        }
        catch (error) {
            if (error.message !== "Process cancelled.") {
                console.warn(`Could not read volume name for ${probe}: ${error.message}`);
            }
            return undefined;
        }
    }
    return undefined;
}
async function existingAncestor(rawPath, bundleRoot) {
    let probe = resolveUserPath(rawPath, bundleRoot);
    while (probe && probe !== path.dirname(probe)) {
        try {
            await stat(probe);
            return probe;
        }
        catch (error) {
            if (error.code !== "ENOENT" && error.code !== "ENOTDIR") {
                throw error;
            }
            probe = path.dirname(probe);
        }
    }
    return probe || resolveUserPath(rawPath, bundleRoot);
}
