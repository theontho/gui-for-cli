import { execFileSync, spawn } from "node:child_process";
import type { ChildProcess } from "node:child_process";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { platform } from "node:os";
import { tmpdir } from "node:os";
import path from "node:path";
import { StringDecoder } from "node:string_decoder";
import type { ProcessRunOptions, RunProcess } from "../../../shared/types.js";
import { platformCommand } from "./platform-command.js";
import { errnoCode, errorMessage } from "./errors.js";

interface ProcessManagerDefaults {
    maxOutputBytes: number;
    maxErrorBytes: number;
}

type ChildLike = { pid?: number | undefined };

export function createProcessManager(defaults: ProcessManagerDefaults) {
    const activeProcessPIDs = new Set<number>();
    const runProcess: RunProcess = async (executable, args, options: ProcessRunOptions) => {
        const baseCommand = await platformCommand(executable, args);
        const elevated = options.requiresAdmin && platform() === "win32"
            ? await windowsAdminCommand(baseCommand, options)
            : undefined;
        const command = elevated?.command ?? baseCommand;
        return new Promise((resolve, reject) => {
            if (options.signal?.aborted) {
                void elevated?.cleanup();
                reject(new Error("Process cancelled."));
                return;
            }
            const child: ChildProcess = spawn(command.executable, command.args, {
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
                void elevated?.cleanup();
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
                void elevated?.cleanup();
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
            if (errnoCode(error) !== "ESRCH") {
                killPID(pid, "SIGTERM");
            }
        }
        killPID(pid, "SIGTERM");
        activeProcessPIDs.delete(pid);
    }
    return { runProcess, terminateAllProcesses, terminateProcessTree };
}

async function windowsAdminCommand(
    command: { executable: string; args: string[] },
    options: ProcessRunOptions,
): Promise<{ command: { executable: string; args: string[] }; cleanup: () => Promise<void> }> {
    const tempRoot = await mkdtemp(path.join(tmpdir(), "gui-for-cli-admin-"));
    const launcherPath = path.join(tempRoot, "launch.ps1");
    const stdoutPath = path.join(tempRoot, "stdout.txt");
    const stderrPath = path.join(tempRoot, "stderr.txt");
    const exitCodePath = path.join(tempRoot, "exit-code.txt");
    await writeFile(launcherPath, windowsAdminLauncherScript(command, options.elevatedEnv ?? {}, stdoutPath, stderrPath, exitCodePath), "utf8");
    const wrapper = windowsAdminWrapperScript(launcherPath, stdoutPath, stderrPath, exitCodePath, options.cwd);
    return {
        command: {
            executable: "powershell.exe",
            args: ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", wrapper],
        },
        cleanup: () => rm(tempRoot, { force: true, recursive: true }),
    };
}

function windowsAdminLauncherScript(
    command: { executable: string; args: string[] },
    environment: Record<string, string | undefined>,
    stdoutPath: string,
    stderrPath: string,
    exitCodePath: string,
): string {
    return [
        "$ErrorActionPreference = 'Stop'",
        ...Object.entries(environment).map(([key, value]) => value == null
            ? `Remove-Item -LiteralPath ${powerShellSingleQuotedString(`Env:\\${key}`)} -ErrorAction SilentlyContinue`
            : `Set-Item -LiteralPath ${powerShellSingleQuotedString(`Env:\\${key}`)} -Value ${powerShellSingleQuotedString(value)}`),
        "try {",
        `  & ${powerShellSingleQuotedString(command.executable)} ${powerShellArraySplat(command.args)} > ${powerShellSingleQuotedString(stdoutPath)} 2> ${powerShellSingleQuotedString(stderrPath)}`,
        "  if ($LASTEXITCODE -is [int]) { $exitCode = $LASTEXITCODE } elseif ($?) { $exitCode = 0 } else { $exitCode = 1 }",
        "} catch {",
        `  $_ | Out-File -FilePath ${powerShellSingleQuotedString(stderrPath)} -Append -Encoding utf8`,
        "  $exitCode = 1",
        "}",
        `Set-Content -LiteralPath ${powerShellSingleQuotedString(exitCodePath)} -Value $exitCode -Encoding ascii`,
        "exit $exitCode",
        "",
    ].join("\n");
}

function windowsAdminWrapperScript(
    launcherPath: string,
    stdoutPath: string,
    stderrPath: string,
    exitCodePath: string,
    workingDirectory: string | undefined,
): string {
    const startProcess = [
        "$process = Start-Process -FilePath 'powershell.exe'",
        `  -ArgumentList ${powerShellArrayLiteral(["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", launcherPath])}`,
        "  -Verb RunAs",
        "  -Wait",
        "  -PassThru",
        ...(workingDirectory ? [`  -WorkingDirectory ${powerShellSingleQuotedString(workingDirectory)}`] : []),
    ].join(" `\n");
    return [
        "$ErrorActionPreference = 'Stop'",
        "try {",
        `  ${startProcess}`,
        "} catch {",
        `  $_ | Out-File -FilePath ${powerShellSingleQuotedString(stderrPath)} -Append -Encoding utf8`,
        "  exit 1",
        "}",
        `if (Test-Path -LiteralPath ${powerShellSingleQuotedString(stdoutPath)}) { [Console]::Out.Write([IO.File]::ReadAllText(${powerShellSingleQuotedString(stdoutPath)})) }`,
        `if (Test-Path -LiteralPath ${powerShellSingleQuotedString(stderrPath)}) { [Console]::Error.Write([IO.File]::ReadAllText(${powerShellSingleQuotedString(stderrPath)})) }`,
        `$exitCode = if (Test-Path -LiteralPath ${powerShellSingleQuotedString(exitCodePath)}) { [int]([IO.File]::ReadAllText(${powerShellSingleQuotedString(exitCodePath)}).Trim()) } else { $process.ExitCode }`,
        "exit $exitCode",
    ].join("\n");
}

function powerShellArraySplat(values: string[]) {
    return values.length > 0 ? `@(${values.map(powerShellSingleQuotedString).join(", ")})` : "@()";
}

function powerShellArrayLiteral(values: string[]) {
    return `@(${values.map(powerShellSingleQuotedString).join(", ")})`;
}

function powerShellSingleQuotedString(value: string) {
    return `'${String(value).replaceAll("'", "''")}'`;
}
function killPID(pid: number, signal: NodeJS.Signals) {
    try {
        process.kill(pid, signal);
    }
    catch (error) {
        if (errnoCode(error) !== "ESRCH") {
            console.warn(`Could not send ${signal} to ${pid}: ${errorMessage(error)}`);
        }
    }
}
function descendantPIDs(rootPID: number): number[] {
    let rows: Array<[number, number]> = [];
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
            .flatMap((line): Array<[number, number]> => {
                const [pid, ppid] = line.trim().split(/\s+/).map(Number);
                return typeof pid === "number" && typeof ppid === "number" && Number.isInteger(pid) && Number.isInteger(ppid)
                    ? [[pid, ppid]]
                    : [];
            });
    }
    catch (error) {
        console.warn(`Could not inspect process tree for ${rootPID}: ${errorMessage(error)}`);
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
