import { checkedOptionsForContext, configEditorControls, configValueKey, contextValue, displayCommand, placeholdersIn, setupResultLine } from "../../../shared/rendering.js";
import { api } from "./api.js";
import { boundFieldKey, configSettingBindings, errorMessage, formatLabel, syncSharedField } from "./model.js";
import { scheduleRender } from "./rerender.js";
import { state } from "./state.js";
import { appendTerminal, runningActionControllers, terminalExitStatus, terminalProcessErrorStatus } from "./terminal.js";
import type { ConfigLoadResponse, ConfigSaveResponse, DataSourcePayload, FileStateResponse, PrecheckResult } from "../../../shared/types.js";
export function setupInstallSizeGB() {
    const value = Number(state.manifest?.setup?.initialInstallSizeGB);
    return Number.isFinite(value) && value > 0 ? value : null;
}
export function setupInstallSizePrecheck() {
    const requiredGB = setupInstallSizeGB();
    if (!requiredGB) {
        return null;
    }
    return { diskSpaceGB: String(requiredGB), diskSpacePath: "{{bundleRoot}}" };
}
export function ensureSetupPreflight() {
    const precheck = setupInstallSizePrecheck();
    if (!precheck) {
        state.setupPreflight = null;
        state.setupPreflightError = "";
        state.setupPreflightKey = "";
        return null;
    }
    const key = JSON.stringify({ precheck, bundleRootPath: state.bundleRootPath });
    if (state.setupPreflightKey !== key) {
        state.setupPreflight = null;
        state.setupPreflightError = "";
        state.loadingSetupPreflight = false;
        state.setupPreflightKey = key;
    }
    if (state.setupPreflight || state.setupPreflightError || state.loadingSetupPreflight) {
        return state.setupPreflight;
    }
    state.loadingSetupPreflight = true;
    api<PrecheckResult>("/api/precheck", {
        method: "POST",
        body: { precheck, context: setupPreflightContext(), labels: state.labels },
    })
        .then((result) => {
        state.setupPreflight = result ?? { severity: "info", message: "" };
        state.setupPreflightError = "";
    })
        .catch((error) => {
        state.setupPreflight = null;
        state.setupPreflightError = errorMessage(error);
    })
        .finally(() => {
        state.loadingSetupPreflight = false;
        scheduleRender();
    });
    return null;
}
export async function resolveSetupPreflight() {
    const precheck = setupInstallSizePrecheck();
    if (!precheck) {
        return null;
    }
    try {
        const result = await api<PrecheckResult>("/api/precheck", {
            method: "POST",
            body: { precheck, context: setupPreflightContext(), labels: state.labels },
        });
        state.setupPreflight = result;
        state.setupPreflightError = "";
        state.setupPreflightKey = JSON.stringify({ precheck, bundleRootPath: state.bundleRootPath });
        return result;
    }
    catch (error) {
        state.setupPreflight = null;
        state.setupPreflightError = errorMessage(error);
        return null;
    }
}
function setupPreflightContext() {
    return { fieldValues: {}, checkedOptions: {}, configValues: {}, rowValues: {}, bundleRootPath: state.bundleRootPath };
}
export async function loadInitialConfigs() {
    for (const control of configEditorControls(state.manifest)) {
        if (!control.configFile) {
            continue;
        }
        await loadConfig(control);
    }
}
export async function loadConfig(control) {
    try {
        const result = await loadConfigIntoState(control);
        appendTerminal("config", formatLabel(state.labels.configLoadedFormat, { path: result.path }));
    }
    catch (error) {
        appendTerminal("error", formatLabel(state.labels.configLoadErrorFormat, { label: control.label, error: errorMessage(error) }));
    }
}
export async function fieldValueChanged(value, control) {
    state.fieldValues[control.id] = value;
    await syncBoundConfigSettings(control.id, value, { removeFieldIDs: [control.id] });
}
export async function checkedOptionsChanged(selectedIDs, control) {
    state.checkedOptions[control.id] = selectedIDs;
    const value = [...selectedIDs].sort().join(",");
    await syncBoundConfigSettings(control.id, value, { removeCheckedIDs: [control.id] });
}
async function loadConfigIntoState(control) {
    const result = await api<ConfigLoadResponse>("/api/config/load", {
        method: "POST",
        body: { control, path: state.configFilePaths[control.id] },
    });
    state.configFilePaths[control.id] = result.path;
    for (const setting of control.settings ?? []) {
        const value = result.values[setting.key] ?? setting.value ?? "";
        state.configValues[configValueKey(control, setting)] = value;
        syncSharedField(setting, value);
    }
    return result;
}
async function syncBoundConfigSettings(controlID, value, removePersistedState) {
    const bindings = configSettingBindings(controlID);
    if (!bindings.length) {
        await persistBundleState();
        return;
    }
    for (const binding of bindings) {
        state.configValues[configValueKey(binding.control, binding.setting)] = value;
        await saveConfig(binding.control);
    }
    await persistBundleState(removePersistedState);
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
        const result = await api<ConfigSaveResponse>("/api/config/save", {
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
    const command = displayCommand(action.command, context);
    const runningID = appendTerminal(
        "command",
        action.title,
        actionTerminalBody(action.title, context, action),
        command);
    const controller = new AbortController();
    runningActionControllers.set(runningID, controller);
    scheduleRender();
    try {
        await streamAction(action, context, runningID, controller.signal);
    }
    catch (error) {
        if (error && typeof error === "object" && "name" in error && error.name === "AbortError") {
            return;
        }
        const runningIndex = state.terminalEntries.findIndex((entry) => entry.id === runningID);
        if (runningIndex < 0) {
            return;
        }
        const existing = state.terminalEntries[runningIndex];
        const failedCommand = existing.command || command;
        state.terminalEntries[runningIndex] = {
            ...existing,
            kind: "error",
            title: action.title,
            command: failedCommand,
            body: [
                existing.body || actionExecutionLine(action.title, context, action),
                errorMessage(error),
            ].join("\n"),
            status: terminalProcessErrorStatus(failedCommand, errorMessage(error)),
        };
    }
    finally {
        runningActionControllers.delete(runningID);
        state.dataSourcePayloads.clear();
        scheduleRender();
    }
}

async function streamAction(action, context, runningID, signal) {
    let sawComplete = false;
    const response = await fetch("/api/run/stream", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ action, context }),
        signal,
    });
    if (!response.ok) {
        throw new Error(await responseErrorMessage(response));
    }
    if (!response.body) {
        throw new Error("Action stream did not include a response body.");
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
                const event = parseActionStreamEvent(line);
                if (event?.type === "complete") {
                    sawComplete = true;
                }
                applyActionEvent(event, action, context, runningID);
            }
        }
    }
    if (buffer.trim()) {
        const event = parseActionStreamEvent(buffer);
        if (event?.type === "complete") {
            sawComplete = true;
        }
        applyActionEvent(event, action, context, runningID);
    }
    if (!sawComplete) {
        throw new Error("Action stream ended before completion.");
    }
}
function parseActionStreamEvent(line) {
    try {
        return JSON.parse(line);
    }
    catch {
        const snippet = line.trim().slice(0, 160);
        throw new Error(`Action stream returned invalid JSON event: ${snippet}`);
    }
}

