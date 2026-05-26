import { execFileSync, spawn } from "node:child_process";
import { platform } from "node:os";
import { StringDecoder } from "node:string_decoder";
import type { ProcessRunOptions, RunProcess } from "../../../shared/types.js";
import { platformCommand } from "./platform-command.js";

interface ProcessManagerDefaults {
    maxOutputBytes: number;
    maxErrorBytes: number;
}

type ChildLike = { pid?: number };

export function createProcessManager(defaults: ProcessManagerDefaults) {
    const activeProcessPIDs = new Set<number>();
    const runProcess: RunProcess = async (executable, args, options: ProcessRunOptions) => {
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
            child.stdin?.end();
            let stdout = "";
            let stderr = "";
            let stdoutTruncated = false;
            let stderrTruncated = false;
            let settled = false;
            const stdoutDecoder = new StringDecoder("utf8");
            const stderrDecoder = new StringDecoder("utf8");
            const appendStdout = (text: string) => {
                if (!text) {
                    return;
                }
                options.onStdout?.(text);
                const next = stdout + text;
                const limit = options.maxOutputBytes ?? defaults.maxOutputBytes;
                stdout = next.slice(0, limit);
                stdoutTruncated ||= next.length > limit;
            };
            const appendStderr = (text: string) => {
                if (!text) {
                    return;
                }
                options.onStderr?.(text);
                const next = stderr + text;
                const limit = options.maxErrorBytes ?? defaults.maxErrorBytes;
                stderr = next.slice(0, limit);
                stderrTruncated ||= next.length > limit;
            };
            const settle = (callback: () => void) => {
                if (settled) {
                    return;
                }
                settled = true;
                callback();
            };
            const timeout = options.timeoutMs
                ? setTimeout(() => {
                    terminateProcessTree(child);
                    const seconds = Math.max(1, Math.ceil((options.timeoutMs ?? 0) / 1000));
                    settle(() => reject(new Error(`Process timed out after ${seconds} seconds.`)));
                }, options.timeoutMs)
                : undefined;
            const abort = () => {
                terminateProcessTree(child);
                settle(() => reject(new Error("Process cancelled.")));
            };
            options.signal?.addEventListener("abort", abort, { once: true });
            child.stdout?.on("data", (chunk) => {
                appendStdout(stdoutDecoder.write(chunk));
            });
            child.stderr?.on("data", (chunk) => {
                appendStderr(stderrDecoder.write(chunk));
            });
            child.on("error", (error) => {
                if (timeout) {
                    clearTimeout(timeout);
                }
                options.signal?.removeEventListener("abort", abort);
                if (child.pid) {
                    activeProcessPIDs.delete(child.pid);
                }
                settle(() => reject(error));
            });
            child.on("close", (exitCode, signal) => {
                if (timeout) {
                    clearTimeout(timeout);
                }
                options.signal?.removeEventListener("abort", abort);
                if (child.pid) {
                    activeProcessPIDs.delete(child.pid);
                }
                appendStdout(stdoutDecoder.end());
                appendStderr(stderrDecoder.end());
                settle(() => resolve({ exitCode, signal, stdout, stderr, stdoutTruncated, stderrTruncated }));
            });
        });
    };
    function terminateAllProcesses() {
        for (const pid of [...activeProcessPIDs]) {
            terminateProcessTree(pid);
        }
    }
    function terminateProcessTree(childOrPID: ChildLike | number) {
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
function killPID(pid: number, signal: NodeJS.Signals) {
    try {
        process.kill(pid, signal);
    }
    catch (error) {
        if (error.code !== "ESRCH") {
            console.warn(`Could not send ${signal} to ${pid}: ${error.message}`);
        }
    }
}
function descendantPIDs(rootPID: number): number[] {
    let rows: number[][] = [];
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
    const childrenByParent = new Map<number, number[]>();
    for (const [pid, ppid] of rows) {
        const children = childrenByParent.get(ppid) ?? [];
        children.push(pid);
        childrenByParent.set(ppid, children);
    }
    const descendants: number[] = [];
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
