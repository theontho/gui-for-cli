import path from "node:path";
import { setupResultLine, shellQuote } from "../../../shared/rendering.js";
import { resolveBundlePath } from "./paths.js";
import { platformDisplayCommand } from "./platform-command.js";
import { resolvePlatformScriptPath } from "./platform-scripts.js";

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

export async function runSetup(manifest, bundleRoot, runProcess, emit = (_event) => { }) {
    return runStepSet(manifest.setup?.steps ?? [], bundleRoot, runProcess, emit);
}

export async function runUninstall(manifest, bundleRoot, runProcess, emit = (_event) => { }) {
    return runStepSet(manifest.uninstall?.steps ?? [], bundleRoot, runProcess, emit);
}

async function runStepSet(steps, bundleRoot, runProcess, emit = (_event) => { }) {
    const results = [];
    for (const step of steps) {
        const result = await executeSetupStep(step, bundleRoot, runProcess, emit);
        results.push(result);
        if (result.status === "failed" && !step.optional) {
            break;
        }
    }
    const status = results.some((result) => result.status === "failed") ? "failed" : "ok";
    const summary = { status, results };
    emit({ type: "complete", result: summary });
    return summary;
}

export async function runInitialSetupIfNeeded(bundle, bundleRoot, runProcess, saveState, emit = (_event) => { }, enabled = true, now = () => new Date().toISOString()) {
    if (!enabled || bundle.bundleState?.setupRun || !(bundle.manifest.setup?.steps ?? []).length) {
        return null;
    }
    const results = [];
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
            error: error instanceof Error ? error.message : String(error),
        };
    }
    await saveState({ setupRun });
    bundle.bundleState = { ...(bundle.bundleState ?? {}), setupRun };
    return setupRun;
}

async function executeSetupStep(step, bundleRoot, runProcess, emit = (_event) => { }) {
    const command = await setupCommandForStep(step, bundleRoot);
    const displayCommand = await platformDisplayCommand(command.executable, command.arguments);
    const displayedStep = {
        ...command,
        command: [displayCommand.executable, ...displayCommand.args].map(shellQuote).join(" "),
    };
    emit({ type: "step-start", step: displayedStep });
    const env = {
        ...process.env,
        ...command.environment,
        GUI_FOR_CLI_BUNDLE_ROOT: bundleRoot,
        GUI_FOR_CLI_BUNDLE_WORKSPACE: bundleRoot,
    };
    const result = await runProcess(displayCommand.executable, displayCommand.args, {
        cwd: command.workingDirectory,
        env,
        onStdout: (text) => emit({ type: "output", id: command.id, stream: "stdout", text }),
        onStderr: (text) => emit({ type: "output", id: command.id, stream: "stderr", text }),
    });
    const status = result.exitCode === 0 ? "ok" : command.optional ? "warning" : "failed";
    const setupResult = {
        ...result,
        id: command.id,
        label: command.label,
        kind: command.kind,
        command: displayedStep.command,
        status,
    };
    emit({ type: "step-complete", result: setupResult });
    return setupResult;
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
        command: [executable, ...args].map(shellQuote).join(" "),
    };
}

function expandSetupValue(value, bundleRoot) {
    return String(value ?? "")
        .replaceAll("{{bundleRoot}}", bundleRoot)
        .replaceAll("{{bundleWorkspace}}", bundleRoot)
        .replaceAll("{{bundleRootBasename}}", path.basename(bundleRoot));
}

export function setupEventLine(event) {
    if (event.type === "step-complete") {
        return setupResultLine(event.result);
    }
    return "";
}
