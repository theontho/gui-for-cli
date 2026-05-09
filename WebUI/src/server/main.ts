#!/usr/bin/env node
import { createServer } from "node:http";
import { chmod, cp, mkdir, readFile, readdir, rm, stat, statfs, writeFile } from "node:fs/promises";
import { createReadStream } from "node:fs";
import { homedir, platform } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { localizeManifest, localizationLabels, mergeTables, parseTomlStrings } from "../shared/localization.js";
import {
  checkedOptionsForContext,
  displayCommand,
  evaluateNumeric,
  interpolate,
  parseFlatToml,
  renderedCommand,
  serializeFlatToml,
} from "../shared/rendering.js";
import { contentType, json, notFound, readJSONBody, staticFile } from "./http.js";
import { createProcessManager } from "./process-runner.js";

const serverDir = path.dirname(fileURLToPath(import.meta.url));
const distRoot = path.resolve(serverDir, "..");
const webuiRoot = path.resolve(distRoot, "..");
const repoRoot = path.resolve(webuiRoot, "..");
const args = parseArgs(process.argv.slice(2));
const sourceBundleRoot = path.resolve(args.bundle ?? path.join(repoRoot, "Examples", "WGSExtract"));
const port = Number(args.port ?? process.env.PORT ?? 8787);
const host = args.host ?? "127.0.0.1";
const defaultLocale = args.locale;
const maxBodyBytes = 1_048_576;
const maxOutputBytes = 1_048_576;
const maxErrorBytes = 65_536;
const dataSourceTimeoutMs = 15_000;
const sourceManifest = await loadManifestFromRoot(sourceBundleRoot);
const bundleRoot = await prepareBundleWorkspace(sourceManifest, sourceBundleRoot);
const { runProcess, terminateAllProcesses } = createProcessManager({ maxOutputBytes, maxErrorBytes });
let isShuttingDown = false;

const routes = {
  "/": (response, headOnly) => staticFile(path.join(webuiRoot, "index.html"), "text/html; charset=utf-8", response, headOnly),
  "/index.html": (response, headOnly) =>
    staticFile(path.join(webuiRoot, "index.html"), "text/html; charset=utf-8", response, headOnly),
  "/favicon.ico": (response, headOnly) => serveBundleFavicon(response, headOnly),
  "/client/app.js": (response, headOnly) => staticFile(path.join(distRoot, "client", "app.js"), "text/javascript; charset=utf-8", response, headOnly),
  "/styles.css": (response, headOnly) => staticFile(path.join(webuiRoot, "styles.css"), "text/css; charset=utf-8", response, headOnly),
};

const server = createServer(async (request, response) => {
  try {
    const url = new URL(request.url ?? "/", `http://${request.headers.host ?? "localhost"}`);
    if ((request.method === "GET" || request.method === "HEAD") && routes[url.pathname]) {
      await routes[url.pathname](response, request.method === "HEAD");
      return;
    }
    const compiledModulePath = distModulePath(url.pathname);
    if ((request.method === "GET" || request.method === "HEAD") && compiledModulePath) {
      await staticFile(compiledModulePath, "text/javascript; charset=utf-8", response, request.method === "HEAD");
      return;
    }
    if (request.method === "GET" && url.pathname === "/api/locales") {
      await json(response, await loadLocaleOptions());
      return;
    }
    if (request.method === "GET" && url.pathname === "/api/manifest") {
      const locale = url.searchParams.get("locale") || defaultLocale;
      await json(response, await loadLocalizedBundle(locale));
      return;
    }
    if (request.method === "GET" && url.pathname === "/api/file") {
      await serveBundleFile(response, url.searchParams.get("path") ?? "");
      return;
    }
    if (request.method === "POST" && url.pathname === "/api/datasource") {
      const body = await readJSONBody(request, maxBodyBytes);
      const payload = await runDataSource(body.dataSource, normalizeContext(body.context));
      await json(response, payload);
      return;
    }
    if (request.method === "POST" && url.pathname === "/api/run") {
      const body = await readJSONBody(request, maxBodyBytes);
      const abortController = new AbortController();
      const abort = () => abortController.abort();
      request.on("aborted", abort);
      response.on("close", () => {
        if (!response.writableEnded) {
          abort();
        }
      });
      const result = await runAction(body.action, normalizeContext(body.context), abortController.signal);
      await json(response, result);
      return;
    }
    if (request.method === "POST" && url.pathname === "/api/precheck") {
      const body = await readJSONBody(request, maxBodyBytes);
      const result = await evaluatePrecheck(body.precheck, normalizeContext(body.context), body.labels ?? {});
      await json(response, result);
      return;
    }
    if (request.method === "POST" && url.pathname === "/api/config/load") {
      const body = await readJSONBody(request, maxBodyBytes);
      await json(response, await loadConfig(body.control, body.path));
      return;
    }
    if (request.method === "POST" && url.pathname === "/api/config/save") {
      const body = await readJSONBody(request, maxBodyBytes);
      await json(response, await saveConfig(body.control, body.path, body.values ?? {}));
      return;
    }
    if (request.method === "POST" && url.pathname === "/api/state/save") {
      const body = await readJSONBody(request, maxBodyBytes);
      await json(response, await saveBundleState(body.state ?? {}));
      return;
    }
    await notFound(response);
  } catch (error) {
    if (request.aborted || response.destroyed) {
      return;
    }
    await json(response, { error: error.message }, 500);
  }
});

