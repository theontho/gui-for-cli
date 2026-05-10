import { checkedOptionsForContext, configEditorControls, configValueKey, displayCommand, setupResultLine } from "../shared/rendering.js";
import { api } from "./api.js";
import { boundFieldKey, configSettingBindings, errorMessage, formatLabel, syncSharedField } from "./model.js";
import { scheduleRender } from "./rerender.js";
import { state } from "./state.js";
import { appendTerminal, runningActionControllers, terminalExitStatus, terminalProcessErrorStatus } from "./terminal.js";
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
    const setupID = appendTerminal("command", state.labels.setupTitle ?? "Setup", state.labels.setupRunningTitle ?? "Running setup...");
    state.activeTerminalID = setupID;
    state.setupRun = { status: "running", results: [], currentStepID: null };
    scheduleRender();
    const entry = () => state.terminalEntries.find((candidate) => candidate.id === setupID);
    try {
        const response = await fetch("/api/setup/stream", {
            method: "POST",
            headers: { "content-type": "application/json" },
            body: JSON.stringify({ locale: state.localizationCode }),
        });
        if (!response.ok) {
            throw new Error(response.statusText || `HTTP ${response.status}`);
        }
        if (!response.body) {
            throw new Error("Setup stream did not include a response body.");
        }
        const reader = response.body.pipeThrough(new TextDecoderStream()).getReader();
        let buffer = "";
        while (true) {
            const { value, done } = await reader.read();
            if (done) {
                break;
            }
            buffer += value;
            const lines = buffer.split(/\r?\n/);
            buffer = lines.pop() ?? "";
            for (const line of lines) {
                if (line.trim()) {
                    applySetupEvent(JSON.parse(line), entry());
                }
            }
        }
        if (buffer.trim()) {
            applySetupEvent(JSON.parse(buffer), entry());
        }
    }
    catch (error) {
        const tab = entry();
        if (tab) {
            tab.kind = "error";
            tab.body = [tab.body, errorMessage(error)].filter(Boolean).join("\n");
        }
        state.setupRun = { status: "failed", error: errorMessage(error) };
    }
    scheduleRender();
}
function applySetupEvent(event, tab) {
    if (!tab) {
        return;
    }
    switch (event.type) {
        case "step-start":
            state.setupRun = {
                ...(state.setupRun ?? {}),
                status: "running",
                currentStepID: event.step.id,
            };
            tab.body = [tab.body, `==> ${event.step.label}`, `$ ${event.step.command}\n`].filter(Boolean).join("\n");
            break;
        case "output":
            tab.body += event.text ?? "";
            break;
        case "step-complete":
            state.setupRun = {
                ...(state.setupRun ?? {}),
                status: "running",
                currentStepID: null,
                results: [
                    ...(state.setupRun?.results ?? []).filter((result) => result.id !== event.result.id),
                    event.result,
                ],
            };
            tab.body = [tab.body, setupResultLine(event.result)].filter(Boolean).join("\n");
            break;
        case "complete":
            state.setupRun = { ...event.result, currentStepID: null };
            tab.kind = event.result?.status === "ok" ? "success" : "error";
            break;
    }
    scheduleRender();
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
