import { access } from "node:fs/promises";
import { platform } from "node:os";
import path from "node:path";

export async function platformCommand(executable, args = []) {
    if (platform() !== "win32") {
        return posixScriptCommand(executable, args);
    }
    if (executable === "/usr/bin/env") {
        const [tool, ...rest] = args;
        if (tool === "which") {
            const [candidate] = rest;
            if (isPathLike(candidate)) {
                return windowsPathExistsCommand(candidate);
            }
            return { executable: "where.exe", args: rest };
        }
        return { executable: tool, args: rest };
    }
    if (executable === "/bin/sh") {
        const [script, ...rest] = args;
        return windowsScriptCommand(script, rest);
    }
    return windowsScriptCommand(executable, args);
}

function posixScriptCommand(executable, args) {
    const extension = path.extname(executable).toLowerCase();
    if (extension === ".sh") {
        return { executable: "/bin/sh", args: [executable, ...args] };
    }
    if (extension === ".py") {
        return { executable: "python3", args: [executable, ...args] };
    }
    return { executable, args };
}

export async function platformDisplayCommand(executable, args = []) {
    const command = await platformCommand(executable, args);
    return command;
}

async function windowsScriptCommand(executable, args) {
    const extension = path.extname(executable).toLowerCase();
    if (extension === ".sh") {
        const powershellScript = executable.slice(0, -3) + ".ps1";
        if (await exists(powershellScript)) {
            return powershellCommand(powershellScript, args);
        }
    }
    if (extension === ".ps1") {
        return powershellCommand(executable, args);
    }
    if (extension === ".py") {
        return { executable: "python", args: [executable, ...args] };
    }
    return { executable, args };
}

function powershellCommand(script, args) {
    return {
        executable: "powershell.exe",
        args: ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", script, ...args],
    };
}

function windowsPathExistsCommand(candidate) {
    const script = [
        "& { param($candidate)",
        "$extensions = @('', '.exe', '.cmd', '.ps1')",
        "foreach ($extension in $extensions) {",
        "  $probe = [string]::Concat($candidate, $extension)",
        "  if (Test-Path -LiteralPath $probe -PathType Leaf) { Write-Output $probe; exit 0 }",
        "}",
        "exit 1 }",
    ].join("; ");
    return {
        executable: "powershell.exe",
        args: ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", script, candidate],
    };
}

function isPathLike(value) {
    return typeof value === "string" && (path.isAbsolute(value) || /[\\/]/.test(value));
}

async function exists(filePath) {
    try {
        await access(filePath);
        return true;
    }
    catch (error) {
        if (error.code === "ENOENT" || error.code === "ENOTDIR") {
            return false;
        }
        throw error;
    }
}
