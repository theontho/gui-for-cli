import { setupResultLine, shellQuote } from "../../../shared/rendering.js";
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
    const step = (manifest.setup?.steps ?? []).find((candidate) => candidate.id === stepID);
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
    return runStepSet(manifest.setup?.steps ?? [], bundleRoot, runProcess, emit);
}

export async function runUninstall(manifest, bundleRoot, runProcess, emit = (_event) => { }) {
    return runStepSet(manifest.uninstall?.steps ?? [], bundleRoot, runProcess, emit);
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
    if (!enabled || bundle.bundleState?.setupRun || !(bundle.manifest.setup?.steps ?? []).length) {
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
    return {
        ...command,
        executable: displayCommand.executable,
        arguments: displayCommand.args,
        command: commandLine(displayCommand.executable, displayCommand.args),
    };
}

async function runSetupCommand(command, bundleRoot, runProcess, emit) {
    const env = {
        ...process.env,
        ...command.environment,
        GUI_FOR_CLI_BUNDLE_ROOT: bundleRoot,
        GUI_FOR_CLI_BUNDLE_WORKSPACE: bundleRoot,
    };
    return runProcess(command.executable, command.arguments, {
        cwd: command.workingDirectory,
        env,
        elevatedEnv: env,
        requiresAdmin: command.requiresAdmin,
        onStdout: (text) => emit({ type: "output", id: command.id, stream: "stdout", text }),
        onStderr: (text) => emit({ type: "output", id: command.id, stream: "stderr", text }),
    });
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
        requiresAdmin: Boolean(step.requiresAdmin),
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
