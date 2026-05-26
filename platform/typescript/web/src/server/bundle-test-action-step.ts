import { checkedOptionsForContext, disabledReason, hydrateRows, isActionVisible, missingPlaceholders, renderedCommand, rowContext, shellQuote } from "../../../shared/rendering.js";
import { contextWithFileState, runAction } from "./action-runner.js";
import { errorMessage } from "./errors.js";
import { platformDisplayCommand } from "./platform-command.js";
import { isPlatformScriptReference, resolvePlatformScriptPath } from "./platform-scripts.js";
import { expandInputs, expandValueRecord } from "./bundle-test-runtime.js";
import { makeReport, outputExpectationFailure } from "./bundle-test-report.js";
import { timeoutRunProcess } from "./bundle-test-timeout.js";

export async function runActionTestStep(step, index, manifest, workspaceRoot, runtime, options) {
    const started = new Date();
    let output = "";
    const timeoutState = { timedOut: false };
    try {
        const resolved = await resolveAction(step, manifest, runtime.context, workspaceRoot);
        if (resolved.missing.length > 0) {
            return makeReport(step, index, started, "failed", {
                error: `Missing input values: ${resolved.missing.join(", ")}`,
            });
        }
        if (!isActionVisible(resolved.action, resolved.context)) {
            return makeReport(step, index, started, "failed", {
                error: "Action is not visible for the provided inputs.",
            });
        }
        const disabled = disabledReason(resolved.action, resolved.context);
        if (disabled) {
            return makeReport(step, index, started, "failed", {
                error: `Action is disabled: ${disabled}`,
            });
        }

        let command: string | null = null;
        if (options.dryRun) {
            const startEvent = await dryRunActionCommand(resolved.action, resolved.context, workspaceRoot);
            command = startEvent.command;
            options.emit({ type: "message", text: `$ ${command}` });
            return makeReport(step, index, started, "skipped", { command, output });
        }

        const result = await runAction(
            resolved.action,
            resolved.context,
            undefined,
            workspaceRoot,
            timeoutRunProcess(options.runProcess, step.timeoutSeconds, timeoutState),
            (event) => {
                switch (event.type) {
                    case "start":
                        command = event.command;
                        options.emit({ type: "message", text: `$ ${event.command}` });
                        break;
                    case "output":
                        output += event.text ?? "";
                        options.emit({ type: "command-output", text: event.text ?? "" });
                        break;
                }
            },
        );
        const expectedExitCodes = step.expectedExitCodes ?? [0];
        let error = expectedExitCodes.includes(result.exitCode)
            ? null
            : `Expected exit code ${expectedExitCodes.join(", ")} but got ${result.exitCode}.`;
        error = error ?? outputExpectationFailure(output, step);
        return makeReport(step, index, started, error ? "failed" : "passed", {
            actionID: step.actionID,
            command: command ?? result.command,
            exitCode: result.exitCode,
            output,
            error,
        });
    }
    catch (error) {
        return makeReport(step, index, started, "failed", {
            actionID: step.actionID,
            output,
            timedOut: timeoutState.timedOut,
            error: errorMessage(error),
        });
    }
}

async function dryRunActionCommand(action, context, workspaceRoot) {
    const rendered = renderedCommand(action.command, await contextWithFileState(context, workspaceRoot));
    const executable = isPlatformScriptReference(rendered.executable, workspaceRoot)
        ? await resolvePlatformScriptPath(rendered.executable, workspaceRoot)
        : rendered.executable;
    const display = await platformDisplayCommand(executable, rendered.arguments ?? []);
    return {
        type: "start",
        command: [display.executable, ...display.args].map(shellQuote).join(" "),
        startedAt: new Date().toISOString(),
    };
}

async function resolveAction(step, manifest, baseContext, workspaceRoot) {
    const candidates = actionCandidates(manifest, step, baseContext, workspaceRoot);
    if (!step.actionID) {
        throw new Error("Action steps must include actionID.");
    }
    const matches = candidates.filter((candidate) => candidate.action.id === step.actionID);
    if (matches.length === 0) {
        throw new Error(`Unknown action: ${step.actionID}`);
    }
    if (matches.length > 1) {
        throw new Error(`Action id is ambiguous, add pageID/sectionID/controlID: ${step.actionID}`);
    }
    const match = matches[0];
    if (!match) {
        throw new Error(`Unknown action: ${step.actionID}`);
    }
    const inputs = expandInputs(step.inputs ?? {}, workspaceRoot);
    const context = {
        ...match.context,
        fieldValues: { ...match.context.fieldValues, ...(inputs.fieldValues ?? {}) },
        configValues: { ...match.context.configValues, ...(inputs.configValues ?? {}) },
        checkedOptions: {
            ...match.context.checkedOptions,
            ...checkedOptionsForContext(inputs.checkedOptions ?? {}),
        },
    };
    const resolvedContext = await contextWithFileState(context, workspaceRoot);
    return {
        action: match.action,
        context: resolvedContext,
        missing: missingPlaceholders(match.action.command, resolvedContext),
    };
}

function actionCandidates(manifest, step, baseContext, workspaceRoot) {
    const candidates: Array<{ action: typeof manifest.pages[number]["sections"][number]["actions"][number]; context: typeof baseContext }> = [];
    for (const page of manifest.pages ?? []) {
        if (step.pageID && page.id !== step.pageID) {
            continue;
        }
        for (const section of page.sections ?? []) {
            if (step.sectionID && section.id !== step.sectionID) {
                continue;
            }
            if (!step.controlID) {
                for (const action of section.actions ?? []) {
                    candidates.push({ action, context: baseContext });
                }
            }
            for (const control of section.controls ?? []) {
                if (step.controlID && control.id !== step.controlID) {
                    continue;
                }
                for (const action of control.rowActions ?? []) {
                    const row = testStepRow(control, step, workspaceRoot);
                    candidates.push({ action, context: rowContext(baseContext, row) });
                }
            }
        }
    }
    return candidates;
}

function testStepRow(control, step, workspaceRoot) {
    const hydrated = hydrateRows(control);
    const existing = step.rowID ? hydrated.find((row) => row.id === step.rowID) : null;
    if (existing && !Object.keys(step.rowValues ?? {}).length) {
        return existing;
    }
    const values = {
        ...(existing?.values ?? {}),
        ...expandValueRecord(step.rowValues ?? {}, workspaceRoot),
    };
    const id = String(step.rowID ?? values.id ?? existing?.id ?? "row");
    const row = {
        id,
        title: String(values.title ?? existing?.title ?? id),
        values,
    };
    const status = values.status == null ? (existing?.status == null ? undefined : String(existing.status)) : String(values.status);
    return status == null ? row : { ...row, status };
}
