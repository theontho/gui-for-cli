import { execFileSync, spawn } from "node:child_process";
import { platform } from "node:os";
import { platformCommand } from "./platform-command.js";
export function createProcessManager(defaults) {
    const activeProcessPIDs = new Set();
    async function runProcess(executable, args, options) {
        const command = await platformCommand(executable, args);
        return new Promise((resolve, reject) => {
            if (options.signal?.aborted) {
                reject(new Error("Process cancelled."));
                return;
            }
            const child = spawn(command.executable, command.args, {
                cwd: options.cwd,
                env: options.env,
                shell: false,
                detached: platform() !== "win32",
                windowsHide: true,
            });
            if (child.pid) {
                activeProcessPIDs.add(child.pid);
            }
            let stdout = "";
            let stderr = "";
            let stdoutTruncated = false;
            let stderrTruncated = false;
            let settled = false;
            const settle = (callback) => {
                if (settled) {
                    return;
                }
                settled = true;
                callback();
            };
            const timeout = options.timeoutMs
                ? setTimeout(() => {
                    terminateProcessTree(child);
                    settle(() => reject(new Error(`Process timed out after ${Math.round((options.timeoutMs ?? 0) / 1000)} seconds.`)));
                }, options.timeoutMs)
                : undefined;
            const abort = () => {
                terminateProcessTree(child);
                settle(() => reject(new Error("Process cancelled.")));
            };
            options.signal?.addEventListener("abort", abort, { once: true });
            child.stdout?.on("data", (chunk) => {
                const next = stdout + chunk.toString("utf8");
                const limit = options.maxOutputBytes ?? defaults.maxOutputBytes;
                stdout = next.slice(0, limit);
                stdoutTruncated ||= next.length > limit;
            });
            child.stderr?.on("data", (chunk) => {
                const next = stderr + chunk.toString("utf8");
                const limit = options.maxErrorBytes ?? defaults.maxErrorBytes;
                stderr = next.slice(0, limit);
                stderrTruncated ||= next.length > limit;
            });
            child.on("error", (error) => {
                if (timeout)
                    clearTimeout(timeout);
                options.signal?.removeEventListener("abort", abort);
                if (child.pid) {
                    activeProcessPIDs.delete(child.pid);
                }
                settle(() => reject(error));
            });
            child.on("close", (exitCode, signal) => {
                if (timeout)
                    clearTimeout(timeout);
                options.signal?.removeEventListener("abort", abort);
                if (child.pid) {
                    activeProcessPIDs.delete(child.pid);
                }
                settle(() => resolve({ exitCode, signal, stdout, stderr, stdoutTruncated, stderrTruncated }));
            });
        });
    }
    function terminateAllProcesses() {
        for (const pid of [...activeProcessPIDs]) {
            terminateProcessTree(pid);
        }
    }
    function terminateProcessTree(childOrPID) {
        const pid = typeof childOrPID === "number" ? childOrPID : childOrPID.pid;
        if (!pid) {
            return;
        }
        const descendants = descendantPIDs(pid);
        for (const descendant of descendants.reverse()) {
            killPID(descendant, "SIGTERM");
        }
        try {
            process.kill(-pid, "SIGTERM");
        }
        catch (error) {
            if (error.code !== "ESRCH") {
                killPID(pid, "SIGTERM");
            }
        }
        killPID(pid, "SIGTERM");
        activeProcessPIDs.delete(pid);
    }
    return { runProcess, terminateAllProcesses, terminateProcessTree };
}
function killPID(pid, signal) {
    try {
        process.kill(pid, signal);
    }
    catch (error) {
        if (error.code !== "ESRCH") {
            console.warn(`Could not send ${signal} to ${pid}: ${error.message}`);
        }
    }
}
function descendantPIDs(rootPID) {
    let rows = [];
    try {
        const output = platform() === "win32"
            ? execFileSync("powershell.exe", [
                "-NoProfile",
                "-Command",
                "Get-CimInstance Win32_Process | ForEach-Object { \"$($_.ProcessId) $($_.ParentProcessId)\" }",
            ], { encoding: "utf8", windowsHide: true })
            : execFileSync("ps", ["-axo", "pid=,ppid="], { encoding: "utf8" });
        rows = output
            .trim()
            .split("\n")
            .map((line) => line.trim().split(/\s+/).map(Number))
            .filter(([pid, ppid]) => Number.isInteger(pid) && Number.isInteger(ppid));
    }
    catch (error) {
        console.warn(`Could not inspect process tree for ${rootPID}: ${error.message}`);
        return [];
    }
    const childrenByParent = new Map();
    for (const [pid, ppid] of rows) {
        const children = childrenByParent.get(ppid) ?? [];
        children.push(pid);
        childrenByParent.set(ppid, children);
    }
    const descendants = [];
    const stack = [...(childrenByParent.get(rootPID) ?? [])];
    while (stack.length) {
        const pid = stack.pop();
        if (pid == null) {
            continue;
        }
        descendants.push(pid);
        stack.push(...(childrenByParent.get(pid) ?? []));
    }
    return descendants;
}
