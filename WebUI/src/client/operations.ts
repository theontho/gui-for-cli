import { checkedOptionsForContext, configEditorControls, configValueKey, displayCommand, setupResultLine } from "../shared/rendering.js";
import { api } from "./api.js";
import { boundFieldKey, configSettingBindings, errorMessage, formatLabel, syncSharedField } from "./model.js";
import { scheduleRender } from "./rerender.js";
import { state } from "./state.js";
import { appendTerminal, runningActionControllers, selectTerminalTab, terminalExitStatus, terminalProcessErrorStatus } from "./terminal.js";
export async function loadInitialConfigs() {
    for (const control of configEditorControls(state.manifest)) {
        if (!control.configFile) {
            continue;
        }
        try {
            const result = await api("/api/config/load", {
                method: "POST",
                body: { control, path: state.configFilePaths[control.id] },
            });
            state.configFilePaths[control.id] = result.path;
            for (const setting of control.settings ?? []) {
                const value = result.values[setting.key] ?? setting.value ?? "";
                state.configValues[configValueKey(control, setting)] = value;
                syncSharedField(setting, value);
            }
            appendTerminal("config", formatLabel(state.labels.configLoadedFormat, { path: result.path }));
        }
        catch (error) {
            appendTerminal("error", formatLabel(state.labels.configLoadErrorFormat, { label: control.label, error: errorMessage(error) }));
        }
    }
}
export async function loadConfig(control) {
    try {
        const result = await api("/api/config/load", {
            method: "POST",
            body: { control, path: state.configFilePaths[control.id] },
        });
        state.configFilePaths[control.id] = result.path;
        for (const setting of control.settings ?? []) {
            const value = result.values[setting.key] ?? setting.value ?? "";
            state.configValues[configValueKey(control, setting)] = value;
            syncSharedField(setting, value);
        }
        appendTerminal("config", formatLabel(state.labels.configLoadedFormat, { path: result.path }));
    }
    catch (error) {
        appendTerminal("error", formatLabel(state.labels.configLoadErrorFormat, { label: control.label, error: errorMessage(error) }));
    }
}
export async function fieldValueChanged(value, control) {
    state.fieldValues[control.id] = value;
    const bindings = configSettingBindings(control.id);
    if (!bindings.length) {
        await persistBundleState();
        return;
    }
    for (const binding of bindings) {
        state.configValues[configValueKey(binding.control, binding.setting)] = value;
        await saveConfig(binding.control);
    }
    await persistBundleState({ removeFieldIDs: [control.id] });
}
export async function checkedOptionsChanged(selectedIDs, control) {
    state.checkedOptions[control.id] = selectedIDs;
    const bindings = configSettingBindings(control.id);
    const value = [...selectedIDs].sort().join(",");
    if (!bindings.length) {
        await persistBundleState();
        return;
    }
    for (const binding of bindings) {
        state.configValues[configValueKey(binding.control, binding.setting)] = value;
        await saveConfig(binding.control);
    }
    await persistBundleState({ removeCheckedIDs: [control.id] });
}
export async function configSettingChanged(value, setting, control) {
    state.configValues[configValueKey(control, setting)] = value;
    const fieldKey = boundFieldKey(setting);
    if (fieldKey) {
        state.fieldValues[fieldKey] = value;
    }
    await saveConfig(control);
    if (fieldKey) {
        await persistBundleState({ removeFieldIDs: [fieldKey] });
    }
}
export async function saveConfig(control, reportSuccess = false) {
    try {
        const values = Object.fromEntries((control.settings ?? []).map((setting) => [setting.key, state.configValues[configValueKey(control, setting)] ?? setting.value ?? ""]));
        const result = await api("/api/config/save", {
            method: "POST",
            body: { control, path: state.configFilePaths[control.id], values },
        });
        state.configFilePaths[control.id] = result.path;
        if (reportSuccess) {
            appendTerminal("config", formatLabel(state.labels.configSavedFormat, { count: result.keyCount, path: result.path }));
        }
    }
    catch (error) {
        appendTerminal("error", formatLabel(state.labels.configSaveErrorFormat, { label: control.label, error: errorMessage(error) }));
        scheduleRender();
        throw error;
    }
}
export async function runAction(action, context) {
    if (action.confirm) {
        state.pendingConfirmation = { action, context, input: "" };
        scheduleRender();
        return;
    }
    const runningID = appendTerminal("command", action.title, displayCommand(action.command, context));
    const controller = new AbortController();
    runningActionControllers.set(runningID, controller);
    scheduleRender();
    try {
        const result = await api("/api/run", { method: "POST", body: { action, context }, signal: controller.signal });
        const runningIndex = state.terminalEntries.findIndex((entry) => entry.id === runningID);
        if (runningIndex < 0) {
            return;
        }
        const status = result.exitCode === 0 ? null : terminalExitStatus(result.exitCode, result.command);
        state.terminalEntries[runningIndex] = {
            id: runningID,
            kind: result.exitCode === 0 ? "success" : status.severity,
            title: action.title,
            command: result.command,
            body: [`$ ${result.command}`, result.stdout, result.stderr, `exit ${result.exitCode}`].filter(Boolean).join("\n"),
            status,
        };
    }
    catch (error) {
        if (error && typeof error === "object" && "name" in error && error.name === "AbortError") {
            return;
        }
        const runningIndex = state.terminalEntries.findIndex((entry) => entry.id === runningID);
        if (runningIndex < 0) {
            return;
        }
        state.terminalEntries[runningIndex] = {
            id: runningID,
            kind: "error",
            title: action.title,
            command: displayCommand(action.command, context),
            body: errorMessage(error),
            status: terminalProcessErrorStatus(displayCommand(action.command, context), errorMessage(error)),
        };
    }
    finally {
        runningActionControllers.delete(runningID);
        state.dataSourcePayloads.clear();
        scheduleRender();
    }
}

