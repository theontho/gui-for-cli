import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import {
    checkedOptionsForContext,
    disabledReason,
    hydrateRows,
    isActionVisible,
    missingPlaceholders,
    renderedCommand,
    rowContext,
    shellQuote,
} from "../../../shared/rendering.js";
import { contextWithFileState, runAction } from "./action-runner.js";
import {
    bootstrapConfigFiles,
    emptyBundleState,
    initialCheckedOptions,
    initialConfigFilePaths,
    initialConfigValues,
    initialFieldValues,
} from "./config-store.js";
import { loadManifestFromRoot } from "./bundle-loader.js";
import { expandPathTokens } from "./paths.js";
import { platformDisplayCommand } from "./platform-command.js";
import { isPlatformScriptReference, resolvePlatformScriptPath } from "./platform-scripts.js";
import { createProcessManager } from "./process-runner.js";
import { runSetup, setupCommandForStep } from "./setup-runner.js";
import { prepareBundleWorkspace } from "./workspace.js";
import type { LooseRecord, RunProcess } from "../../../shared/types.js";

type BundleTestOptions = {
    workspaceURL?: string;
    bootstrapConfig?: boolean;
    dryRun?: boolean;
    runSetup?: boolean;
    progressHandler?: (event: LooseRecord) => void;
    processManager?: { runProcess: RunProcess };
    maxOutputBytes?: number;
    maxErrorBytes?: number;
};

export async function loadBundleTestPlan(planPath) {
    if (!planPath) {
        return { steps: [] };
    }
    let source;
    try {
        source = await readFile(planPath, "utf8");
    }
    catch (error) {
        throw new Error(`Could not read bundle test plan ${planPath}: ${errorMessage(error)}`);
    }
    try {
        return JSON.parse(source);
    }
    catch (error) {
        throw new Error(`Could not parse bundle test plan ${planPath}: ${errorMessage(error)}`);
    }
}

export async function runBundleTest(bundleURL, plan, options: BundleTestOptions = {}) {
    const startedAt = timestamp();
    const sourceRoot = path.resolve(bundleURL);
    const sourceManifest = await loadManifestFromRoot(sourceRoot);
    const workspaceRoot = await prepareBundleWorkspace(sourceManifest, sourceRoot, options.workspaceURL);
    const manifest = await loadManifestFromRoot(workspaceRoot);
    const runtime = await makeRuntime(manifest, workspaceRoot, plan.inputs ?? {}, options.bootstrapConfig !== false);
    const messages = [
        options.workspaceURL
            ? `[bundle] Using test workspace: ${workspaceRoot}`
            : `[bundle] Using bundle workspace: ${workspaceRoot}`,
    ];
    const emit = options.progressHandler ?? (() => { });
    const steps = plan.steps ?? [];

    emit({ type: "message", text: `Bundle test started: ${plan.name ?? manifest.displayName} (${steps.length} steps)` });
    for (const message of messages) {
        emit({ type: "message", text: message });
    }

    const processManager = options.processManager ?? createProcessManager({
        maxOutputBytes: options.maxOutputBytes ?? 1_048_576,
        maxErrorBytes: options.maxErrorBytes ?? 65_536,
    });
    const reports = [];
    let skipRemaining = false;
    for (const [offset, step] of steps.entries()) {
        const index = offset + 1;
        if (skipRemaining) {
            emit({ type: "message", text: `Step ${index}/${steps.length} skipped after a previous failure.` });
            reports.push(skippedReport(step, index, "Skipped after a previous failure."));
            continue;
        }

        emit({ type: "message", text: `Step ${index}/${steps.length} started: ${stepDescription(step)}` });
        const report = await runBundleTestStep(step, index, steps.length, manifest, workspaceRoot, runtime, {
            dryRun: Boolean(options.dryRun),
            emit,
            runProcess: processManager.runProcess,
        });
        reports.push(report);
        emitStepFinished(report, steps.length, emit);
        if (report.status === "failed" && !step.continueOnFailure) {
            skipRemaining = true;
        }
    }

    const summary = {
        total: reports.length,
        passed: reports.filter((report) => report.status === "passed").length,
        failed: reports.filter((report) => report.status === "failed").length,
        skipped: reports.filter((report) => report.status === "skipped").length,
    };
    return {
        planName: plan.name,
        bundleID: manifest.id,
        bundleName: manifest.displayName,
        bundleVersion: manifest.version,
        bundleRoot: workspaceRoot,
        status: summary.failed === 0 ? "passed" : "failed",
        startedAt,
        finishedAt: timestamp(),
        summary,
        messages,
        steps: reports,
    };
}

