#!/usr/bin/env node
import { watch } from "node:fs";
import { writeFile } from "node:fs/promises";
import { createServer, type ServerResponse } from "node:http";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { fileStateValues, runAction, runDataSource, evaluatePrecheck } from "./action-runner.js";
import { serveBundleFavicon, serveBundleFile } from "./assets.js";
import { createOneShotBundlePreload, loadLocaleOptions, loadLocalizedBundle, loadManifestFromRoot } from "./bundle-loader.js";
import { loadConfig, saveBundleState, saveConfig } from "./config-store.js";
import { contentType, json, notFound, readJSONBody, staticFile } from "./http.js";
import { distModulePath, normalizeContext, parseArgs } from "./paths.js";
import { pickPath } from "./path-picker.js";
import { createProcessManager } from "./process-runner.js";
import { runSetup } from "./setup-runner.js";
import { prepareBundleWorkspace } from "./workspace.js";
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
const enableDevReload = process.env.WEBUI_DEV_RELOAD === "1";
const sourceManifest = await loadManifestFromRoot(sourceBundleRoot);
const bundleRoot = await prepareBundleWorkspace(sourceManifest, sourceBundleRoot);
const { runProcess, terminateAllProcesses } = createProcessManager({ maxOutputBytes, maxErrorBytes });
const localizedBundleLoader = createOneShotBundlePreload(loadBundleForServer, defaultLocale, Boolean(args.bundle));
let server;
let isShuttingDown = false;
installParentMonitor();
installShutdownHandlers();
const routes = {
    "/": (response, headOnly) => staticFile(path.join(webuiRoot, "index.html"), "text/html; charset=utf-8", response, headOnly),
    "/index.html": (response, headOnly) => staticFile(path.join(webuiRoot, "index.html"), "text/html; charset=utf-8", response, headOnly),
    "/favicon.ico": (response, headOnly) => serveBundleFavicon(response, headOnly, bundleRoot),
    "/client/app.js": (response, headOnly) => staticFile(path.join(distRoot, "client", "app.js"), "text/javascript; charset=utf-8", response, headOnly),
    "/styles.css": (response, headOnly) => staticFile(path.join(webuiRoot, "styles.css"), "text/css; charset=utf-8", response, headOnly),
};
server = createServer(async (request, response) => {
    try {
        const url = new URL(request.url ?? "/", `http://${request.headers.host ?? "localhost"}`);
        if ((request.method === "GET" || request.method === "HEAD") && routes[url.pathname]) {
            await routes[url.pathname](response, request.method === "HEAD");
            return;
        }
        if (request.method === "GET" && url.pathname === "/api/dev/reload" && enableDevReload) {
            addDevReloadClient(response);
            return;
        }
        const vendorFilePath = webuiVendorAssetPath(url.pathname);
        if ((request.method === "GET" || request.method === "HEAD") && vendorFilePath) {
            await staticFile(vendorFilePath, contentType(vendorFilePath), response, request.method === "HEAD");
            return;
        }
        const compiledModulePath = distModulePath(url.pathname, distRoot);
        if ((request.method === "GET" || request.method === "HEAD") && compiledModulePath) {
            await staticFile(compiledModulePath, "text/javascript; charset=utf-8", response, request.method === "HEAD");
            return;
        }
        if (request.method === "GET" && url.pathname === "/api/locales") {
            await json(response, await loadLocaleOptions(repoRoot, bundleRoot));
            return;
        }
        if (request.method === "GET" && url.pathname === "/api/manifest") {
            const locale = url.searchParams.get("locale") || defaultLocale;
            await json(response, await localizedBundleLoader.load(locale));
            return;
        }
        if (request.method === "GET" && url.pathname === "/api/file") {
            await serveBundleFile(response, url.searchParams.get("path") ?? "", bundleRoot);
            return;
        }
        if (request.method === "POST" && url.pathname === "/api/datasource") {
            const body = await readJSONBody(request, maxBodyBytes);
            const payload = await runDataSource(body.dataSource, normalizeContext(body.context, bundleRoot), bundleRoot, runProcess);
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
            const result = await runAction(body.action, normalizeContext(body.context, bundleRoot), abortController.signal, bundleRoot, runProcess);
            await json(response, result);
            return;
        }
        if (request.method === "POST" && url.pathname === "/api/precheck") {
            const body = await readJSONBody(request, maxBodyBytes);
            const result = await evaluatePrecheck(body.precheck, normalizeContext(body.context, bundleRoot), body.labels ?? {}, bundleRoot, runProcess);
            await json(response, result);
            return;
        }
        if (request.method === "POST" && url.pathname === "/api/file-state") {
            const body = await readJSONBody(request, maxBodyBytes);
            await json(response, { values: await fileStateValues(normalizeContext(body.context, bundleRoot), bundleRoot) });
            return;
        }
        if (request.method === "POST" && url.pathname === "/api/setup/stream") {
            const body = await readJSONBody(request, maxBodyBytes);
            const bundle = await localizedBundleLoader.load(body.locale || defaultLocale);
            response.writeHead(200, { "content-type": "application/x-ndjson; charset=utf-8" });
            await runSetup(bundle.manifest, bundleRoot, runProcess, (event) => {
                response.write(`${JSON.stringify(event)}\n`);
            });
            response.end();
            return;
        }
        if (request.method === "POST" && url.pathname === "/api/path/pick") {
            const body = await readJSONBody(request, maxBodyBytes);
            await json(response, await pickPath({ ...body, bundleRoot }));
            return;
        }
        if (request.method === "POST" && url.pathname === "/api/config/load") {
            const body = await readJSONBody(request, maxBodyBytes);
            await json(response, await loadConfig(body.control, body.path, bundleRoot));
            return;
        }
        if (request.method === "POST" && url.pathname === "/api/config/save") {
            const body = await readJSONBody(request, maxBodyBytes);
            await json(response, await saveConfig(body.control, body.path, body.values ?? {}, bundleRoot));
            return;
        }
        if (request.method === "POST" && url.pathname === "/api/state/save") {
            const body = await readJSONBody(request, maxBodyBytes);
            await json(response, await saveBundleState(body.state ?? {}, bundleRoot));
            return;
        }
        await notFound(response);
    }
    catch (error) {
        if (request.aborted || response.destroyed) {
            return;
        }
        await json(response, { error: error.message }, 500);
    }
});
server.listen(port, host, () => {
    const address = server?.address();
    const boundPort = typeof address === "object" && address ? address.port : port;
    console.log(`GUI for CLI Web UI: http://${host}:${boundPort}/`);
    console.log(`Bundle source: ${sourceBundleRoot}`);
    console.log(`Bundle workspace: ${bundleRoot}`);
    if (process.env.GFC_PORT_FILE) {
        writeFile(process.env.GFC_PORT_FILE, `${boundPort}\n`).catch((error) => {
            console.error(`Could not write GFC_PORT_FILE: ${error.message}`);
            shutdown("portFileError");
        });
    }
});
installDevReloadWatcher();
async function loadBundleForServer(locale) {
    return loadLocalizedBundle(locale, repoRoot, bundleRoot, sourceBundleRoot);
}
function webuiVendorAssetPath(pathname) {
    const prefix = "/vendor/bootstrap-icons/";
    if (!pathname.startsWith(prefix)) {
        return undefined;
    }
    const vendorRoot = path.resolve(webuiRoot, "vendor", "bootstrap-icons");
    const filePath = path.resolve(vendorRoot, pathname.slice(prefix.length));
    return filePath === vendorRoot || filePath.startsWith(`${vendorRoot}${path.sep}`) ? filePath : undefined;
}
const devReloadClients = new Set<ServerResponse>();
function addDevReloadClient(response) {
    response.writeHead(200, {
        "content-type": "text/event-stream; charset=utf-8",
        "cache-control": "no-cache",
        connection: "keep-alive",
    });
    response.write("event: ready\ndata: ok\n\n");
    devReloadClients.add(response);
    response.on("close", () => devReloadClients.delete(response));
}
function installDevReloadWatcher() {
    if (!enableDevReload) {
        return;
    }
    for (const directory of [path.join(distRoot, "client"), path.join(distRoot, "shared"), webuiRoot]) {
        try {
            const watcher = watch(directory, { persistent: false }, (_event, fileName) => {
                const name = String(fileName ?? "");
                if (directory === webuiRoot && !["index.html", "styles.css"].includes(name)) {
                    return;
                }
                notifyDevReload();
            });
            process.once("exit", () => watcher.close());
        }
        catch (error) {
            console.warn(`Could not watch ${directory}: ${error.message}`);
        }
    }
}
function notifyDevReload() {
    for (const client of [...devReloadClients]) {
        client.write("event: reload\ndata: changed\n\n");
    }
}
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
function installParentMonitor() {
    const parentPid = Number(process.env.GFC_PARENT_PID ?? "");
    if (!Number.isInteger(parentPid) || parentPid <= 1) {
        return;
    }
    const timer = setInterval(() => {
        try {
            process.kill(parentPid, 0);
        }
        catch (error) {
            if (error?.code === "ESRCH") {
                shutdown("parentExit");
            }
        }
    }, 1000);
    timer.unref();
}
function shutdown(reason) {
    if (isShuttingDown) {
        return;
    }
    isShuttingDown = true;
    terminateAllProcesses();
    const exitCode = reason === "SIGINT" ? 130 : reason === "uncaughtException" ? 1 : 0;
    if (!server) {
        process.exit(exitCode);
    }
    server.close(() => process.exit(exitCode));
    setTimeout(() => process.exit(exitCode), 500).unref();
}
