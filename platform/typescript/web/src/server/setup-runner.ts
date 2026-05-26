import { setupResultLine, shellQuote } from "../../../shared/rendering.js";
import { setupStepsForPlatform } from "../../../shared/setup-platforms.js";
import { evaluateSetupInstallSizePrecheck } from "./action-runner.js";
import { expandPathTokens, resolveBundlePath } from "./paths.js";
import { platformDisplayCommand } from "./platform-command.js";
import { resolvePlatformScriptPath } from "./platform-scripts.js";
import { errorMessage } from "./errors.js";

export async function setupCommandForStep(step, bundleRoot) {
    const workingDirectory = step.workingDirectory ? resolveBundlePath(step.workingDirectory, bundleRoot) : bundleRoot;
    const environment = Object.fromEntries(Object.entries(step.environment ?? {}).map(([key, value]) => [key, expandSetupValue(value, bundleRoot)]));
    const value = expandSetupValue(step.value, bundleRoot);
    const args = (step.arguments ?? []).map((argument) => expandSetupValue(argument, bundleRoot));
    switch (step.kind) {
        case "pathTool":
            return setupCommand(step, "/usr/bin/env", ["which", value], workingDirectory, environment);
        case "homebrewPackage":
            return setupCommand(step, "/usr/bin/env", ["brew", "list", value], workingDirectory, environment);
        case "bundledScript":
        case "setupScript":
            return setupCommand(step, await resolvePlatformScriptPath(step.value, bundleRoot), args, workingDirectory, environment);
        case "pixiInstall":
            return setupCommand(step, "/usr/bin/env", ["pixi", "install", ...args], workingDirectory, environment);
        case "pixiRun":
            return setupCommand(step, "/usr/bin/env", ["pixi", "run", value, ...args], workingDirectory, environment);
        default:
            throw new Error(`Unsupported setup step kind: ${step.kind}`);
    }
}

export async function runSetupStep(manifest, bundleRoot, runProcess, stepID) {
    const step = setupStepsForPlatform(manifest.setup?.steps ?? []).find((candidate) => candidate.id === stepID);
    if (!step) {
        throw new Error(`Unknown setup step: ${stepID}`);
    }
    return executeSetupStep(step, bundleRoot, runProcess);
}

export async function runSetup(manifest, bundleRoot, runProcess, emit = (_event) => { }, labels = {}) {
    const preflight = await evaluateSetupInstallSizePrecheck(manifest, labels, bundleRoot, runProcess);
    if (preflight?.severity === "warning") {
        const summary = { status: "failed", results: [], error: preflight.message, preflight };
        emit({ type: "complete", result: summary });
        return summary;
    }
    return runStepSet(setupStepsForPlatform(manifest.setup?.steps ?? []), bundleRoot, runProcess, emit);
}
export async function runUninstall(manifest, bundleRoot, runProcess, emit = (_event) => { }) {
    return runStepSet(setupStepsForPlatform(manifest.uninstall?.steps ?? []), bundleRoot, runProcess, emit);
}

async function runStepSet(steps, bundleRoot, runProcess, emit = (_event) => { }) {
    const results: Awaited<ReturnType<typeof executeSetupStep>>[] = [];
    for (const step of steps) {
        const result = await executeSetupStep(step, bundleRoot, runProcess, emit);
        results.push(result);
        if (result.status === "failed" && !step.optional) {
            break;
        }
    }
    const status = setupRunStatus(results);
    const summary = { status, results };
    emit({ type: "complete", result: summary });
    return summary;
}

export async function runInitialSetupIfNeeded(bundle, bundleRoot, runProcess, saveState, emit = (_event) => { }, enabled = true, now = () => new Date().toISOString()) {
    if (!enabled || bundle.bundleState?.setupRun || !setupStepsForPlatform(bundle.manifest.setup?.steps ?? []).length) {
        return null;
    }
    const results: Awaited<ReturnType<typeof executeSetupStep>>[] = [];
    const captureAndEmit = (event) => {
        if (event.type === "step-complete") {
            const index = results.findIndex((result) => result.id === event.result.id);
            if (index >= 0) {
                results[index] = event.result;
            }
            else {
                results.push(event.result);
            }
        }
        emit(event);
    };
    let setupRun;
    try {
        setupRun = { ...(await runSetup(bundle.manifest, bundleRoot, runProcess, captureAndEmit)), completedAt: now() };
    }
    catch (error) {
        setupRun = {
            status: "failed",
            results,
            completedAt: now(),
            error: error instanceof Error ? errorMessage(error) : String(error),
        };
    }
    await saveState({ setupRun });
    bundle.bundleState = { ...(bundle.bundleState ?? {}), setupRun };
    return setupRun;
}