export async function runSetup() {
    if (state.setupRun?.status === "running") {
        return;
    }
    const title = state.labels.setupTitle ?? "Setup";
    state.setupRun = { status: "running", results: [] };
    const runningID = appendTerminal("command", title, state.labels.setupRunningTitle ?? "Running setup...");
    const controller = new AbortController();
    runningActionControllers.set(runningID, controller);
    scheduleRender();
    const results = [];
    let status = "ok";
    try {
        await runSetupStream(runningID, results, (nextStatus) => {
            status = nextStatus;
        }, controller.signal);
        const result = { status, results };
        state.setupRun = result;
        finalizeSetupTerminal(runningID, title, result);
    }
    catch (error) {
        if (error && typeof error === "object" && "name" in error && error.name === "AbortError") {
            state.setupRun = { status: "cancelled", results };
            const runningIndex = state.terminalEntries.findIndex((entry) => entry.id === runningID);
            if (runningIndex >= 0) {
                const cancelledTitle = state.labels.setupCancelledTitle ?? "Setup cancelled";
                appendSetupTerminal(runningID, cancelledTitle);
                state.terminalEntries[runningIndex] = {
                    ...state.terminalEntries[runningIndex],
                    kind: "warning",
                    title,
                    command: "setup",
                    status: {
                        severity: "warning",
                        symbol: "▲",
                        title: cancelledTitle,
                        blurb: cancelledTitle,
                        detail: "",
                    },
                };
            }
            return;
        }
        state.setupRun = { status: "failed", results, error: errorMessage(error) };
        const runningIndex = state.terminalEntries.findIndex((entry) => entry.id === runningID);
        if (runningIndex >= 0) {
            appendSetupTerminal(runningID, errorMessage(error));
            state.terminalEntries[runningIndex] = {
                ...state.terminalEntries[runningIndex],
                kind: "error",
                title,
                command: "setup",
                status: terminalProcessErrorStatus("setup", errorMessage(error)),
            };
        }
    }
    finally {
        runningActionControllers.delete(runningID);
        state.dataSourcePayloads.clear();
        scheduleRender();
    }
}

async function runSetupStream(runningID, results, setStatus, signal) {
    const response = await fetch("/api/setup/stream", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({}),
        signal,
    });
    if (!response.ok) {
        throw new Error(response.statusText || `HTTP ${response.status}`);
    }
    if (!response.body) {
        throw new Error("Setup stream response did not include a body.");
    }

    const decoder = new TextDecoder();
    const reader = response.body.getReader();
    let buffer = "";
    while (true) {
        const { done, value } = await reader.read();
        if (done) {
            break;
        }
        buffer += decoder.decode(value, { stream: true });
        buffer = processSetupStreamLines(buffer, runningID, results, setStatus);
    }
    buffer += decoder.decode();
    processSetupStreamLines(`${buffer}\n`, runningID, results, setStatus);
}

