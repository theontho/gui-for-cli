import { readFile, readdir, stat } from "node:fs/promises";
import path from "node:path";
import { mergeIconMaps, parseIconMapToml } from "../../../shared/icon-map.js";
import { localizeManifest, localizationLabels, mergeTables, parseTomlStrings, parseTomlStringValue } from "../../../shared/localization.js";
import { bootstrapConfigFiles, initialCheckedOptions, initialConfigFilePaths, initialConfigValues, initialFieldValues, loadBundleState, } from "./config-store.js";
import { isSafePageFileName } from "./paths.js";
import { validatePlatformScriptSets } from "./platform-scripts.js";

export async function resolveBundleSourceRoot(source: string): Promise<string> {
    const value = String(source ?? "").trim();
    if (!value) {
        throw new Error("Choose a bundle folder or manifest.json file.");
    }
    const resolved = path.resolve(value);
    const info = await stat(resolved);
    if (info.isDirectory()) {
        return resolved;
    }
    if (info.isFile() && path.basename(resolved).toLowerCase() === "manifest.json") {
        return path.dirname(resolved);
    }
    throw new Error("Choose a bundle folder or manifest.json file.");
}

export async function loadManifestFromRoot(root) {
    const manifestPath = path.join(root, "manifest.json");
    const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
    if (Array.isArray(manifest.pages) && manifest.pages.every((page) => typeof page === "string")) {
        manifest.pageFiles = manifest.pages;
        manifest.pages = await Promise.all(manifest.pageFiles.map(async (pageFile) => {
            if (!isSafePageFileName(pageFile)) {
                throw new Error(`Invalid page file name: ${pageFile}`);
            }
            return JSON.parse(await readFile(path.join(root, "pages", pageFile), "utf8"));
        }));
    }
    manifest.setup = manifest.setup ?? { steps: [] };
    manifest.uninstall = manifest.uninstall ?? { steps: [] };
    manifest.exitCodeReference = manifest.exitCodeReference ?? [];
    manifest.defaultLocalizationCode = manifest.defaultLocalizationCode ?? "en";
    await resolveSetupToolVersions(manifest, root);
    await validatePlatformScriptSets(root, manifest);
    return manifest;
}
export async function loadLocaleOptions(repoRoot, bundleRoot, rawManifest = undefined) {
    const manifest = rawManifest ?? (await loadManifestFromRoot(bundleRoot));
    const defaultCode = manifest.defaultLocalizationCode ?? "en";
    const seen = new Map();
    const builtinOptions = await Promise.all((await availableBuiltinLocaleCodes(repoRoot)).map(async (code) => {
        const displayName = await readLanguageDisplayName(path.join(builtinStringsRoot(repoRoot), `strings.${code}.toml`));
        return { code, displayName: displayName ?? code, isAITranslated: false };
    }));
    for (const option of builtinOptions) {
        seen.set(option.code, option);
    }
    const bundleOptions = await Promise.all((await availableBundleLocaleCodes(bundleRoot)).map(async (code) => {
        const filePath = path.join(bundleRoot, "strings", `strings.${code}.toml`);
        const displayName = await readLanguageDisplayName(filePath);
        const isAITranslated = await readLanguageAITranslatedFlag(filePath);
        return {
            code,
            displayName: displayName ?? seen.get(code)?.displayName ?? code,
            isAITranslated: isAITranslated ?? seen.get(code)?.isAITranslated ?? false,
        };
    }));
    for (const option of bundleOptions) {
        seen.set(option.code, option);
    }
    const options = [...seen.values()].sort((first, second) => {
        if (first.code === defaultCode)
            return -1;
        if (second.code === defaultCode)
            return 1;
        return first.displayName.localeCompare(second.displayName);
    });
    return { defaultLocalizationCode: defaultCode, options };
}
export async function loadStringTable(manifest, locale, repoRoot, bundleRoot) {
    const defaultCode = manifest.defaultLocalizationCode ?? "en";
    const builtinBase = await readBuiltinTable("en", repoRoot);
    const builtinOverlay = locale === "en" ? {} : await readBuiltinTable(locale, repoRoot);
    const bundleBase = await readBundleTable(defaultCode, bundleRoot);
    const bundleOverlay = locale === defaultCode ? {} : await readBundleTable(locale, bundleRoot);
    return mergeTables(builtinBase, builtinOverlay, bundleBase, bundleOverlay);
}
export async function loadIconMap(repoRoot, bundleRoot) {
    const builtin = await readOptionalIconMap(path.join(builtinResourcesRoot(repoRoot), "BuiltinIconMap", "iconmap.toml"));
    const bundle = await readOptionalIconMap(path.join(bundleRoot, "iconmap.toml"));
    return mergeIconMaps(builtin, bundle);
}
export function effectiveExitCodeReference(overrides = [], table = {}) {
    const defaults = [
        {
            code: 1,
            title: table["exitCodes.default.1.title"] ?? "General command failure",
            summary: table["exitCodes.default.1.summary"] ??
                "The command reported a generic failure. Review the output for details.",
            severity: "error",
        },
        {
            code: 2,
            title: table["exitCodes.default.2.title"] ?? "Command-line usage error",
            summary: table["exitCodes.default.2.summary"] ??
                "The command arguments were not accepted. Check required inputs, paths, and selected options before running again.",
            severity: "error",
        },
        {
            code: 126,
            title: table["exitCodes.default.126.title"] ?? "Command found but not executable",
            summary: table["exitCodes.default.126.summary"] ??
                "The command or script exists but could not be executed. Check file permissions and whether setup completed successfully.",
            severity: "error",
        },
        {
            code: 127,
            title: table["exitCodes.default.127.title"] ?? "Command not found",
            summary: table["exitCodes.default.127.summary"] ??
                "The command runner could not find the executable. Run setup for this bundle and verify the runtime workspace exists.",
            severity: "error",
        },
        {
            code: 130,
            title: table["exitCodes.default.130.title"] ?? "Command cancelled",
            summary: table["exitCodes.default.130.summary"] ??
                "The command was interrupted by the user. Any partial output or temporary files may need to be cleaned up before retrying.",
            severity: "warning",
        },
    ];
    const byCode = new Map(defaults.map((entry) => [entry.code, entry]));
    for (const entry of overrides) {
        byCode.set(entry.code, { severity: "error", ...entry });
    }
    return [...byCode.values()].sort((first, second) => first.code - second.code);
}
async function readBuiltinTable(code, repoRoot) {
    return readOptionalTable(path.join(builtinStringsRoot(repoRoot), `strings.${code}.toml`));
}
async function readBundleTable(code, bundleRoot) {
    return readOptionalTable(path.join(bundleRoot, "strings", `strings.${code}.toml`));
}
async function readOptionalTable(filePath) {
    try {
        return parseTomlStrings(await readFile(filePath, "utf8"));
    }
    catch (error) {
        if (error.code === "ENOENT") {
            return {};
        }
        throw error;
    }
}
async function readOptionalIconMap(filePath) {
    try {
        return parseIconMapToml(await readFile(filePath, "utf8"));
    }
    catch (error) {
        if (error.code === "ENOENT") {
            return {};
        }
        throw error;
    }
}
async function availableBuiltinLocaleCodes(repoRoot) {
    return availableLocaleCodes(builtinStringsRoot(repoRoot));
}
function builtinStringsRoot(repoRoot) {
    return path.join(builtinResourcesRoot(repoRoot), "BuiltinStrings");
}
function builtinResourcesRoot(repoRoot) {
    return path.join(repoRoot, "resources");
}
async function availableBundleLocaleCodes(bundleRoot) {
    return availableLocaleCodes(path.join(bundleRoot, "strings"));
}
async function availableLocaleCodes(directory) {
    try {
        const files = await readdir(directory);
        return files
            .map((file) => /^strings\.([A-Za-z0-9_-]+)\.toml$/.exec(file)?.[1])
            .filter(Boolean);
    }
    catch (error) {
        if (error.code === "ENOENT") {
            return [];
        }
        throw error;
    }
}
async function readLanguageDisplayName(filePath) {
    try {
        return parseTomlStringValue(await readFile(filePath, "utf8"), "language.name");
    }
    catch (error) {
        if (error.code === "ENOENT") {
            return undefined;
        }
        throw error;
    }
}
async function readLanguageAITranslatedFlag(filePath) {
    try {
        const value = parseTomlStringValue(await readFile(filePath, "utf8"), "language.aiTranslated");
        if (value == null) {
            return undefined;
        }
        const normalized = value.trim().toLowerCase();
        if (["true", "yes", "1"].includes(normalized)) {
            return true;
        }
        if (["false", "no", "0"].includes(normalized)) {
            return false;
        }
        return undefined;
    }
    catch (error) {
        if (error.code === "ENOENT") {
            return undefined;
        }
        throw error;
    }
}
export async function loadLocalizedBundle(locale, repoRoot, bundleRoot, sourceBundleRoot, preferredLocales = []) {
    const rawManifest = await loadManifestFromRoot(bundleRoot);
    const locales = await loadLocaleOptions(repoRoot, bundleRoot, rawManifest);
    const bundleState = await loadBundleState(bundleRoot);
    const systemLocale = matchLocalizationCode(preferredLocales, locales.options);
    const effectiveLocale = locale && locales.options.some((option) => option.code === locale)
        ? locale
        : bundleState.localizationCode && locales.options.some((option) => option.code === bundleState.localizationCode)
            ? bundleState.localizationCode
            : systemLocale ?? rawManifest.defaultLocalizationCode ?? "en";
    const table = await loadStringTable(rawManifest, effectiveLocale, repoRoot, bundleRoot);
    const localizedOptions = locales.options.map((option) => ({
        ...option,
        displayName: table[`language.names.${option.code}`] ?? option.displayName,
    }));
    const manifest = localizeManifest(rawManifest, table);
    const iconMap = await loadIconMap(repoRoot, bundleRoot);
    manifest.exitCodeReference = effectiveExitCodeReference(manifest.exitCodeReference, table);
    const configFilePaths = initialConfigFilePaths(manifest, bundleState);
    await bootstrapConfigFiles(manifest, bundleRoot, configFilePaths);
    const configValues = await initialConfigValues(manifest, configFilePaths, bundleRoot);
    const fieldValues = initialFieldValues(manifest, configValues, bundleState);
    const checkedOptions = initialCheckedOptions(manifest, configValues, bundleState);
    return {
        manifest,
        labels: localizationLabels(table),
        iconMap,
        localizationCode: effectiveLocale,
        localizationOptions: localizedOptions,
        usingSystemDefaultLocale: !locale && !bundleState.localizationCode,
        bundleRootPath: bundleRoot,
        sourceRootPath: sourceBundleRoot,
        bundleState,
        configFilePaths,
        configValues,
        fieldValues,
        checkedOptions,
    };
}
function matchLocalizationCode(preferences, options) {
    const available = new Set(options.map((option) => option.code));
    for (const raw of preferences ?? []) {
        const candidate = String(raw ?? "").trim();
        if (!candidate) {
            continue;
        }
        if (available.has(candidate)) {
            return candidate;
        }
        const [primary, ...rest] = candidate.split("-");
        if (primary && available.has(primary)) {
            return primary;
        }
        if (primary === "zh") {
            const region = rest.join("-").toLowerCase();
            if (["cn", "sg", "hans"].some((part) => region.includes(part)) && available.has("zh-Hans")) {
                return "zh-Hans";
            }
            if (["tw", "hk", "mo", "hant"].some((part) => region.includes(part)) && available.has("zh-Hant")) {
                return "zh-Hant";
            }
        }
    }
    return undefined;
}

