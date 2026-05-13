import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { parseFlatToml, serializeFlatToml } from "../../../shared/rendering.js";
import { configPath } from "./paths.js";
export function normalizeIconSet(value) {
    return value === "emoji" ? "emoji" : "platform";
}
export function normalizeColorTheme(value) {
    return value === "light" || value === "dark" ? value : "system";
}
export function normalizeWebUIFont(value) {
    return value === "sfPro" ? "sfPro" : "system";
}
export function bundleStatePath(bundleRoot) {
    return path.join(bundleRoot, "state.json");
}
export function emptyBundleState() {
    return {
        localizationCode: null,
        configFilePaths: {},
        fieldValues: {},
        checkedOptions: {},
        selectedPageID: null,
        setupRun: null,
        iconSet: "platform",
        colorTheme: "system",
        webUIFont: "system",
    };
}
let saveBundleStateQueue = Promise.resolve();
export async function loadBundleState(bundleRoot) {
    try {
        const state = JSON.parse(await readFile(bundleStatePath(bundleRoot), "utf8"));
        return {
            localizationCode: state.localizationCode ?? null,
            configFilePaths: state.configFilePaths ?? {},
            fieldValues: state.fieldValues ?? {},
            checkedOptions: state.checkedOptions ?? {},
            selectedPageID: state.selectedPageID ?? null,
            setupRun: state.setupRun ?? null,
            iconSet: normalizeIconSet(state.iconSet),
            colorTheme: normalizeColorTheme(state.colorTheme),
            webUIFont: normalizeWebUIFont(state.webUIFont),
        };
    }
    catch (_error) {
        return emptyBundleState();
    }
}
export async function saveBundleState(partialState, bundleRoot) {
    const saveOperation = saveBundleStateQueue.then(async () => {
        const current = await loadBundleState(bundleRoot);
        const next = {
            localizationCode: Object.hasOwn(partialState, "localizationCode") ? partialState.localizationCode : current.localizationCode,
            configFilePaths: partialState.configFilePaths ?? current.configFilePaths,
            fieldValues: partialState.fieldValues ?? current.fieldValues,
            checkedOptions: partialState.checkedOptions ?? current.checkedOptions,
            selectedPageID: Object.hasOwn(partialState, "selectedPageID") ? partialState.selectedPageID : current.selectedPageID,
            setupRun: Object.hasOwn(partialState, "setupRun") ? partialState.setupRun : current.setupRun,
            iconSet: Object.hasOwn(partialState, "iconSet") ? normalizeIconSet(partialState.iconSet) : current.iconSet,
            colorTheme: Object.hasOwn(partialState, "colorTheme")
                ? normalizeColorTheme(partialState.colorTheme)
                : current.colorTheme,
            webUIFont: Object.hasOwn(partialState, "webUIFont") ? normalizeWebUIFont(partialState.webUIFont) : current.webUIFont,
        };
        await mkdir(path.dirname(bundleStatePath(bundleRoot)), { recursive: true });
        await writeFile(bundleStatePath(bundleRoot), `${JSON.stringify(next, null, 2)}\n`, "utf8");
        return next;
    });
    saveBundleStateQueue = saveOperation.then(() => undefined, () => undefined);
    return saveOperation;
}
export function initialConfigFilePaths(manifest, bundleState) {
    return Object.fromEntries(configEditorControls(manifest)
        .filter((control) => control.configFile)
        .map((control) => [control.id, bundleState.configFilePaths?.[control.id] ?? control.configFile.path]));
}
export async function initialConfigValues(manifest, configFilePaths, bundleRoot) {
    const values = Object.fromEntries(configEditorControls(manifest).flatMap((control) => (control.settings ?? []).map((setting) => [`${control.id}.${setting.id}`, setting.value ?? ""])));
    for (const control of configEditorControls(manifest)) {
        if (!control.configFile || !configFilePaths[control.id])
            continue;
        try {
            const fileValues = parseFlatToml(await readFile(configPath(control, configFilePaths[control.id], bundleRoot), "utf8"));
            for (const setting of control.settings ?? []) {
                if (fileValues[setting.key] != null) {
                    values[`${control.id}.${setting.id}`] = fileValues[setting.key];
                }
            }
        }
        catch (error) {
            if (error.code !== "ENOENT")
                throw error;
        }
    }
    return values;
}
export function initialFieldValues(manifest, configValues, bundleState) {
    const values = Object.fromEntries(allControls(manifest)
        .filter((control) => persistsFieldValue(control.kind))
        .map((control) => [control.id, control.value ?? ""]));
    for (const control of allControls(manifest).filter((control) => persistsFieldValue(control.kind))) {
        if (!configSettingBindings(manifest, control.id).length && bundleState.fieldValues?.[control.id] != null) {
            values[control.id] = bundleState.fieldValues[control.id];
        }
    }
    for (const control of configEditorControls(manifest)) {
        for (const setting of control.settings ?? []) {
            const value = configValues[`${control.id}.${setting.id}`] ?? setting.value ?? "";
            if (Object.hasOwn(values, setting.key))
                values[setting.key] = value;
            if (Object.hasOwn(values, setting.id))
                values[setting.id] = value;
        }
    }
    return values;
}
export function initialCheckedOptions(manifest, configValues, bundleState) {
    const values = {};
    for (const control of allControls(manifest).filter((candidate) => candidate.kind === "checkboxGroup")) {
        const binding = configSettingBindings(manifest, control.id)[0];
        if (binding) {
            const configValue = configValues[`${binding.control.id}.${binding.setting.id}`] ?? binding.setting.value ?? "";
            values[control.id] = configValue
                .split(",")
                .map((item) => item.trim())
                .filter(Boolean);
        }
        else if (bundleState.checkedOptions?.[control.id]) {
            values[control.id] = bundleState.checkedOptions[control.id];
        }
        else {
            values[control.id] = (control.options ?? []).filter((option) => option.selected).map((option) => option.id);
        }
    }
    return values;
}
export function configSettingBindings(manifest, fieldID) {
    return configEditorControls(manifest).flatMap((control) => (control.settings ?? [])
        .filter((setting) => setting.id === fieldID || setting.key === fieldID)
        .map((setting) => ({ control, setting })));
}
export function allControls(manifest) {
    return (manifest.pages ?? []).flatMap((page) => (page.sections ?? []).flatMap((section) => section.controls ?? []));
}
export function configEditorControls(manifest) {
    return allControls(manifest).filter((control) => control.kind === "configEditor");
}
export function persistsFieldValue(kind) {
    return ["text", "path", "dropdown", "toggle"].includes(kind);
}
export async function loadConfig(control, requestedPath, bundleRoot) {
    const filePath = configPath(control, requestedPath, bundleRoot);
    let values = {};
    try {
        values = parseFlatToml(await readFile(filePath, "utf8"));
    }
    catch (error) {
        if (error.code !== "ENOENT") {
            throw error;
        }
    }
    return {
        path: filePath,
        values: Object.fromEntries((control.settings ?? []).map((setting) => [setting.key, values[setting.key] ?? setting.value ?? ""])),
    };
}
export async function saveConfig(control, requestedPath, values, bundleRoot) {
    const filePath = configPath(control, requestedPath, bundleRoot);
    const byKey = {};
    for (const setting of control.settings ?? []) {
        byKey[setting.key] = values[setting.key] ?? values[setting.id] ?? values[`${control.id}.${setting.id}`] ?? setting.value ?? "";
    }
    await mkdir(path.dirname(filePath), { recursive: true });
    await writeFile(filePath, serializeFlatToml(byKey), "utf8");
    return { path: filePath, keyCount: Object.keys(byKey).length };
}