function processSetupStreamLines(buffer, runningID, results, setStatus) {
    const lines = buffer.split("\n");
    const remainder = lines.pop() ?? "";
    for (const line of lines) {
        if (!line.trim()) {
            continue;
        }
        handleSetupStreamEvent(JSON.parse(line), runningID, results, setStatus);
    }
    return remainder;
}

function handleSetupStreamEvent(event, runningID, results, setStatus) {
    switch (event.type) {
        case "step-start":
            appendSetupTerminal(runningID, ["", `==> ${event.step.label}`, `$ ${event.step.command}`].join("\n"));
            break;
        case "output":
            appendSetupTerminal(runningID, event.text);
            break;
        case "step-complete": {
            const stepResult = event.result;
            results.push(stepResult);
            appendSetupTerminal(runningID, setupResultLine(stepResult));
            if (stepResult.status === "warning") {
                setStatus("warning");
            }
            if (stepResult.status === "failed" || stepResult.status === "error" || stepResult.status === "cancelled") {
                setStatus(stepResult.status === "cancelled" ? "cancelled" : "failed");
            }
            state.setupRun = { status: "running", results };
            break;
        }
        case "complete":
            setStatus(event.result.status);
            break;
        case "error":
            throw new Error(event.error);
    }
    scheduleRender();
}

function appendSetupTerminal(runningID, body) {
    const runningIndex = state.terminalEntries.findIndex((entry) => entry.id === runningID);
    if (runningIndex < 0) {
        return;
    }
    selectTerminalTab(runningID);
    state.terminalEntries[runningIndex] = {
        ...state.terminalEntries[runningIndex],
        body: [state.terminalEntries[runningIndex].body, body].filter(Boolean).join("\n"),
    };
}

function finalizeSetupTerminal(runningID, title, result) {
    const runningIndex = state.terminalEntries.findIndex((entry) => entry.id === runningID);
    if (runningIndex < 0) {
        return;
    }
    const kind = result.status === "ok" ? "success" : result.status === "warning" ? "warning" : "error";
    state.terminalEntries[runningIndex] = {
        ...state.terminalEntries[runningIndex],
        kind,
        title,
        command: "setup",
        status: setupTerminalStatus(result),
    };
}

function setupTerminalBody(result) {
    return (result.results ?? [])
        .flatMap((step) => [step.command ? `$ ${step.command}` : "", ...setupStepTerminalLines(step)])
        .filter(Boolean)
        .join("\n");
}

function setupStepTerminalLines(step) {
    return [
        step.stdout ?? "",
        step.stderr ?? "",
        step.error ?? "",
        setupResultLine(step),
    ];
}

function setupTerminalStatus(result) {
    const status = result.status === "warning" ? "warning" : result.status === "ok" ? "success" : "error";
    const title = result.status === "ok"
        ? state.labels.setupCompletedTitle ?? "Setup completed"
        : result.status === "warning"
            ? state.labels.setupCompletedWithWarningsTitle ?? "Setup completed with warnings"
            : state.labels.setupFailedTitle ?? "Setup failed";
    return {
        severity: status === "success" ? "info" : status,
        symbol: status === "success" ? "●" : status === "warning" ? "▲" : "✕",
        title,
        blurb: setupResultSummary(result),
        detail: setupTerminalBody(result),
    };
}

function setupResultSummary(result) {
    const lines = (result.results ?? []).map(setupResultLine);
    if (lines.length) {
        return lines.join("\n");
    }
    return state.labels.setupNoStepsTitle ?? "No setup steps are defined.";
}

