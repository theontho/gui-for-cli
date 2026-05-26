import { configValueKey } from "../shared/rendering.js";
import { runDataSource } from "../web/src/server/action-runner.js";
import { configSettingBindings, saveBundleState, saveConfig } from "../web/src/server/config-store.js";
import { activePage, commandContext, controlWithDataSource, selectedIDs } from "./rendering.js";
import type { TUIApp } from "./app.js";
import type { BundleStateSnapshot, LooseRecord } from "../shared/types.js";
import type { TUICommandContext, TUIConfigSetting, TUIControl } from "./types.js";

export async function refreshDataSources(app: TUIApp) {
    const page = activePage(app.state);
    if (!page) {
        return;
    }
    for (const section of page.sections ?? []) {
        const sectionKey = `section:${section.id}`;
        if (section.dataSource) {
            await loadDataSource(app, sectionKey, section.dataSource, commandContext(app.state));
        }
        const sectionValues = app.state.dataSourcePayloads.get(sectionKey)?.values ?? {};
        const sectionContext = commandContext(app.state, {}, sectionValues);
        for (const rawControl of section.controls ?? []) {
            const control = controlWithDataSource(app.state, rawControl);
            if (control.dataSource) {
                await loadDataSource(app, `control:${control.id}`, control.dataSource, sectionContext);
            }
        }
    }
}

export async function loadDataSource(app: TUIApp, key: string, dataSource: LooseRecord, context: TUICommandContext) {
    try {
        const payload = await runDataSource(dataSource, context, app.state.bundleRootPath, app.runProcess);
        app.state.dataSourcePayloads.set(key, payload);
        app.state.dataSourceErrors.delete(key);
    } catch (error) {
        app.state.dataSourcePayloads.delete(key);
        app.state.dataSourceErrors.set(key, errorMessage(error));
    }
}

export async function updateField(app: TUIApp, control: TUIControl, value: string) {
    app.state.fieldValues[control.id] = value;
    const bindings = configSettingBindings(app.state.manifest, control.id);
    for (const binding of bindings) {
        app.state.configValues[configValueKey(binding.control, binding.setting)] = value;
        await persistConfig(app, binding.control);
    }
    await persistBundleState(app);
}

export async function updateCheckedOptions(app: TUIApp, control: TUIControl, ids: string[]) {
    app.state.checkedOptions[control.id] = ids;
    const bindings = configSettingBindings(app.state.manifest, control.id);
    for (const binding of bindings) {
        app.state.configValues[configValueKey(binding.control, binding.setting)] = ids.sort().join(",");
        await persistConfig(app, binding.control);
    }
    await persistBundleState(app);
}

export async function updateConfigSetting(app: TUIApp, control: TUIControl, setting: TUIConfigSetting, value: string) {
    app.state.configValues[configValueKey(control, setting)] = value;
    if (setting.key && Object.hasOwn(app.state.fieldValues, setting.key)) {
        app.state.fieldValues[setting.key] = value;
    }
    if (Object.hasOwn(app.state.fieldValues, setting.id)) {
        app.state.fieldValues[setting.id] = value;
    }
    await persistConfig(app, control);
    await persistBundleState(app);
}

export async function persistConfig(app: TUIApp, control: TUIControl) {
    const values = Object.fromEntries((control.settings ?? []).map((setting) => [
        setting.key,
        app.state.configValues[configValueKey(control, setting)] ?? setting.value ?? "",
    ]));
    const result = await saveConfig(control, app.state.configFilePaths?.[control.id], values, app.state.bundleRootPath);
    app.state.configFilePaths[control.id] = result.path;
}

export async function persistBundleState(app: TUIApp, partial: Partial<BundleStateSnapshot> = {}) {
    const state = {
        fieldValues: app.state.fieldValues,
        checkedOptions: Object.fromEntries(Object.entries(app.state.checkedOptions ?? {}).map(([key, value]) => [key, selectedIDs(value)])),
        configFilePaths: app.state.configFilePaths,
        selectedPageID: app.state.activePageID,
        setupRun: app.state.setupRun,
        ...partial,
    };
    app.state.bundleState = await saveBundleState(state, app.state.bundleRootPath);
}

function errorMessage(error: unknown) {
    return error instanceof Error ? error.message : String(error);
}