export async function writeBundleTestReport(report, reportPath) {
    const outputPath = path.resolve(reportPath ?? defaultReportPath());
    await mkdir(path.dirname(outputPath), { recursive: true });
    await writeFile(outputPath, `${JSON.stringify(report, null, 2)}\n`, "utf8");
    return outputPath;
}

async function makeRuntime(manifest, workspaceRoot, planInputs, bootstrapConfig) {
    const bundleState = emptyBundleState();
    const configFilePaths = initialConfigFilePaths(manifest, bundleState);
    if (bootstrapConfig) {
        await bootstrapConfigFiles(manifest, workspaceRoot, configFilePaths);
    }
    const initialConfig = await initialConfigValues(manifest, configFilePaths, workspaceRoot);
    const baseInputs = {
        fieldValues: initialFieldValues(manifest, initialConfig, bundleState),
        configValues: initialConfig,
        checkedOptions: initialCheckedOptions(manifest, initialConfig, bundleState),
    };
    const inputs = mergeInputs(baseInputs, expandInputs(planInputs, workspaceRoot));
    return {
        context: {
            fieldValues: inputs.fieldValues,
            checkedOptions: checkedOptionsForContext(inputs.checkedOptions),
            configValues: inputs.configValues,
            rowValues: {},
            bundleRootPath: workspaceRoot,
            placeholderLabels: placeholderLabels(manifest),
        },
    };
}

async function runBundleTestStep(step, index, totalSteps, manifest, workspaceRoot, runtime, options) {
    switch (step.kind) {
        case "setup":
            return runSetupTestStep(step, index, totalSteps, manifest, workspaceRoot, options);
        case "action":
            return runActionTestStep(step, index, manifest, workspaceRoot, runtime, options);
        default:
            throw new Error(`Unsupported bundle test step kind: ${step.kind}`);
    }
}

