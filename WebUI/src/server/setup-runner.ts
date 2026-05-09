import { setupResultLine, shellQuote } from "../shared/rendering.js";
import { expandPathTokens, resolveBundlePath } from "./paths.js";

export function setupCommandsForManifest(manifest, bundleRoot) {
    return (manifest?.setup?.steps ?? []).map((step) => setupCommandForStep(step, bundleRoot));
}

export async function runSetup(manifest, bundleRoot, runProcess, signal) {
    const commands = setupCommandsForManifest(manifest, bundleRoot);
    const results = [];
    let status = "ok";

    for (const command of commands) {
        const stepResult = await runSetupCommand(command, bundleRoot, runProcess, signal);
        results.push(stepResult);
        if (stepResult.status === "warning" && status === "ok") {
            status = "warning";
        }
        if (stepResult.status === "failed" || stepResult.status === "error" || stepResult.status === "cancelled") {
            status = stepResult.status === "cancelled" ? "cancelled" : "failed";
            break;
        }
    }

    return {
        status,
        results,
        output: results.map(setupResultLine).join("\n"),
    };
}

export async function runSetupStreaming(manifest, bundleRoot, runProcessStreaming, emit, signal) {
    const commands = setupCommandsForManifest(manifest, bundleRoot);
    const results = [];
    let status = "ok";

    for (const command of commands) {
        emit({ type: "step-start", step: setupCommandEvent(command) });
        const stepResult = await runSetupCommand(command, bundleRoot, runProcessStreaming, signal, (output) => {
            emit({ type: "output", id: command.id, stream: output.stream, text: output.text });
        });
        results.push(stepResult);
        emit({ type: "step-complete", result: stepResult });
        if (stepResult.status === "warning" && status === "ok") {
            status = "warning";
        }
        if (stepResult.status === "failed" || stepResult.status === "error" || stepResult.status === "cancelled") {
            status = stepResult.status === "cancelled" ? "cancelled" : "failed";
            break;
        }
    }

    return {
        status,
        results,
        output: results.map(setupResultLine).join("\n"),
    };
}

export async function runSetupStep(manifest, bundleRoot, runProcess, stepID, signal) {
    const commands = setupCommandsForManifest(manifest, bundleRoot);
    const command = commands.find((candidate) => candidate.id === stepID);
    if (!command) {
        throw new Error(`Unknown setup step: ${stepID}`);
    }
    return runSetupCommand(command, bundleRoot, runProcess, signal);
}

async function runSetupCommand(command, bundleRoot, runProcess, signal, onOutput = undefined) {
    try {
        const result = await runProcess(command.executable, command.arguments, {
            cwd: command.workingDirectory,
            env: {
                ...process.env,
                GUI_FOR_CLI_BUNDLE_ROOT: bundleRoot,
                GUI_FOR_CLI_BUNDLE_WORKSPACE: bundleRoot,
                ...command.environment,
            },
            signal,
        }, onOutput);
        return {
            id: command.id,
            label: command.label,
            kind: command.kind,
            optional: command.optional,
            command: command.displayCommand,
            exitCode: result.exitCode ?? 0,
            stdout: result.stdout ?? "",
            stderr: result.stderr ?? "",
            status: result.exitCode === 0 ? "ok" : command.optional ? "warning" : "failed",
        };
    } catch (error) {
        const isCancelled = error instanceof Error && error.message === "Process cancelled.";
        return {
            id: command.id,
            label: command.label,
            kind: command.kind,
            optional: command.optional,
            command: command.displayCommand,
            exitCode: null,
            stdout: "",
            stderr: "",
            status: isCancelled ? "cancelled" : command.optional ? "warning" : "error",
            error: error instanceof Error ? error.message : String(error),
        };
    }
}

function setupCommandEvent(command) {
    return {
        id: command.id,
        label: command.label,
        kind: command.kind,
        optional: command.optional,
        command: command.displayCommand,
    };
}

function setupCommandForStep(step, bundleRoot) {
    const workingDirectory = step.workingDirectory
        ? resolveBundlePath(step.workingDirectory, bundleRoot)
        : bundleRoot;
    const environment = Object.fromEntries(
        Object.entries(step.environment ?? {}).map(([key, value]) => [
            key,
            expandPathTokens(value, bundleRoot),
        ])
    );
    const value = expandPathTokens(step.value ?? "", bundleRoot);
    const args = (step.arguments ?? []).map((argument) => expandPathTokens(argument, bundleRoot));

    switch (step.kind) {
        case "pathTool":
            return setupCommand(step, "/usr/bin/env", ["which", value], environment, workingDirectory);
        case "homebrewPackage":
            return setupCommand(step, "/usr/bin/env", ["brew", "list", value], environment, workingDirectory);
        case "bundledScript":
        case "setupScript":
            return setupCommand(
                step,
                "/bin/sh",
                [resolveBundlePath(step.value ?? "", bundleRoot), ...args],
                environment,
                workingDirectory
            );
        case "pixiInstall":
            return setupCommand(step, "/usr/bin/env", ["pixi", "install", ...args], environment, workingDirectory);
        case "pixiRun":
            return setupCommand(step, "/usr/bin/env", ["pixi", "run", value, ...args], environment, workingDirectory);
        default:
            throw new Error(`Unsupported setup step kind: ${step.kind}`);
    }
}

function setupCommand(step, executable, args, environment, workingDirectory) {
    return {
        id: step.id,
        label: step.label,
        kind: step.kind,
        executable,
        arguments: args,
        environment,
        workingDirectory,
        optional: Boolean(step.optional),
        displayCommand: [executable, ...args].map(shellQuote).join(" "),
    };
}