server.listen(port, host, () => {
  console.log(`GUI for CLI Web UI: http://${host}:${port}/`);
  console.log(`Bundle source: ${sourceBundleRoot}`);
  console.log(`Bundle workspace: ${bundleRoot}`);
});
installShutdownHandlers();

function installShutdownHandlers() {
  for (const signal of ["SIGINT", "SIGTERM", "SIGHUP"]) {
    process.once(signal, () => shutdown(signal));
  }
  process.once("beforeExit", () => terminateAllProcesses());
  process.once("uncaughtException", (error) => {
    console.error(error);
    shutdown("uncaughtException");
  });
}

function shutdown(reason) {
  if (isShuttingDown) {
    return;
  }
  isShuttingDown = true;
  terminateAllProcesses();
  server.close(() => process.exit(reason === "SIGINT" ? 130 : 0));
  setTimeout(() => process.exit(reason === "SIGINT" ? 130 : 0), 500).unref();
}

async function loadLocalizedBundle(requestedLocale) {
  const rawManifest = await loadRawManifest();
  const locales = await loadLocaleOptions(rawManifest);
  const bundleState = await loadBundleState();
  const locale =
    requestedLocale && locales.options.some((option) => option.code === requestedLocale)
      ? requestedLocale
      : bundleState.localizationCode && locales.options.some((option) => option.code === bundleState.localizationCode)
        ? bundleState.localizationCode
        : rawManifest.defaultLocalizationCode ?? "en";
  const table = await loadStringTable(rawManifest, locale);
  const manifest = localizeManifest(rawManifest, table);
  manifest.exitCodeReference = effectiveExitCodeReference(manifest.exitCodeReference, table);
  const configFilePaths = initialConfigFilePaths(manifest, bundleState);
  const configValues = await initialConfigValues(manifest, configFilePaths);
  const fieldValues = initialFieldValues(manifest, configValues, bundleState);
  const checkedOptions = initialCheckedOptions(manifest, configValues, bundleState);
  return {
    manifest,
    labels: localizationLabels(table),
    localizationCode: locale,
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

async function loadRawManifest() {
  return loadManifestFromRoot(bundleRoot);
}

async function loadManifestFromRoot(root) {
  const manifestPath = path.join(root, "manifest.json");
  const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
  if (Array.isArray(manifest.pages) && manifest.pages.every((page) => typeof page === "string")) {
    manifest.pageFiles = manifest.pages;
    manifest.pages = await Promise.all(
      manifest.pageFiles.map(async (pageFile) => {
        if (!isSafePageFileName(pageFile)) {
          throw new Error(`Invalid page file name: ${pageFile}`);
        }
        return JSON.parse(await readFile(path.join(root, "pages", pageFile), "utf8"));
      }),
    );
  }
  manifest.setup = manifest.setup ?? { steps: [] };
  manifest.exitCodeReference = manifest.exitCodeReference ?? [];
  manifest.defaultLocalizationCode = manifest.defaultLocalizationCode ?? "en";
  return manifest;
}

async function loadLocaleOptions(rawManifest = undefined) {
  const manifest = rawManifest ?? (await loadRawManifest());
  const defaultCode = manifest.defaultLocalizationCode ?? "en";
  const seen = new Map();
  for (const code of await availableBuiltinLocaleCodes()) {
    const table = await readBuiltinTable(code);
    seen.set(code, { code, displayName: table["language.name"] ?? code });
  }
  for (const code of await availableBundleLocaleCodes()) {
    const table = await readBundleTable(code);
    seen.set(code, { code, displayName: table["language.name"] ?? seen.get(code)?.displayName ?? code });
  }
  const options = [...seen.values()].sort((first, second) => {
    if (first.code === defaultCode) return -1;
    if (second.code === defaultCode) return 1;
    return first.displayName.localeCompare(second.displayName);
  });
  return { defaultLocalizationCode: defaultCode, options };
}

async function loadStringTable(manifest, locale) {
  const defaultCode = manifest.defaultLocalizationCode ?? "en";
  const builtinBase = await readBuiltinTable("en");
  const builtinOverlay = locale === "en" ? {} : await readBuiltinTable(locale);
  const bundleBase = await readBundleTable(defaultCode);
  const bundleOverlay = locale === defaultCode ? {} : await readBundleTable(locale);
  return mergeTables(builtinBase, builtinOverlay, bundleBase, bundleOverlay);
}

function effectiveExitCodeReference(overrides = [], table = {}) {
  const defaults = [
    {
      code: 1,
      title: table["exitCodes.default.1.title"] ?? "General command failure",
      summary:
        table["exitCodes.default.1.summary"] ??
        "The command reported a generic failure. Review the output for details.",
      severity: "error",
    },
    {
      code: 2,
      title: table["exitCodes.default.2.title"] ?? "Command-line usage error",
      summary:
        table["exitCodes.default.2.summary"] ??
        "The command arguments were not accepted. Check required inputs, paths, and selected options before running again.",
      severity: "error",
    },
    {
      code: 126,
      title: table["exitCodes.default.126.title"] ?? "Command found but not executable",
      summary:
        table["exitCodes.default.126.summary"] ??
        "The command or script exists but could not be executed. Check file permissions and whether setup completed successfully.",
      severity: "error",
    },
    {
      code: 127,
      title: table["exitCodes.default.127.title"] ?? "Command not found",
      summary:
        table["exitCodes.default.127.summary"] ??
        "The command runner could not find the executable. Run setup for this bundle and verify the runtime workspace exists.",
      severity: "error",
    },
    {
      code: 130,
      title: table["exitCodes.default.130.title"] ?? "Command cancelled",
      summary:
        table["exitCodes.default.130.summary"] ??
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

async function readBuiltinTable(code) {
  return readOptionalTable(path.join(repoRoot, "Sources", "GUIForCLICore", "Resources", "BuiltinStrings", `strings.${code}.toml`));
}

async function readBundleTable(code) {
  return readOptionalTable(path.join(bundleRoot, "strings", `strings.${code}.toml`));
}

async function readOptionalTable(filePath) {
  try {
    return parseTomlStrings(await readFile(filePath, "utf8"));
  } catch (error) {
    if (error.code === "ENOENT") {
      return {};
    }
    throw error;
  }
}

async function availableBuiltinLocaleCodes() {
  return availableLocaleCodes(path.join(repoRoot, "Sources", "GUIForCLICore", "Resources", "BuiltinStrings"));
}

async function availableBundleLocaleCodes() {
  return availableLocaleCodes(path.join(bundleRoot, "strings"));
}

async function availableLocaleCodes(directory) {
  try {
    const files = await readdir(directory);
    return files
      .map((file) => /^strings\.([A-Za-z0-9_-]+)\.toml$/.exec(file)?.[1])
      .filter(Boolean);
  } catch (error) {
    if (error.code === "ENOENT") {
      return [];
    }
    throw error;
  }
}

async function runDataSource(dataSource, context) {
  if (!dataSource?.path) {
    throw new Error("Missing data source path.");
  }
  const executable = resolveBundlePath(dataSource.path);
  const workingDirectory = dataSource.workingDirectory ? resolveBundlePath(dataSource.workingDirectory) : bundleRoot;
  const args = (dataSource.arguments ?? []).map((argument) => interpolate(argument, context));
  const env = {
    ...process.env,
    GUI_FOR_CLI_BUNDLE_ROOT: bundleRoot,
    GUI_FOR_CLI_BUNDLE_WORKSPACE: bundleRoot,
    GUI_FOR_CLI_DATA_SOURCE: "1",
  };
  for (const [key, value] of Object.entries(context.fieldValues ?? {})) {
    env[`GUI_FOR_CLI_FIELD_${environmentKey(key)}`] = value;
  }
  for (const [key, value] of Object.entries(context.configValues ?? {})) {
    env[`GUI_FOR_CLI_CONFIG_${environmentKey(key)}`] = value;
  }
  for (const [key, value] of Object.entries(dataSource.environment ?? {})) {
    env[key] = interpolate(value, context);
  }
  const result = await runProcess(executable, args, { cwd: workingDirectory, env, timeoutMs: dataSourceTimeoutMs });
  if (result.exitCode !== 0) {
    throw new Error(`Data source ${dataSource.path} exited ${result.exitCode}: ${result.stderr || "no stderr"}`);
  }
  try {
    return JSON.parse(result.stdout || "{}");
  } catch (error) {
    throw new Error(`Data source ${dataSource.path} did not print valid JSON: ${error.message}`);
  }
}

async function runAction(action, context, signal) {
  if (!action?.command) {
    throw new Error("Missing action command.");
  }
  const rendered = renderedCommand(action.command, context);
  const startedAt = new Date().toISOString();
  const result = await runProcess(rendered.executable, rendered.arguments, {
    cwd: bundleRoot,
    env: { ...process.env, GUI_FOR_CLI_BUNDLE_ROOT: bundleRoot, GUI_FOR_CLI_BUNDLE_WORKSPACE: bundleRoot },
    signal,
  });
  return {
    ...result,
    startedAt,
    finishedAt: new Date().toISOString(),
    command: displayCommand(action.command, context),
  };
}

async function evaluatePrecheck(precheck, context, labels) {
  if (!precheck?.diskSpaceGB) {
    return null;
  }
  const interpolated = await interpolatePrecheck(precheck.diskSpaceGB, context);
  const requiredGB = evaluateNumeric(interpolated);
  if (!Number.isFinite(requiredGB) || requiredGB <= 0) {
    return null;
  }

  const pathExpression = precheck.diskSpacePath || "{{out_dir}}";
  let targetPath = (await interpolatePrecheck(pathExpression, context)).trim();
  if (!targetPath) {
    targetPath = context.bundleRootPath || homedir();
  }
  const expandedPath = resolveUserPath(targetPath);
  const availableGB = await volumeAvailableGB(expandedPath);
  if (!Number.isFinite(availableGB)) {
    return null;
  }

  const severity = availableGB < requiredGB ? "warning" : "info";
  const required = formatGB(requiredGB);
  const available = formatGB(availableGB);
  const pathLabel = await diskPathLabel(expandedPath);
  const title =
    severity === "warning"
      ? labels.actionPrecheckDiskSpaceTitle || "Not enough free disk space"
      : labels.actionPrecheckDiskSpaceInfoTitle || "Disk space estimate";
  const format =
    severity === "warning" && precheck.warningMessage
      ? await interpolatePrecheck(precheck.warningMessage, context)
      : severity === "warning"
        ? labels.actionPrecheckDiskSpaceMessageFormat ||
          "Need %{required} GB free at %{path}, only %{available} GB available."
        : labels.actionPrecheckDiskSpaceInfoFormat ||
          "Estimated %{required} GB needed at %{path} (%{available} GB free).";

  return {
    severity,
    title,
    message: String(format)
      .replaceAll("%{required}", required)
      .replaceAll("%{available}", available)
      .replaceAll("%{path}", pathLabel),
    requiredGB,
    availableGB,
    path: expandedPath,
    pathLabel,
  };
}

async function interpolatePrecheck(value, context) {
  let output = "";
  let cursor = 0;
  for (const match of String(value ?? "").matchAll(/\{\{([^}]+)\}\}/g)) {
    output += String(value).slice(cursor, match.index);
    output += (await precheckContextValue(context, match[1].trim())) ?? "";
    cursor = match.index + match[0].length;
  }
  output += String(value ?? "").slice(cursor);
  return output;
}

async function precheckContextValue(context, placeholder) {
  const separator = placeholder.lastIndexOf(".");
  if (separator > 0 && separator < placeholder.length - 1) {
    const fieldID = placeholder.slice(0, separator);
    const property = placeholder.slice(separator + 1);
    const rawPath = context.fieldValues?.[fieldID] ?? context.configValues?.[fieldID];
    if (property === "fileSizeGB" || property === "fileSize") {
      const bytes = await fileSizeBytes(rawPath);
      if (!Number.isFinite(bytes)) {
        return "";
      }
      return property === "fileSizeGB" ? String(bytes / 1_073_741_824) : String(bytes);
    }
    if (property === "parentDir") {
      return rawPath ? path.dirname(resolveUserPath(rawPath)) : "";
    }
  }
  return interpolate(`{{${placeholder}}}`, context);
}

async function fileSizeBytes(rawPath) {
  if (!rawPath) {
    return Number.NaN;
  }
  try {
    const info = await stat(resolveUserPath(rawPath));
    return info.isFile() ? info.size : Number.NaN;
  } catch (error) {
    if (error.code === "ENOENT") {
      return Number.NaN;
    }
    throw error;
  }
}

async function volumeAvailableGB(rawPath) {
  let probe = resolveUserPath(rawPath);
  while (probe && probe !== path.dirname(probe)) {
    try {
      const info = await statfs(probe);
      return Number(info.bavail * info.bsize) / 1_073_741_824;
    } catch (error) {
      if (error.code !== "ENOENT" && error.code !== "ENOTDIR") {
        throw error;
      }
      probe = path.dirname(probe);
    }
  }
  return Number.NaN;
}

async function diskPathLabel(rawPath) {
  const expanded = resolveUserPath(rawPath);
  const folderName = path.basename(expanded) || expanded;
  const volumeName = await volumeNameForPath(expanded);
  return volumeName && volumeName !== folderName ? `${folderName} (${volumeName})` : folderName;
}

async function volumeNameForPath(rawPath) {
  const probe = await existingAncestor(rawPath);
  if (platform() === "win32") {
    const root = path.parse(probe).root;
    return root ? root.replace(/[\\/]$/, "") : undefined;
  }
  if (platform() === "darwin") {
    try {
      const result = await runProcess("/usr/sbin/diskutil", ["info", "-plist", probe], {
        cwd: bundleRoot,
        env: process.env,
        maxOutputBytes: 262_144,
        maxErrorBytes: 16_384,
      });
      if (result.exitCode === 0) {
        const match = /<key>VolumeName<\/key>\s*<string>([^<]+)<\/string>/.exec(result.stdout);
        if (match?.[1]) {
          return decodeXML(match[1]);
        }
      }
    } catch (error) {
      if (error.message !== "Process cancelled.") {
        console.warn(`Could not read volume name for ${probe}: ${error.message}`);
      }
      return undefined;
    }
  }
  return undefined;
}

async function existingAncestor(rawPath) {
  let probe = resolveUserPath(rawPath);
  while (probe && probe !== path.dirname(probe)) {
    try {
      await stat(probe);
      return probe;
    } catch (error) {
      if (error.code !== "ENOENT" && error.code !== "ENOTDIR") {
        throw error;
      }
      probe = path.dirname(probe);
    }
  }
  return probe || resolveUserPath(rawPath);
}

function decodeXML(value) {
  return String(value)
    .replaceAll("&amp;", "&")
    .replaceAll("&lt;", "<")
    .replaceAll("&gt;", ">")
    .replaceAll("&quot;", '"')
    .replaceAll("&apos;", "'");
}

function resolveUserPath(value) {
  const expanded = expandPathTokens(value);
  return path.isAbsolute(expanded) ? expanded : path.resolve(bundleRoot, expanded);
}

function formatGB(value) {
  if (value >= 100) {
    return value.toFixed(0);
  }
  if (value >= 10) {
    return value.toFixed(1);
  }
  return value.toFixed(2);
}

async function loadConfig(control, requestedPath) {
  const filePath = configPath(control, requestedPath);
  let values = {};
  try {
    values = parseFlatToml(await readFile(filePath, "utf8"));
  } catch (error) {
    if (error.code !== "ENOENT") {
      throw error;
    }
  }
  return {
    path: filePath,
    values: Object.fromEntries((control.settings ?? []).map((setting) => [setting.key, values[setting.key] ?? setting.value ?? ""])),
  };
}

async function saveConfig(control, requestedPath, values) {
  const filePath = configPath(control, requestedPath);
  const byKey = {};
  for (const setting of control.settings ?? []) {
    byKey[setting.key] = values[setting.key] ?? values[setting.id] ?? values[`${control.id}.${setting.id}`] ?? setting.value ?? "";
  }
  await mkdir(path.dirname(filePath), { recursive: true });
  await writeFile(filePath, serializeFlatToml(byKey), "utf8");
  return { path: filePath, keyCount: Object.keys(byKey).length };
}

async function loadBundleState() {
  try {
    const state = JSON.parse(await readFile(bundleStatePath(), "utf8"));
    return {
      localizationCode: state.localizationCode ?? null,
      configFilePaths: state.configFilePaths ?? {},
      fieldValues: state.fieldValues ?? {},
      checkedOptions: state.checkedOptions ?? {},
      iconSet: normalizeIconSet(state.iconSet),
      colorTheme: normalizeColorTheme(state.colorTheme),
    };
  } catch (error) {
    if (error.code === "ENOENT") {
      return emptyBundleState();
    }
    return emptyBundleState();
  }
}

async function saveBundleState(partialState) {
  const current = await loadBundleState();
  const next = {
    localizationCode:
      Object.hasOwn(partialState, "localizationCode") ? partialState.localizationCode : current.localizationCode,
    configFilePaths: partialState.configFilePaths ?? current.configFilePaths,
    fieldValues: partialState.fieldValues ?? current.fieldValues,
    checkedOptions: partialState.checkedOptions ?? current.checkedOptions,
    iconSet: Object.hasOwn(partialState, "iconSet") ? normalizeIconSet(partialState.iconSet) : current.iconSet,
    colorTheme: Object.hasOwn(partialState, "colorTheme")
      ? normalizeColorTheme(partialState.colorTheme)
      : current.colorTheme,
  };
  await mkdir(path.dirname(bundleStatePath()), { recursive: true });
  await writeFile(bundleStatePath(), `${JSON.stringify(next, null, 2)}\n`, "utf8");
  return next;
}

function emptyBundleState() {
  return {
    localizationCode: null,
    configFilePaths: {},
    fieldValues: {},
    checkedOptions: {},
    iconSet: "platform",
    colorTheme: "system",
  };
}

function normalizeIconSet(value) {
  return value === "emoji" ? "emoji" : "platform";
}

function normalizeColorTheme(value) {
  return value === "light" || value === "dark" ? value : "system";
}

function bundleStatePath() {
  return path.join(bundleRoot, "state.json");
}

function initialConfigFilePaths(manifest, bundleState) {
  return Object.fromEntries(
    configEditorControls(manifest)
      .filter((control) => control.configFile)
      .map((control) => [control.id, bundleState.configFilePaths?.[control.id] ?? control.configFile.path]),
  );
}

async function initialConfigValues(manifest, configFilePaths) {
  const values = Object.fromEntries(
    configEditorControls(manifest).flatMap((control) =>
      (control.settings ?? []).map((setting) => [`${control.id}.${setting.id}`, setting.value ?? ""]),
    ),
  );
  for (const control of configEditorControls(manifest)) {
    if (!control.configFile || !configFilePaths[control.id]) continue;
    try {
      const fileValues = parseFlatToml(await readFile(configPath(control, configFilePaths[control.id]), "utf8"));
      for (const setting of control.settings ?? []) {
        if (fileValues[setting.key] != null) {
          values[`${control.id}.${setting.id}`] = fileValues[setting.key];
        }
      }
    } catch (error) {
      if (error.code !== "ENOENT") throw error;
    }
  }
  return values;
}

function initialFieldValues(manifest, configValues, bundleState) {
  const values = Object.fromEntries(
    allControls(manifest)
      .filter((control) => persistsFieldValue(control.kind))
      .map((control) => [control.id, control.value ?? ""]),
  );
  for (const control of allControls(manifest).filter((control) => persistsFieldValue(control.kind))) {
    if (!configSettingBindings(manifest, control.id).length && bundleState.fieldValues?.[control.id] != null) {
      values[control.id] = bundleState.fieldValues[control.id];
    }
  }
  for (const control of configEditorControls(manifest)) {
    for (const setting of control.settings ?? []) {
      const value = configValues[`${control.id}.${setting.id}`] ?? setting.value ?? "";
      if (Object.hasOwn(values, setting.key)) values[setting.key] = value;
      if (Object.hasOwn(values, setting.id)) values[setting.id] = value;
    }
  }
  return values;
}

function initialCheckedOptions(manifest, configValues, bundleState) {
  const values = {};
  for (const control of allControls(manifest).filter((candidate) => candidate.kind === "checkboxGroup")) {
    const binding = configSettingBindings(manifest, control.id)[0];
    if (binding) {
      const configValue = configValues[`${binding.control.id}.${binding.setting.id}`] ?? binding.setting.value ?? "";
      values[control.id] = configValue
        .split(",")
        .map((item) => item.trim())
        .filter(Boolean);
    } else if (bundleState.checkedOptions?.[control.id]) {
      values[control.id] = bundleState.checkedOptions[control.id];
    } else {
      values[control.id] = (control.options ?? []).filter((option) => option.selected).map((option) => option.id);
    }
  }
  return values;
}

function configSettingBindings(manifest, fieldID) {
  return configEditorControls(manifest).flatMap((control) =>
    (control.settings ?? [])
      .filter((setting) => setting.id === fieldID || setting.key === fieldID)
      .map((setting) => ({ control, setting })),
  );
}

function allControls(manifest) {
  return (manifest.pages ?? []).flatMap((page) => (page.sections ?? []).flatMap((section) => section.controls ?? []));
}

function configEditorControls(manifest) {
  return allControls(manifest).filter((control) => control.kind === "configEditor");
}

function persistsFieldValue(kind) {
  return ["text", "path", "dropdown", "toggle"].includes(kind);
}

function configPath(control, requestedPath) {
  const rawPath = requestedPath || control?.configFile?.path;
  if (!rawPath) {
    throw new Error("Choose a settings file path before loading or saving.");
  }
  const expanded = expandPathTokens(rawPath);
  return path.isAbsolute(expanded) ? expanded : path.join(bundleRoot, expanded);
}

function expandPathTokens(value, configPathValue = "") {
  const home = homedir();
  const configHome = process.env.XDG_CONFIG_HOME || path.join(home, ".config");
  const applicationSupport =
    platform() === "darwin"
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

function normalizeContext(context: Record<string, any> = {}) {
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

function resolveBundlePath(value) {
  const expanded = expandPathTokens(value);
  if (path.isAbsolute(expanded)) {
    throw new Error(`Bundle script paths must be relative: ${value}`);
  }
  const candidate = path.resolve(bundleRoot, expanded);
  if (!candidate.startsWith(`${bundleRoot}${path.sep}`) && candidate !== bundleRoot) {
    throw new Error(`Bundle script path escapes bundle root: ${value}`);
  }
  return candidate;
}

async function prepareBundleWorkspace(manifest, sourceRoot) {
  const workspaceRoot = path.join(applicationSupportDirectory(), "gui-for-cli", "BundleWorkspaces", safePathComponent(manifest.id));
  await mkdir(workspaceRoot, { recursive: true });
  for (const entry of await readdir(sourceRoot, { withFileTypes: true })) {
    if (entry.name.startsWith(".")) continue;
    const source = path.join(sourceRoot, entry.name);
    const destination = path.join(workspaceRoot, entry.name);
    if (entry.name === "runtime") {
      try {
        await stat(destination);
        continue;
      } catch (error) {
        if (error.code !== "ENOENT") throw error;
      }
    }
    await rm(destination, { recursive: true, force: true });
    await cp(source, destination, { recursive: true });
  }
  await markDemoScriptsExecutable(workspaceRoot);
  return workspaceRoot;
}

async function markDemoScriptsExecutable(root) {
  for (const scriptName of [
    "setup-wgsextract-pixi.sh",
    "bootstrap-wgsextract-config.sh",
    "run-wgsextract.sh",
    "list-reference-genomes.py",
    "delete-reference-genome.sh",
  ]) {
    try {
      await chmod(path.join(root, "scripts", scriptName), 0o755);
    } catch (error) {
      if (error.code !== "ENOENT") throw error;
    }
  }
}

function applicationSupportDirectory() {
  if (platform() === "darwin") {
    return path.join(homedir(), "Library", "Application Support");
  }
  return process.env.XDG_DATA_HOME || path.join(homedir(), ".local", "share");
}

function safePathComponent(value) {
  const sanitized = String(value)
    .split("")
    .map((character) => (/[A-Za-z0-9_.-]/.test(character) ? character : "-"))
    .join("")
    .replace(/^[.-]+|[.-]+$/g, "");
  return sanitized || "bundle";
}

async function serveBundleFile(response, relativePath) {
  const filePath = resolveBundlePath(relativePath);
  const info = await stat(filePath);
  if (!info.isFile()) {
    await notFound(response);
    return;
  }
  response.writeHead(200, { "content-type": contentType(filePath) });
  createReadStream(filePath).pipe(response);
}

async function serveBundleFavicon(response, headOnly = false) {
  for (const relativePath of ["Assets/favicon.ico", "favicon.ico", "Assets/icon.png"]) {
    try {
      const filePath = resolveBundlePath(relativePath);
      const info = await stat(filePath);
      if (info.isFile()) {
        response.writeHead(200, {
          "content-type": contentType(filePath),
          "content-length": info.size,
          "cache-control": "no-cache",
        });
        if (headOnly) {
          response.end();
          return;
        }
        createReadStream(filePath).pipe(response);
        return;
      }
    } catch (error) {
      if (error.code !== "ENOENT") {
        throw error;
      }
    }
  }
  await notFound(response);
}

function distModulePath(pathname) {
  const match = /^\/(client|shared)\/([A-Za-z0-9_.-]+\.js)$/.exec(pathname);
  if (!match) {
    return undefined;
  }
  return path.join(distRoot, match[1] ?? "", match[2] ?? "");
}

function isSafePageFileName(value) {
  return Boolean(value && !value.startsWith("/") && !value.includes("/") && !value.split("/").includes("..") && value.endsWith(".json"));
}

function environmentKey(value) {
  return String(value)
    .split("")
    .map((character) => (/[A-Za-z0-9]/.test(character) ? character.toUpperCase() : "_"))
    .join("");
}

function parseArgs(argv) {
  const parsed: Record<string, string | undefined> = {};
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--bundle") parsed.bundle = argv[++index];
    else if (arg === "--port") parsed.port = argv[++index];
    else if (arg === "--host") parsed.host = argv[++index];
    else if (arg === "--locale") parsed.locale = argv[++index];
    else if (!parsed.bundle) parsed.bundle = arg;
  }
  return parsed;
}
