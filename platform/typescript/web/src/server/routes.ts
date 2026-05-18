import path from "node:path";
import { fileStateValues, runAction, runDataSource, evaluatePrecheck } from "./action-runner.js";
import { serveBundleFavicon, serveBundleFile } from "./assets.js";
import { loadLocaleOptions } from "./bundle-loader.js";
import { loadConfig, saveBundleState, saveConfig } from "./config-store.js";
import { contentType, json, notFound, readJSONBody, staticFile } from "./http.js";
import { distModulePath, normalizeContext } from "./paths.js";
import { pickPath } from "./path-picker.js";
import { runSetup } from "./setup-runner.js";

export function createRequestHandler(context) {
    const staticRoutes = {
        "/": (response, headOnly) => staticFile(path.join(context.webRoot, "index.html"), "text/html; charset=utf-8", response, headOnly),
        "/index.html": (response, headOnly) => staticFile(path.join(context.webRoot, "index.html"), "text/html; charset=utf-8", response, headOnly),
        "/favicon.ico": (response, headOnly) => serveBundleFavicon(response, headOnly, context.bundleRoot),
        "/client/app.js": (response, headOnly) => staticFile(path.join(context.distRoot, "web", "src", "client", "app.js"), "text/javascript; charset=utf-8", response, headOnly),
        "/styles.css": (response, headOnly) => staticFile(path.join(context.webRoot, "styles.css"), "text/css; charset=utf-8", response, headOnly),
    };
    return async (request, response) => {
        try {
            const url = new URL(request.url ?? "/", `http://${request.headers.host ?? "localhost"}`);
            if ((request.method === "GET" || request.method === "HEAD") && staticRoutes[url.pathname]) {
                await staticRoutes[url.pathname](response, request.method === "HEAD");
                return;
            }
            if (request.method === "GET" && url.pathname === "/api/dev/reload" && context.enableDevReload) {
                context.addDevReloadClient(response);
                return;
            }
            if (await maybeServeAsset(url, request.method, response, context)) {
                return;
            }
            if (await maybeHandleGetApi(url, request.method, response, context)) {
                return;
            }
            if (await maybeHandlePostApi(url, request, response, context)) {
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
    };
}

async function maybeServeAsset(url, method, response, context) {
    const vendorFilePath = webuiVendorAssetPath(url.pathname, context.webRoot);
    if ((method === "GET" || method === "HEAD") && vendorFilePath) {
        await staticFile(vendorFilePath, contentType(vendorFilePath), response, method === "HEAD");
        return true;
    }
    const compiledModulePath = distModulePath(url.pathname, context.distRoot);
    if ((method === "GET" || method === "HEAD") && compiledModulePath) {
        await staticFile(compiledModulePath, "text/javascript; charset=utf-8", response, method === "HEAD");
        return true;
    }
    return false;
}

async function maybeHandleGetApi(url, method, response, context) {
    if (method === "GET" && url.pathname === "/api/locales") {
        await json(response, await loadLocaleOptions(context.repoRoot, context.bundleRoot));
        return true;
    }
    if (method === "GET" && url.pathname === "/api/manifest") {
        const locale = url.searchParams.get("locale") || context.defaultLocale;
        await json(response, await context.localizedBundleLoader.load(locale));
        return true;
    }
    if (method === "GET" && url.pathname === "/api/file") {
        await serveBundleFile(response, url.searchParams.get("path") ?? "", context.bundleRoot);
        return true;
    }
    return false;
}

async function maybeHandlePostApi(url, request, response, context) {
    if (request.method !== "POST") {
        return false;
    }
    switch (url.pathname) {
        case "/api/datasource":
            return handleJSONRequest(request, response, context, async (body) => runDataSource(body.dataSource, normalizeContext(body.context, context.bundleRoot), context.bundleRoot, context.runProcess));
        case "/api/run":
            return handleRunAction(request, response, context);
        case "/api/precheck":
            return handleJSONRequest(request, response, context, async (body) => evaluatePrecheck(body.precheck, normalizeContext(body.context, context.bundleRoot), body.labels ?? {}, context.bundleRoot, context.runProcess));
        case "/api/file-state":
            return handleJSONRequest(request, response, context, async (body) => ({ values: await fileStateValues(normalizeContext(body.context, context.bundleRoot), context.bundleRoot) }));
        case "/api/setup/stream":
            return handleSetupStream(request, response, context);
        case "/api/path/pick":
            return handleJSONRequest(request, response, context, async (body) => pickPath({ ...body, bundleRoot: context.bundleRoot }));
        case "/api/shutdown":
            await json(response, { ok: true });
            setTimeout(() => context.shutdown("apiShutdown"), 0).unref();
            return true;
        case "/api/open-bundle-workspace":
            await openPath(context.bundleRoot, context.bundleRoot, context.runProcess);
            await json(response, { ok: true });
            return true;
        case "/api/config/load":
            return handleJSONRequest(request, response, context, async (body) => loadConfig(body.control, body.path, context.bundleRoot));
        case "/api/config/save":
            return handleJSONRequest(request, response, context, async (body) => saveConfig(body.control, body.path, body.values ?? {}, context.bundleRoot));
        case "/api/state/save":
            return handleJSONRequest(request, response, context, async (body) => saveBundleState(body.state ?? {}, context.bundleRoot));
        default:
            return false;
    }
}

async function handleJSONRequest(request, response, context, handler) {
    const body = await readJSONBody(request, context.maxBodyBytes);
    await json(response, await handler(body));
    return true;
}

async function handleRunAction(request, response, context) {
    const body = await readJSONBody(request, context.maxBodyBytes);
    const abortController = new AbortController();
    const abort = () => abortController.abort();
    request.on("aborted", abort);
    response.on("close", () => {
        if (!response.writableEnded) {
            abort();
        }
    });
    const result = await runAction(body.action, normalizeContext(body.context, context.bundleRoot), abortController.signal, context.bundleRoot, context.runProcess);
    await json(response, result);
    return true;
}

async function handleSetupStream(request, response, context) {
    const body = await readJSONBody(request, context.maxBodyBytes);
    const bundle = await context.localizedBundleLoader.load(body.locale || context.defaultLocale);
    response.writeHead(200, { "content-type": "application/x-ndjson; charset=utf-8" });
    await runSetup(bundle.manifest, context.bundleRoot, context.runProcess, (event) => {
        response.write(`${JSON.stringify(event)}\n`);
    });
    response.end();
    return true;
}

function webuiVendorAssetPath(pathname, webRoot) {
    const prefix = "/vendor/bootstrap-icons/";
    if (!pathname.startsWith(prefix)) {
        return undefined;
    }
    const vendorRoot = path.resolve(webRoot, "vendor", "bootstrap-icons");
    const filePath = path.resolve(vendorRoot, pathname.slice(prefix.length));
    if (filePath === vendorRoot) {
        return undefined;
    }
    return filePath.startsWith(`${vendorRoot}${path.sep}`) ? filePath : undefined;
}

async function openPath(filePath, workingDirectory, runProcess) {
    if (process.platform === "win32") {
        await runProcess("explorer.exe", [filePath], { cwd: workingDirectory, env: process.env });
        return;
    }
    if (process.platform === "darwin") {
        await runProcess("/usr/bin/open", [filePath], { cwd: workingDirectory, env: process.env });
        return;
    }
    await runProcess("xdg-open", [filePath], { cwd: workingDirectory, env: process.env });
}