async function executeSetupStep(step, bundleRoot, runProcess, emit = (_event) => { }) {
    const command = await setupCommandForStep(step, bundleRoot);
    const displayedStep = await displaySetupCommand(command);
    emit({ type: "step-start", step: displayedStep });
    const result = await runSetupCommand(displayedStep, bundleRoot, runProcess, emit);
    const setupResult = setupResultForCommand(displayedStep, result);
    emit({ type: "step-complete", result: setupResult });
    return setupResult;
}

async function displaySetupCommand(command) {
    const displayCommand = await platformDisplayCommand(command.executable, command.arguments);
    const renderedCommand = commandLine(displayCommand.executable, displayCommand.args);
    return {
        ...command,
        executable: displayCommand.executable,
        arguments: displayCommand.args,
        command: command.requiresAdmin ? `sudo ${renderedCommand}` : renderedCommand,
    };
}

async function runSetupCommand(command, bundleRoot, runProcess, emit) {
    const env = {
        ...process.env,
        ...command.environment,
        GUI_FOR_CLI_BUNDLE_ROOT: bundleRoot,
        GUI_FOR_CLI_BUNDLE_WORKSPACE: bundleRoot,
    };
    const executionCommand = adminExecutionCommand(command, bundleRoot, env);
    return runProcess(executionCommand.executable, executionCommand.arguments, {
        cwd: executionCommand.cwd,
        env: executionCommand.env,
        onStdout: (text) => emit({ type: "output", id: command.id, stream: "stdout", text }),
        onStderr: (text) => emit({ type: "output", id: command.id, stream: "stderr", text }),
    });
}

function adminExecutionCommand(command, bundleRoot, env) {
    if (!command.requiresAdmin) {
        return {
            executable: command.executable,
            arguments: command.arguments,
            cwd: command.workingDirectory,
            env,
        };
    }
    if (process.platform === "darwin") {
        const elevatedEnv = elevatedCommandEnvironment(command, bundleRoot);
        const shellScript = [
            `cd ${shellQuote(command.workingDirectory)}`,
            commandLine("/usr/bin/env", [
                ...environmentAssignmentArguments(elevatedEnv),
                command.executable,
                ...command.arguments,
            ]),
        ].join(" && ");
        return {
            executable: "/usr/bin/osascript",
            arguments: ["-e", `do shell script ${appleScriptStringLiteral(shellScript)} with administrator privileges`],
            cwd: undefined,
            env,
        };
    }
    if (process.platform === "win32") {
        throw new Error("Admin setup steps are only supported on macOS and POSIX systems.");
    }
    const elevatedEnv = elevatedCommandEnvironment(command, bundleRoot);
    return {
        executable: "/usr/bin/env",
        arguments: [
            "sudo",
            "/usr/bin/env",
            ...environmentAssignmentArguments(elevatedEnv),
            command.executable,
            ...command.arguments,
        ],
        cwd: command.workingDirectory,
        env,
    };
}

function elevatedCommandEnvironment(command, bundleRoot) {
    return {
        PATH: process.env.PATH ?? "/usr/bin:/bin:/usr/sbin:/sbin",
        ...command.environment,
        GUI_FOR_CLI_BUNDLE_ROOT: bundleRoot,
        GUI_FOR_CLI_BUNDLE_WORKSPACE: bundleRoot,
    };
}

function environmentAssignmentArguments(env) {
    return Object.entries(env)
        .filter(([key, value]) => value != null && /^[A-Za-z_][A-Za-z0-9_]*$/.test(key))
        .map(([key, value]) => `${key}=${String(value)}`);
}

function appleScriptStringLiteral(value) {
    return `"${value.replaceAll("\\", "\\\\").replaceAll("\"", "\\\"")}"`;
}

function setupResultForCommand(command, result) {
    const status = result.exitCode === 0 ? "ok" : command.optional ? "warning" : "failed";
    return {
        ...result,
        id: command.id,
        label: command.label,
        kind: command.kind,
        command: command.command,
        status,
    };
}

function setupCommand(step, executable, args, workingDirectory, environment) {
    return {
        id: step.id,
        label: step.label,
        kind: step.kind,
        executable,
        arguments: args,
        environment,
        workingDirectory,
        optional: Boolean(step.optional),
        requiresAdmin: step.requiresAdmin === true,
        command: commandLine(executable, args),
    };
}

function expandSetupValue(value, bundleRoot) {
    return expandPathTokens(value, bundleRoot);
}

export function setupEventLine(event) {
    if (event.type === "step-complete") {
        return setupResultLine(event.result);
    }
    return "";
}

function setupRunStatus(results) {
    if (results.some((result) => result.status === "failed")) {
        return "failed";
    }
    return results.some((result) => result.status === "warning") ? "warning" : "ok";
}

function commandLine(executable, args) {
    return [executable, ...args].map(shellQuote).join(" ");
}
