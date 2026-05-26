import { configEditorControls, configValueKey } from "../../../shared/rendering.js";
import { api } from "./api.js";
import { boundFieldKey, configSettingBindings, errorMessage, formatLabel, syncSharedField } from "./model.js";
import { scheduleRender } from "./rerender.js";
import { state } from "./state.js";
import { appendTerminal } from "./terminal.js";
import { persistBundleState } from "./operations-state.js";
import type { ConfigLoadResponse, ConfigSaveResponse } from "../../../shared/types.js";

export async function loadInitialConfigs() {
    for (const control of configEditorControls(state.manifest ?? {})) {
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
