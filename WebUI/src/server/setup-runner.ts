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
            });
            const stepResult = {
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
            results.push(stepResult);
            if (stepResult.status === "warning" && status === "ok") {
                status = "warning";
            }
            if (stepResult.status === "failed") {
                status = "failed";
                break;
            }
        } catch (error) {
            const isCancelled = error instanceof Error && error.message === "Process cancelled.";
            const stepResult = {
                id: command.id,
                label: command.label,
                kind: command.kind,
                optional: command.optional,
                command: command.displayCommand,
                exitCode: null,
                stdout: "",
                stderr: "",
                status: isCancelled ? "cancelled" : "error",
                error: error instanceof Error ? error.message : String(error),
            };
            results.push(stepResult);
            status = isCancelled ? "cancelled" : command.optional ? "warning" : "failed";
            if (!command.optional || isCancelled) {
                break;
            }
        }
    }

    return {
        status,
        results,
        output: results.map(setupResultLine).join("\n"),
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
