import { realpathSync } from "node:fs";
import { homedir, platform } from "node:os";
import path from "node:path";
import { checkedOptionsForContext } from "../shared/rendering.js";
export function parseArgs(argv) {
    const parsed: Record<string, string | undefined> = {};
    const readValue = (flag: string, index: number) => {
        const next = argv[index];
        if (!next || next.startsWith("--")) {
            throw new Error(`Missing value for ${flag}`);
        }
        return next;
    };
    for (let index = 0; index < argv.length; index += 1) {
        const arg = argv[index];
        if (arg === "--bundle")
            parsed.bundle = readValue("--bundle", ++index);
        else if (arg === "--port")
            parsed.port = readValue("--port", ++index);
        else if (arg === "--host")
            parsed.host = readValue("--host", ++index);
        else if (arg === "--locale")
            parsed.locale = readValue("--locale", ++index);
        else if (arg === "--theme")
            parsed.theme = readValue("--theme", ++index);
        else if (arg === "--once")
            parsed.once = "true";
        else if (arg === "--benchmark")
            parsed.benchmark = "true";
        else if (arg === "--setup")
            parsed.setup = "true";
        else if (arg === "--no-setup")
            parsed.setup = "false";
        else if (arg === "--help" || arg === "-h")
            parsed.help = "true";
        else if (!parsed.bundle)
            parsed.bundle = arg;
    }
    return parsed;
}
export function applicationSupportDirectory() {
    if (platform() === "darwin") {
        return path.join(homedir(), "Library", "Application Support");
    }
    return process.env.XDG_DATA_HOME || path.join(homedir(), ".local", "share");
}
export function safePathComponent(value) {
    const sanitized = String(value)
        .split("")
        .map((character) => (/[A-Za-z0-9_.-]/.test(character) ? character : "-"))
        .join("")
        .replace(/^[.-]+|[.-]+$/g, "");
    return sanitized || "bundle";
}
export function environmentKey(value) {
    return String(value)
        .split("")
        .map((character) => (/[A-Za-z0-9]/.test(character) ? character.toUpperCase() : "_"))
        .join("");
}
export function isSafePageFileName(value) {
    return Boolean(value &&
        !value.startsWith("/") &&
        !value.startsWith("\\") &&
        !value.includes("/") &&
        !value.includes("\\") &&
        !value.split("/").includes("..") &&
        !value.split("\\").includes("..") &&
        value.endsWith(".json"));
}
export function decodeXML(value) {
    return String(value)
        .replaceAll("&lt;", "<")
        .replaceAll("&gt;", ">")
        .replaceAll("&quot;", '"')
        .replaceAll("&apos;", "'")
        .replaceAll("&amp;", "&");
}
export function formatGB(value) {
    if (value >= 100) {
        return value.toFixed(0);
    }
    if (value >= 10) {
        return value.toFixed(1);
    }
    return value.toFixed(2);
}
export function expandPathTokens(value, bundleRoot, configPathValue = "") {
    const home = homedir();
    const configHome = process.env.XDG_CONFIG_HOME || path.join(home, ".config");
    const applicationSupport = platform() === "darwin"
        ? path.join(home, "Library", "Application Support")
        : process.env.XDG_DATA_HOME || path.join(home, ".local", "share");
    return String(value)
        .replaceAll("{{bundleRoot}}", bundleRoot)
        .replaceAll("{{bundleWorkspace}}", bundleRoot)
        .replaceAll("{{home}}", home)
        .replaceAll("{{configHome}}", configHome)
        .replaceAll("{{userConfig}}", configHome)
        .replaceAll("{{applicationSupport}}", applicationSupport)
        .replaceAll("{{appConfig}}", applicationSupport)
        .replaceAll("{{configPath}}", configPathValue ?? "")
        .replaceAll("{{configDir}}", configPathValue ? path.dirname(configPathValue) : "")
        .replace(/^~(?=\/|$)/, home);
}
export function resolveUserPath(value, bundleRoot) {
    const expanded = expandPathTokens(value, bundleRoot);
    return path.isAbsolute(expanded) ? expanded : path.resolve(bundleRoot, expanded);
}
export function resolveBundlePath(value, bundleRoot) {
    const expanded = expandPathTokens(value, bundleRoot);
    if (path.isAbsolute(expanded)) {
        throw new Error(`Bundle script paths must be relative: ${value}`);
    }
    const candidate = path.resolve(bundleRoot, expanded);
    if (!candidate.startsWith(`${bundleRoot}${path.sep}`) && candidate !== bundleRoot) {
        throw new Error(`Bundle script path escapes bundle root: ${value}`);
    }
    const realCandidate = realPathIfExists(candidate);
    if (realCandidate) {
        const realRoot = realpathSync(bundleRoot);
        if (!realCandidate.startsWith(`${realRoot}${path.sep}`) && realCandidate !== realRoot) {
            throw new Error(`Bundle script path escapes bundle root: ${value}`);
        }
        return realCandidate;
    }
    return candidate;
}
function realPathIfExists(candidate) {
    try {
        return realpathSync(candidate);
    }
    catch (error) {
        if (error.code === "ENOENT" || error.code === "ENOTDIR") {
            return undefined;
        }
        throw error;
    }
}
export function configPath(control, requestedPath, bundleRoot) {
    const rawPath = requestedPath || control?.configFile?.path;
    if (!rawPath) {
        throw new Error("Choose a settings file path before loading or saving.");
    }
    const expanded = expandPathTokens(rawPath, bundleRoot);
    return path.isAbsolute(expanded) ? expanded : path.join(bundleRoot, expanded);
}
export function distModulePath(pathname, distRoot) {
    const match = /^\/(client|shared)\/([A-Za-z0-9_.-]+\.js)$/.exec(pathname);
    if (!match) {
        return undefined;
    }
    return path.join(distRoot, match[1] ?? "", match[2] ?? "");
}
export function normalizeContext(context: Record<string, any> = {}, bundleRoot) {
    return {
        ...context,
        fieldValues: context.fieldValues ?? {},
        checkedOptions: context.checkedOptions ?? checkedOptionsForContext({}),
        configValues: context.configValues ?? {},
        rowValues: context.rowValues ?? {},
        bundleRootPath: bundleRoot,
        homePath: homedir(),
    };
}
