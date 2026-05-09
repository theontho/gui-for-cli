#!/usr/bin/env node
import { createServer } from "node:http";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { fileStateValues, runAction, runDataSource, evaluatePrecheck } from "./action-runner.js";
import { serveBundleFavicon, serveBundleFile } from "./assets.js";
import { loadLocaleOptions, loadLocalizedBundle, loadManifestFromRoot } from "./bundle-loader.js";
import { loadConfig, saveBundleState, saveConfig } from "./config-store.js";
import { json, notFound, readJSONBody, staticFile } from "./http.js";
import { distModulePath, normalizeContext, parseArgs } from "./paths.js";
import { createProcessManager } from "./process-runner.js";
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
const sourceManifest = await loadManifestFromRoot(sourceBundleRoot);
const bundleRoot = await prepareBundleWorkspace(sourceManifest, sourceBundleRoot);
const { runProcess, terminateAllProcesses } = createProcessManager({ maxOutputBytes, maxErrorBytes });
let isShuttingDown = false;
const routes = {
    "/": (response, headOnly) => staticFile(path.join(webuiRoot, "index.html"), "text/html; charset=utf-8", response, headOnly),
    "/index.html": (response, headOnly) => staticFile(path.join(webuiRoot, "index.html"), "text/html; charset=utf-8", response, headOnly),
    "/favicon.ico": (response, headOnly) => serveBundleFavicon(response, headOnly, bundleRoot),
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
            await json(response, await loadLocalizedBundle(locale, repoRoot, bundleRoot, sourceBundleRoot));
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
    const exitCode = reason === "SIGINT" ? 130 : reason === "uncaughtException" ? 1 : 0;
    server.close(() => process.exit(exitCode));
    setTimeout(() => process.exit(exitCode), 500).unref();
}