export function createOneShotBundlePreload(load, initialLocale, enabled) {
    let preloadedLocale = enabled ? localeCacheKey(initialLocale) : undefined;
    let preloadedBundle = enabled ? load(initialLocale) : undefined;
    return {
        preloaded: preloadedBundle,
        async load(locale, preferredLocales = []) {
            if (preloadedBundle && preferredLocales.length === 0 && localeCacheKey(locale) === preloadedLocale) {
                const bundle = await preloadedBundle;
                preloadedBundle = undefined;
                preloadedLocale = undefined;
                return bundle;
            }
            return load(locale, preferredLocales);
        },
    };
}

function localeCacheKey(locale) {
    return locale ?? "";
}

async function resolveSetupToolVersions(manifest: any, root: string): Promise<void> {
    const stepGroups: Array<[string, any[]]> = [
        ["setup.steps", manifest.setup.steps],
        ["uninstall.steps", manifest.uninstall.steps],
    ];
    for (const [scope, steps] of stepGroups) {
        for (const step of steps) {
            if (step.toolVersion || !step.toolVersionFile) {
                continue;
            }
            const stepID = String(step.id ?? "<unknown>");
            const stepLabel = String(step.label ?? "").trim();
            const context = `${scope}.${stepID}${stepLabel ? ` (${stepLabel})` : ""}.toolVersionFile`;
            const versionFile = String(step.toolVersionFile);
            if (!isSafeRelativePath(versionFile)) {
                throw new Error(`Invalid ${context}: ${versionFile}`);
            }
            try {
                const firstLine = (await readFile(path.join(root, versionFile), "utf8")).split(/\r?\n/, 1)[0]?.trim();
                if (firstLine) {
                    step.toolVersion = firstLine;
                }
            }
            catch (error) {
                const message = error instanceof Error ? error.message : String(error);
                throw new Error(`Could not read ${context} at ${versionFile}: ${message}`, { cause: error });
            }
        }
    }
}

function isSafeRelativePath(value: string): boolean {
    const normalized = value.replaceAll("\\", "/");
    return Boolean(normalized.trim()) && !path.isAbsolute(normalized) && !normalized.split("/").includes("..");
}
