import { execFile } from "node:child_process";
import { existsSync } from "node:fs";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { parseFlatToml, serializeFlatToml } from "../../../shared/rendering.js";
import { configPath, expandPathTokens } from "./paths.js";

const bootstrapScriptTimeoutMs = 30_000;
const inheritedBootstrapEnvironmentKeys = [
    "PATH",
    "HOME",
    "USERPROFILE",
    "TMPDIR",
    "TMP",
    "TEMP",
    "SystemRoot",
    "WINDIR",
    "COMSPEC",
    "PATHEXT",
    "LOCALAPPDATA",
    "APPDATA",
];
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
        .map((control) => {
        const persistedPath = bundleState.configFilePaths?.[control.id];
        const defaultPath = control.configFile.path;
        return [
            control.id,
            persistedPath && !shouldDiscardLegacyConfigPath(persistedPath, defaultPath)
                ? persistedPath
                : defaultPath,
        ];
    }));
}
function shouldDiscardLegacyConfigPath(value, defaultPath) {
    if (!String(defaultPath ?? "").includes("{{bundleWorkspace}}")) {
        return false;
    }
    const normalized = String(value ?? "").replaceAll("\\", "/");
    return normalized === "{{home}}/.config/wgsextract/config.toml" ||
        normalized.endsWith("/.config/wgsextract/config.toml");
}
export async function bootstrapConfigFiles(manifest, bundleRoot, configFilePaths) {
    for (const control of configEditorControls(manifest)) {
        const configFile = control.configFile;
        const bootstrap = configFile?.bootstrap;
        if (!configFile || !bootstrap || bootstrap.mode === "none") {
            continue;
        }
        const targetPath = configFilePaths[control.id] ?? configFile.path;
        const defaultURL = resolveConfigFilePath(targetPath, bundleRoot);
        const existing = await readOptionalFlatToml(defaultURL);
        const mode = bootstrap.mode ?? "createIfMissing";
        if (shouldSkipBootstrap(control, mode, existing)) {
            continue;
        }
        const document = await bootstrapDocument(control, bundleRoot, defaultURL, bootstrap.script);
        await bootstrapToml(control, mode, document.url, document.contents);
    }
}
function shouldSkipBootstrap(control, mode, existing) {
    if (mode === "createIfMissing") {
        return existing != null;
    }
    if (mode !== "mergeMissing" || existing == null) {
        return false;
    }
    return (control.settings ?? []).every((setting) => String(existing[setting.key] ?? "").trim() !== "");
}
async function bootstrapDocument(control, bundleRoot, defaultURL, script) {
    if (!script) {
        return {
            url: defaultURL,
            contents: serializeFlatToml(Object.fromEntries((control.settings ?? []).map((setting) => [setting.key, setting.value ?? ""]))),
        };
    }
    const payload = await runBootstrapScript(script, control, bundleRoot, defaultURL);
    const payloadPath = String(payload.path ?? "").trim();
    return {
        url: payloadPath ? resolveConfigFilePath(payloadPath, bundleRoot) : defaultURL,
        contents: await scriptContents(payload, bundleRoot),
    };
}
async function runBootstrapScript(script, control, bundleRoot, defaultURL) {
    const scriptPath = resolveBundledPath(script.path, bundleRoot, true);
    const workingDirectory = resolveBundledPath(script.workingDirectory ?? "", bundleRoot, false);
    const shell = bootstrapShell();
    const args = [
        scriptPath,
        ...(script.arguments ?? []).map((argument) => expandConfigPath(argument, bundleRoot, defaultURL)),
    ];
    const stdout = await new Promise((resolve, reject) => {
        execFile(shell, args, {
            cwd: workingDirectory,
            env: scriptEnvironment(script, control, bundleRoot, defaultURL),
            maxBuffer: 1024 * 1024,
            timeout: bootstrapScriptTimeoutMs,
            killSignal: "SIGTERM",
        }, (error, stdout, stderr) => {
            if (error) {
                const reason = error.killed ? `timed out after ${bootstrapScriptTimeoutMs}ms` : "failed";
                reject(new Error(`Config bootstrap script ${reason}: ${scriptPath}\n${[stdout, stderr].filter(Boolean).join("\n")}`));
                return;
            }
            resolve(stdout);
        });
    });
    try {
        return JSON.parse(String(stdout).trim());
    }
    catch (_error) {
        throw new Error(`Config bootstrap script did not return valid JSON: ${scriptPath}`);
    }
}
function bootstrapShell() {
    if (process.platform !== "win32") {
        return "/bin/sh";
    }
    const gitShell = "C:\\Program Files\\Git\\bin\\sh.exe";
    return existsSync(gitShell) ? gitShell : "sh";
}
function scriptEnvironment(script, control, bundleRoot, defaultURL) {
    return {
        ...Object.fromEntries(inheritedBootstrapEnvironmentKeys.flatMap((key) => process.env[key] == null ? [] : [[key, process.env[key]]])),
        GUI_FOR_CLI_BUNDLE_ROOT: bundleRoot,
        GUI_FOR_CLI_BUNDLE_WORKSPACE: bundleRoot,
        GUI_FOR_CLI_CONFIG_PATH: defaultURL,
        GUI_FOR_CLI_CONFIG_DIR: path.dirname(defaultURL),
        GUI_FOR_CLI_CONFIG_CONTROL_ID: control.id,
        GUI_FOR_CLI_CONFIG_CONTROL_LABEL: control.label,
        GUI_FOR_CLI_DRY_RUN: "0",
        ...Object.fromEntries(Object.entries(script.environment ?? {}).map(([key, value]) => [
            key,
            expandConfigPath(value, bundleRoot, defaultURL),
        ])),
    };
}
async function scriptContents(payload, bundleRoot) {
    if (payload.contents != null) {
        return String(payload.contents);
    }
    const contentsPath = String(payload.contentsPath ?? "").trim();
    if (contentsPath) {
        return readFile(resolveConfigFilePath(contentsPath, bundleRoot), "utf8");
    }
    if (payload.values) {
        return serializeFlatToml(payload.values);
    }
    return "";
}
async function bootstrapToml(control, mode, url, contents) {
    const existing = await readOptionalFlatToml(url);
    if (mode === "createIfMissing" && existing != null) {
        return;
    }
    const defaults = parseFlatToml(contents);
    const next = mode === "mergeMissing" && existing
        ? { ...existing }
        : { ...defaults };
    if (mode === "mergeMissing" && existing) {
        for (const [key, value] of Object.entries(defaults)) {
            if (String(existing[key] ?? "").trim() === "") {
                next[key] = value;
            }
        }
    }
    if (mode !== "createIfMissing" && mode !== "mergeMissing") {
        throw new Error(`Unsupported config bootstrap mode: ${mode}`);
    }
    await mkdir(path.dirname(url), { recursive: true });
    await writeFile(url, serializeFlatToml(next), "utf8");
}
async function readOptionalFlatToml(filePath) {
    try {
        return parseFlatToml(await readFile(filePath, "utf8"));
    }
    catch (error) {
        if (error.code === "ENOENT") {
            return null;
        }
        throw error;
    }
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
function resolveConfigFilePath(value, bundleRoot) {
    const expanded = expandPathTokens(value, bundleRoot);
    return path.isAbsolute(expanded) ? expanded : path.resolve(bundleRoot, expanded);
}
function expandConfigPath(value, bundleRoot, configURL) {
    return expandPathTokens(String(value ?? ""), bundleRoot).replaceAll("{{configPath}}", configURL).replaceAll("{{configDir}}", path.dirname(configURL));
}
function resolveBundledPath(value, bundleRoot, mustExist) {
    if (!value) {
        return bundleRoot;
    }
    if (path.isAbsolute(value) || value.split(/[\\/]/).includes("..")) {
        throw new Error(`Config bootstrap script path must be relative and stay inside the bundle: ${value}`);
    }
    const candidate = path.resolve(bundleRoot, value);
    const relative = path.relative(bundleRoot, candidate);
    if (relative.startsWith("..") || path.isAbsolute(relative)) {
        throw new Error(`Config bootstrap script path must be relative and stay inside the bundle: ${value}`);
    }
    if (mustExist && !existsSync(candidate)) {
        throw new Error(`Config bootstrap script does not exist: ${candidate}`);
    }
    return candidate;
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
