import path from "node:path";
import { setupResultLine, shellQuote } from "../shared/rendering.js";
import { resolveBundlePath } from "./paths.js";

export function setupCommandForStep(step, bundleRoot) {
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
            return setupCommand(step, "/bin/sh", [resolveBundlePath(step.value, bundleRoot), ...args], workingDirectory, environment);
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
    const results = [];
    for (const step of manifest.setup?.steps ?? []) {
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

async function executeSetupStep(step, bundleRoot, runProcess, emit = (_event) => { }) {
    const command = setupCommandForStep(step, bundleRoot);
    emit({ type: "step-start", step: command });
    const env = {
        ...process.env,
        ...command.environment,
        GUI_FOR_CLI_BUNDLE_ROOT: bundleRoot,
        GUI_FOR_CLI_BUNDLE_WORKSPACE: bundleRoot,
    };
    const result = await runProcess(command.executable, command.arguments, {
        cwd: command.workingDirectory,
        env,
    });
    const status = result.exitCode === 0 ? "ok" : command.optional ? "warning" : "failed";
    const setupResult = {
        ...result,
        id: command.id,
        label: command.label,
        kind: command.kind,
        command: command.command,
        status,
    };
    if (result.stdout) {
        emit({ type: "output", id: command.id, stream: "stdout", text: result.stdout });
    }
    if (result.stderr) {
        emit({ type: "output", id: command.id, stream: "stderr", text: result.stderr });
    }
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