async function responseErrorMessage(response) {
    const text = await response.text();
    if (!text.trim()) {
        return response.statusText || `HTTP ${response.status}`;
    }
    try {
        const body = JSON.parse(text);
        if (body && typeof body === "object" && "error" in body) {
            return String(body.error);
        }
    }
    catch (_error) {
        // Fall through to the raw response text.
    }
    return text;
}

function applyActionEvent(event, action, context, runningID) {
    const runningIndex = state.terminalEntries.findIndex((entry) => entry.id === runningID);
    if (runningIndex < 0) {
        return;
    }
    const tab = state.terminalEntries[runningIndex];
    switch (event.type) {
        case "start":
            tab.command = event.command;
            tab.body = [
                `$ ${event.command}`,
                actionExecutionLine(action.title, context, action),
                "[running] Started.",
            ].join("\n") + "\n";
            break;
        case "output":
            tab.body += event.text ?? "";
            break;
        case "complete": {
            const result = event.result;
            const status = result.exitCode === 0 ? null : terminalExitStatus(result.exitCode, result.command);
            tab.kind = result.exitCode === 0 ? "success" : status.severity;
            tab.command = result.command;
            tab.status = status;
            tab.body = [tab.body, `exit ${result.exitCode}`].filter(Boolean).join("\n");
            break;
        }
        case "error":
            throw new Error(event.error ?? "Action failed.");
    }
    scheduleRender();
}