async function runSetupTestStep(step, index, totalSteps, manifest, workspaceRoot, options) {
    const started = new Date();
    let output = "";
    let exitCode = null;
    let error = null;
    const setupSteps = manifest.setup?.steps ?? [];
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
            const display = await platformDisplayCommand(command.executable, command.arguments);
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

async function runActionTestStep(step, index, manifest, workspaceRoot, runtime, options) {
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

        let command = null;
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
    const display = await platformDisplayCommand(executable, rendered.arguments);
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
    const candidates = [];
    for (const page of manifest.pages ?? []) {
        if (step.pageID && page.id !== step.pageID) {
            continue;
        }
        for (const section of page.sections ?? []) {
            if (step.sectionID && section.id !== step.sectionID) {
                continue;
            }
            for (const action of section.actions ?? []) {
                candidates.push({ action, context: baseContext });
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
    return {
        id,
        title: String(values.title ?? existing?.title ?? id),
        status: values.status == null ? existing?.status : String(values.status),
        values,
    };
}

function mergeInputs(base, overrides) {
    return {
        fieldValues: { ...(base.fieldValues ?? {}), ...(overrides.fieldValues ?? {}) },
        configValues: { ...(base.configValues ?? {}), ...(overrides.configValues ?? {}) },
        checkedOptions: { ...(base.checkedOptions ?? {}), ...(overrides.checkedOptions ?? {}) },
    };
}

function expandInputs(inputs, workspaceRoot) {
    return {
        fieldValues: expandValueRecord(inputs.fieldValues ?? {}, workspaceRoot),
        configValues: expandValueRecord(inputs.configValues ?? {}, workspaceRoot),
        checkedOptions: Object.fromEntries(Object.entries(inputs.checkedOptions ?? {}).map(([key, values]) => [
            key,
            checkedOptionValues(values, key, workspaceRoot),
        ])),
    };
}

function checkedOptionValues(values, key, workspaceRoot) {
    if (!Array.isArray(values)) {
        throw new Error(`checkedOptions.${key} must be an array.`);
    }
    return values.map((value) => expandPathTokens(String(value), workspaceRoot));
}

function expandValueRecord(values, workspaceRoot) {
    return Object.fromEntries(Object.entries(values).map(([key, value]) => [
        key,
        expandPathTokens(String(value), workspaceRoot),
    ]));
}

function timeoutRunProcess(runProcess, timeoutSeconds, timeoutState = undefined) {
    if (typeof timeoutSeconds !== "number" || !Number.isFinite(timeoutSeconds) || timeoutSeconds <= 0) {
        return runProcess;
    }
    return async (executable, args, options) => {
        try {
            return await runProcess(executable, args, {
                ...options,
                timeoutMs: effectiveTimeoutMs(options.timeoutMs, timeoutSeconds),
            });
        }
        catch (error) {
            if (/timed out/i.test(errorMessage(error))) {
                timeoutState && (timeoutState.timedOut = true);
            }
            throw error;
        }
    };
}

function effectiveTimeoutMs(existingTimeoutMs, stepTimeoutSeconds) {
    const stepTimeoutMs = stepTimeoutSeconds * 1000;
    if (typeof existingTimeoutMs === "number" && Number.isFinite(existingTimeoutMs) && existingTimeoutMs > 0) {
        return Math.min(existingTimeoutMs, stepTimeoutMs);
    }
    return stepTimeoutMs;
}

function outputExpectationFailure(output, step) {
    const failures = [];
    for (const required of step.requiredOutput ?? []) {
        if (!output.includes(required)) {
            failures.push(`Required output was not found: ${required}`);
        }
    }
    for (const forbidden of step.forbiddenOutput ?? []) {
        if (output.includes(forbidden)) {
            failures.push(`Forbidden output was found: ${forbidden}`);
        }
    }
    return failures.length ? failures.join(" ") : null;
}

function makeReport(step, index, started, status, values: LooseRecord = {}) {
    const finished = new Date();
    return {
        index,
        id: step.id,
        kind: step.kind,
        actionID: values.actionID ?? step.actionID,
        status,
        command: values.command,
        exitCode: values.exitCode,
        timedOut: values.timedOut ?? false,
        startedAt: started.toISOString(),
        finishedAt: finished.toISOString(),
        durationSeconds: (finished.getTime() - started.getTime()) / 1000,
        output: values.output ?? "",
        error: values.error ?? null,
    };
}

function skippedReport(step, index, reason) {
    const now = new Date();
    return {
        index,
        id: step.id,
        kind: step.kind,
        actionID: step.actionID,
        status: "skipped",
        startedAt: now.toISOString(),
        finishedAt: now.toISOString(),
        durationSeconds: 0,
        output: "",
        error: reason,
    };
}

function emitStepFinished(report, totalSteps, emit) {
    let message = `Step ${report.index}/${totalSteps} ${report.status} in ${report.durationSeconds.toFixed(1)}s`;
    if (report.exitCode != null) {
        message += ` (exit ${report.exitCode})`;
    }
    if (report.error) {
        message += `: ${report.error}`;
    }
    emit({ type: "message", text: message });
}

function stepDescription(step) {
    if (step.kind === "setup") {
        return step.id ? `setup ${step.id}` : "setup";
    }
    const identifier = step.actionID ?? step.id ?? "action";
    return step.pageID ? `action ${identifier} on ${step.pageID}` : `action ${identifier}`;
}

function setupCommandSummary(count) {
    return `bundle setup (${count} step${count === 1 ? "" : "s"})`;
}

function commandLine(executable, args) {
    return [executable, ...args].map(shellQuote).join(" ");
}

function setupResultLine(result) {
    const status = result.status ?? (result.exitCode === 0 ? "ok" : "failed");
    return `[${status}] ${result.label ?? result.id}`;
}

function placeholderLabels(manifest) {
    const labels = {};
    for (const page of manifest.pages ?? []) {
        for (const section of page.sections ?? []) {
            for (const control of section.controls ?? []) {
                labels[control.id] = control.label;
                for (const setting of control.settings ?? []) {
                    labels[setting.id] = setting.label;
                    labels[setting.key] = setting.label;
                    labels[`${control.id}.${setting.id}`] = setting.label;
                    labels[`${control.id}.${setting.key}`] = setting.label;
                }
            }
        }
    }
    return labels;
}

function defaultReportPath() {
    return path.join(process.cwd(), `bundle-test-report-${new Date().toISOString().replaceAll(":", "-")}.json`);
}

function timestamp() {
    return new Date().toISOString();
}

function errorMessage(error) {
    return error instanceof Error ? error.message : String(error);
}