export function ensureDataSource(key, dataSource, context) {
    if (state.dataSourcePayloads.has(key) || state.dataSourceErrors.has(key) || state.loadingDataSources.has(key)) {
        return;
    }
    state.loadingDataSources.add(key);
    api("/api/datasource", { method: "POST", body: { dataSource, context } })
        .then((payload) => {
        state.dataSourcePayloads.set(key, payload);
        selectDefaultDataSourceOption(key, payload);
        state.dataSourceErrors.delete(key);
    })
        .catch((error) => {
        state.dataSourceErrors.set(key, errorMessage(error));
    })
        .finally(() => {
        state.loadingDataSources.delete(key);
        scheduleRender();
    });
}
export function ensureActionPrecheck(key, precheck, context) {
    if (!key || state.actionPrechecks.has(key) || state.actionPrecheckErrors.has(key) || state.loadingActionPrechecks.has(key)) {
        return state.actionPrechecks.get(key) ?? null;
    }
    state.loadingActionPrechecks.add(key);
    api("/api/precheck", {
        method: "POST",
        body: { precheck, context, labels: state.labels },
    })
        .then((result) => {
        state.actionPrechecks.set(key, result);
        state.actionPrecheckErrors.delete(key);
    })
        .catch((error) => {
        state.actionPrecheckErrors.set(key, errorMessage(error));
    })
        .finally(() => {
        state.loadingActionPrechecks.delete(key);
        scheduleRender();
    });
    return null;
}
export function contextWithFileState(context) {
    const key = fileStateKey(context);
    ensureFileState(key, context);
    const fileStateValues = state.fileStateValues.get(key);
    return fileStateValues ? { ...context, fileStateValues } : context;
}
function ensureFileState(key, context) {
    if (!key || state.fileStateValues.has(key) || state.loadingFileStates.has(key)) {
        return;
    }
    state.loadingFileStates.add(key);
    api("/api/file-state", { method: "POST", body: { context } })
        .then((result) => {
        state.fileStateValues.set(key, result.values ?? {});
    })
        .catch((error) => {
        console.warn(`Could not resolve file state: ${errorMessage(error)}`);
        state.fileStateValues.set(key, {});
    })
        .finally(() => {
        state.loadingFileStates.delete(key);
        scheduleRender();
    });
}
function fileStateKey(context) {
    return JSON.stringify({
        fieldValues: context.fieldValues,
        configValues: context.configValues,
        rowValues: context.rowValues,
        bundleRootPath: context.bundleRootPath,
    });
}
export function actionPrecheckKey(action, context) {
    return JSON.stringify({
        actionID: action.id,
        precheck: action.precheck,
        fieldValues: context.fieldValues,
        checkedOptions: checkedOptionsForContext(context.checkedOptions ?? {}),
        configValues: context.configValues,
        rowValues: context.rowValues,
        bundleRootPath: context.bundleRootPath,
    });
}
export function selectDefaultDataSourceOption(key, payload) {
    const options = payload.options;
    if (!options?.length) {
        return;
    }
    const defaultValue = options.find((option) => option.selected)?.id ?? options[0].id;
    if (key.startsWith("control:")) {
        const controlID = key.slice("control:".length);
        const current = state.fieldValues[controlID]?.trim() ?? "";
        if (!current || !options.some((option) => option.id === current)) {
            state.fieldValues[controlID] = defaultValue;
        }
        return;
    }
    if (key.startsWith("setting:")) {
        const configKey = key.slice("setting:".length);
        const current = state.configValues[configKey]?.trim() ?? "";
        if (!current || !options.some((option) => option.id === current)) {
            state.configValues[configKey] = defaultValue;
        }
    }
}
export async function persistBundleState(options: Record<string, string[]> = {}) {
    const fieldValues = { ...state.fieldValues };
    for (const id of options.removeFieldIDs ?? []) {
        delete fieldValues[id];
    }
    const checkedOptions = Object.fromEntries(Object.entries(state.checkedOptions).map(([key, selected]) => [
        key,
        [...(selected instanceof Set ? selected : new Set(Array.isArray(selected) ? selected : []))].sort(),
    ]));
    for (const id of options.removeCheckedIDs ?? []) {
        delete checkedOptions[id];
    }
    await api("/api/state/save", {
        method: "POST",
        body: {
            state: {
                localizationCode: state.localizationCode,
                configFilePaths: state.configFilePaths,
                fieldValues,
                checkedOptions,
                iconSet: state.iconSet,
                colorTheme: state.colorTheme,
            },
        },
    });
}
