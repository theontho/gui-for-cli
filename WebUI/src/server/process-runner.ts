import { execFileSync, spawn } from "node:child_process";
import { platform } from "node:os";
export function createProcessManager(defaults) {
    const activeProcessPIDs = new Set();
    async function runProcess(executable, args, options) {
        return new Promise((resolve, reject) => {
            if (options.signal?.aborted) {
                reject(new Error("Process cancelled."));
                return;
            }
            const target = spawnTarget(executable, args);
            const child = spawn(target.executable, target.args, {
                cwd: options.cwd,
                env: options.env,
                shell: false,
                detached: true,
                windowsHide: true,
                ...target.options,
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
        if (platform() === "win32") {
            try {
                execFileSync("taskkill", ["/PID", String(pid), "/T", "/F"], { stdio: "ignore", windowsHide: true });
            }
            catch (error) {
                console.warn(`Could not terminate process tree for ${pid}: ${error.message}`);
                killPID(pid, "SIGTERM");
            }
            activeProcessPIDs.delete(pid);
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
function spawnTarget(executable, args) {
    if (platform() === "win32" && /\.(cmd|bat)$/i.test(String(executable))) {
        const comspec = process.env.ComSpec || process.env.COMSPEC || "cmd.exe";
        return {
            executable: comspec,
            args: ["/d", "/s", "/c", batchCommandLine(executable, args)],
            options: { windowsVerbatimArguments: true },
        };
    }
    return { executable, args, options: {} };
}
function batchCommandLine(executable, args) {
    return [executable, ...args].map(quoteWindowsBatchArgument).join(" ");
}
function quoteWindowsBatchArgument(value) {
    const text = String(value ?? "");
    if (!text.length) {
        return '""';
    }
    if (!/[\s"&|<>^()%!]/.test(text)) {
        return text;
    }
    return `"${text.replaceAll('"', '""').replaceAll("%", "%%")}"`;
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
    if (platform() === "win32") {
        return [];
    }
    let rows = [];
    try {
        rows = execFileSync("ps", ["-axo", "pid=,ppid="], { encoding: "utf8" })
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