function actionTerminalBody(title, context, action = null) {
    return [
        actionExecutionLine(title, context, action),
        "[queued] Preparing command environment...",
    ].join("\n");
}
function actionExecutionLine(title, context, action = null) {
    return `[action] Executing action "${title}" with inputs ${actionInputSummary(context, action)}`;
}
function actionInputSummary(context, action = null) {
    const entries = [];
    const seen = new Set();
    if (action?.command) {
        for (const placeholder of actionCommandPlaceholders(action.command)) {
            addPlaceholderInputEntry(entries, seen, placeholder, context);
        }
    }
    else {
        addInputEntries(entries, seen, context.fieldValues, context);
        addInputEntries(entries, seen, context.checkedOptions, context);
        addInputEntries(entries, seen, context.rowValues, context);
        addInputEntries(entries, seen, context.configValues, context);
    }
    return entries.length ? entries.join(", ") : "(none)";
}
function actionCommandPlaceholders(command) {
    return placeholdersIn([
        command.executable,
        ...(command.arguments ?? []),
        ...(command.optionalArguments ?? []).flat(),
    ]).filter((placeholder) => !["bundleRoot", "bundleWorkspace", "home"].includes(placeholder));
}
function addPlaceholderInputEntry(entries, seen, placeholder, context) {
    const key = inputValueKey(placeholder);
    const rawValue = key === placeholder ? contextValue(context, placeholder) : contextValue(context, key);
    const text = String(rawValue ?? "").trim();
    if (!text) {
        return;
    }
    const label = inputLabel(key, context);
    const displayValue = displayInputValue(key, label, text);
    const dedupeKey = `${normalizedInputLabelKey(key)}\u0000${label}\u0000${displayValue}`;
    if (seen.has(dedupeKey)) {
        return;
    }
    seen.add(dedupeKey);
    entries.push(`${label}=${displayValue}`);
}
function addInputEntries(entries, seen, values, context) {
    for (const [key, value] of Object.entries(values ?? {})) {
        const text = String(value ?? "").trim();
        const label = inputLabel(key, context);
        const displayValue = displayInputValue(key, label, text);
        const dedupeKey = `${normalizedInputLabelKey(key)}\u0000${label}\u0000${displayValue}`;
        if (!text || seen.has(dedupeKey)) {
            continue;
        }
        seen.add(dedupeKey);
        entries.push(`${label}=${displayValue}`);
    }
}
function displayInputValue(key, label, value) {
    return isSensitiveInput(key, label) ? "<redacted>" : value;
}
function isSensitiveInput(key, label) {
    const haystack = `${normalizedInputLabelKey(key)} ${label}`.toLowerCase();
    return ["token", "secret", "password", "passphrase", "api_key", "apikey", "api key", "private_key", "private key"].some((marker) => haystack.includes(marker));
}
function inputValueKey(placeholder) {
    const separator = placeholder.lastIndexOf(".");
    if (separator < 0 || separator === placeholder.length - 1) {
        return placeholder;
    }
    const suffix = placeholder.slice(separator + 1);
    if (["exists", "fileSize", "fileSizeGB", "isIndexed", "isSorted", "pathExtension", "parentDir"].includes(suffix)) {
        return placeholder.slice(0, separator);
    }
    return placeholder;
}
function inputLabel(key, context) {
    return context.placeholderLabels?.[normalizedInputLabelKey(key)] ?? prettifyInputKey(key);
}
function normalizedInputLabelKey(key) {
    if (key.startsWith("row.")) {
        return key.slice(4);
    }
    if (key.startsWith("config.")) {
        return key.slice(7);
    }
    const separator = key.lastIndexOf(".");
    if (separator < 0 || separator === key.length - 1) {
        return key;
    }
    const suffix = key.slice(separator + 1);
    return suffix === "fileSize" || suffix === "fileSizeGB" ? key.slice(0, separator) : key;
}
function prettifyInputKey(key) {
    return key
        .replace(/^(row|config)\./, "")
        .replace(/[._-]+/g, " ")
        .replace(/\b\w/g, (letter) => letter.toUpperCase());
}
export async function runSetup() {
    if (state.setupRun?.status === "running") {
        return;
    }
    const preflight = await resolveSetupPreflight();
    if (preflight?.severity === "warning") {
        const setupID = appendTerminal("error", preflight.title ?? state.labels.setupTitle ?? "Setup", preflight.message ?? "");
        state.activeTerminalID = setupID;
        state.setupRun = {
            status: "failed",
            results: [],
            error: preflight.message,
            completedAt: new Date().toISOString(),
        };
        await persistBundleState();
        scheduleRender();
        return;
    }
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
        if (state.setupRun?.status && state.setupRun.status !== "running") {
            await persistBundleState();
        }
    }
    catch (error) {
        const tab = entry();
        if (tab) {
            tab.kind = "error";
            tab.body = [tab.body, errorMessage(error)].filter(Boolean).join("\n");
        }
        state.setupRun = { status: "failed", results: state.setupRun?.results ?? [], error: errorMessage(error), completedAt: new Date().toISOString() };
        await persistBundleState();
    }
    scheduleRender();
}
export async function openBundleWorkspace() {
    await api<void>("/api/open-bundle-workspace", { method: "POST", body: {} });
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
            state.setupRun = { ...event.result, completedAt: new Date().toISOString(), currentStepID: null };
            tab.kind = event.result?.status === "failed" ? "error" : "success";
            if (event.result?.error) {
                tab.body = [tab.body, event.result.error].filter(Boolean).join("\n");
            }
            break;
    }
    scheduleRender();
}
export function ensureDataSource(key, dataSource, context) {
    if (state.dataSourcePayloads.has(key) || state.dataSourceErrors.has(key) || state.loadingDataSources.has(key)) {
        return;
    }
    state.loadingDataSources.add(key);
    api<DataSourcePayload>("/api/datasource", { method: "POST", body: { dataSource, context } })
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
    api<PrecheckResult>("/api/precheck", {
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
    api<FileStateResponse>("/api/file-state", { method: "POST", body: { context } })
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
        const current = String(state.fieldValues[controlID] ?? "").trim();
        if (!current || !options.some((option) => option.id === current)) {
            state.fieldValues[controlID] = defaultValue;
        }
        return;
    }
    if (key.startsWith("setting:")) {
        const configKey = key.slice("setting:".length);
        const current = String(state.configValues[configKey] ?? "").trim();
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
    await api<void>("/api/state/save", {
        method: "POST",
        body: {
            state: {
                localizationCode: state.usingSystemDefaultLocale ? null : state.localizationCode,
                configFilePaths: state.configFilePaths,
                fieldValues,
                checkedOptions,
                selectedPageID: state.activePageID,
                iconSet: state.iconSet,
                colorTheme: state.colorTheme,
                webUIFont: state.webUIFont,
                ...(state.setupRun?.status === "running" ? {} : { setupRun: state.setupRun }),
            },
        },
    });
}
