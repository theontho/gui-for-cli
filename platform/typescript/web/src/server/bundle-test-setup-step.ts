import { errorMessage } from "./errors.js";
import { setupStepsForPlatform } from "../../../shared/setup-platforms.js";
import { platformDisplayCommand } from "./platform-command.js";
import { runSetup, setupCommandForStep } from "./setup-runner.js";
import { commandLine, makeReport, outputExpectationFailure, setupCommandSummary, setupResultLine } from "./bundle-test-report.js";
import { timeoutRunProcess } from "./bundle-test-timeout.js";

export async function runSetupTestStep(step, index, totalSteps, manifest, workspaceRoot, options) {
    const started = new Date();
    let output = "";
    let exitCode: number | null = null;
    let error: string | null = null;
    const setupSteps = setupStepsForPlatform(manifest.setup?.steps ?? []);
    const appendOutput = (text) => {
        output += text;
        options.emit({ type: "command-output", text });
    };
    const appendMessage = (text) => {
        output += `${text}\n`;
        options.emit({ type: "message", text });
    };

    if (options.dryRun) {
        for (const setupStep of setupSteps) {
            const command = await setupCommandForStep(setupStep, workspaceRoot);
            const display = await platformDisplayCommand(command.executable, command.arguments ?? []);
            appendMessage(`==> ${command.label}\n$ ${commandLine(display.executable, display.args)}`);
        }
        return makeReport(step, index, started, "skipped", {
            command: setupCommandSummary(setupSteps.length),
            output,
        });
    }

    const timeoutState = { timedOut: false };
    const runProcess = timeoutRunProcess(options.runProcess, step.timeoutSeconds, timeoutState);
    try {
        const summary = await runSetup(manifest, workspaceRoot, runProcess, (event) => {
            switch (event.type) {
                case "step-start":
                    appendMessage(`==> ${event.step.label}\n$ ${event.step.command}`);
                    break;
                case "output":
                    appendOutput(event.text ?? "");
                    break;
                case "step-complete":
                    exitCode = event.result.exitCode ?? exitCode;
                    appendMessage(setupResultLine(event.result));
                    break;
                case "complete":
                    if (event.result?.error) {
                        error = event.result.error;
                    }
                    break;
            }
        });
        if (summary.status === "failed") {
            error = error ?? "Setup failed.";
        }
    }
    catch (caughtError) {
        error = errorMessage(caughtError);
    }
    error = error ?? outputExpectationFailure(output, step);
    return makeReport(step, index, started, error ? "failed" : "passed", {
        command: setupCommandSummary(setupSteps.length),
        exitCode,
        timedOut: timeoutState.timedOut,
        output,
        error,
    });
}
