import { readFile, readdir } from "node:fs/promises";
import path from "node:path";
import { localizeManifest, localizationLabels, mergeTables, parseTomlStrings, parseTomlStringValue } from "../shared/localization.js";
import { initialCheckedOptions, initialConfigFilePaths, initialConfigValues, initialFieldValues, loadBundleState, } from "./config-store.js";
import { isSafePageFileName } from "./paths.js";
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
    manifest.exitCodeReference = manifest.exitCodeReference ?? [];
    manifest.defaultLocalizationCode = manifest.defaultLocalizationCode ?? "en";
    return manifest;
}
export async function loadLocaleOptions(repoRoot, bundleRoot, rawManifest = undefined) {
    const manifest = rawManifest ?? (await loadManifestFromRoot(bundleRoot));
    const defaultCode = manifest.defaultLocalizationCode ?? "en";
    const seen = new Map();
    const builtinOptions = await Promise.all((await availableBuiltinLocaleCodes(repoRoot)).map(async (code) => {
        const displayName = await readLanguageDisplayName(path.join(repoRoot, "Sources", "GUIForCLICore", "Resources", "BuiltinStrings", `strings.${code}.toml`));
        return { code, displayName: displayName ?? code };
    }));
    for (const option of builtinOptions) {
        seen.set(option.code, option);
    }
    const bundleOptions = await Promise.all((await availableBundleLocaleCodes(bundleRoot)).map(async (code) => {
        const displayName = await readLanguageDisplayName(path.join(bundleRoot, "strings", `strings.${code}.toml`));
        return { code, displayName: displayName ?? seen.get(code)?.displayName ?? code };
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
    return readOptionalTable(path.join(repoRoot, "Sources", "GUIForCLICore", "Resources", "BuiltinStrings", `strings.${code}.toml`));
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
async function availableBuiltinLocaleCodes(repoRoot) {
    return availableLocaleCodes(path.join(repoRoot, "Sources", "GUIForCLICore", "Resources", "BuiltinStrings"));
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
export async function loadLocalizedBundle(locale, repoRoot, bundleRoot, sourceBundleRoot) {
    const rawManifest = await loadManifestFromRoot(bundleRoot);
    const locales = await loadLocaleOptions(repoRoot, bundleRoot, rawManifest);
    const bundleState = await loadBundleState(bundleRoot);
    const effectiveLocale = locale && locales.options.some((option) => option.code === locale)
        ? locale
        : bundleState.localizationCode && locales.options.some((option) => option.code === bundleState.localizationCode)
            ? bundleState.localizationCode
            : rawManifest.defaultLocalizationCode ?? "en";
    const table = await loadStringTable(rawManifest, effectiveLocale, repoRoot, bundleRoot);
    const manifest = localizeManifest(rawManifest, table);
    manifest.exitCodeReference = effectiveExitCodeReference(manifest.exitCodeReference, table);
    const configFilePaths = initialConfigFilePaths(manifest, bundleState);
    const configValues = await initialConfigValues(manifest, configFilePaths, bundleRoot);
    const fieldValues = initialFieldValues(manifest, configValues, bundleState);
    const checkedOptions = initialCheckedOptions(manifest, configValues, bundleState);
    return {
        manifest,
        labels: localizationLabels(table),
        localizationCode: effectiveLocale,
        localizationOptions: locales.options,
        bundleRootPath: bundleRoot,
        sourceRootPath: sourceBundleRoot,
        bundleState,
        configFilePaths,
        configValues,
        fieldValues,
        checkedOptions,
    };
}

export function createOneShotBundlePreload(load, initialLocale, enabled) {
    let preloadedLocale = enabled ? localeCacheKey(initialLocale) : undefined;
    let preloadedBundle = enabled ? load(initialLocale) : undefined;
    return {
        preloaded: preloadedBundle,
        async load(locale) {
            if (preloadedBundle && localeCacheKey(locale) === preloadedLocale) {
                const bundle = await preloadedBundle;
                preloadedBundle = undefined;
                preloadedLocale = undefined;
                return bundle;
            }
            return load(locale);
        },
    };
}

function localeCacheKey(locale) {
    return locale ?? "";
}
