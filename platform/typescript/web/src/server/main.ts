#!/usr/bin/env node
import { writeFile } from "node:fs/promises";
import { createServer } from "node:http";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createOneShotBundlePreload, loadLocalizedBundle, loadManifestFromRoot } from "./bundle-loader.js";
import { createDevReload } from "./dev-reload.js";
import { createShutdownController } from "./lifecycle.js";
import { parseArgs } from "./paths.js";
import { createProcessManager } from "./process-runner.js";
import { createRequestHandler } from "./routes.js";
import { prepareBundleWorkspace } from "./workspace.js";

const serverDir = path.dirname(fileURLToPath(import.meta.url));
const distRoot = path.resolve(serverDir, "../../..");
const packageRoot = path.resolve(distRoot, "..");
const webRoot = path.join(packageRoot, "web");
const repoRoot = path.resolve(packageRoot, "../..");
const args = parseArgs(process.argv.slice(2));
const sourceBundleRoot = path.resolve(args.bundle ?? path.join(repoRoot, "examples", "WGSExtract"));
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
const localizedBundleLoader = createOneShotBundlePreload(
    (locale) => loadLocalizedBundle(locale, repoRoot, bundleRoot, sourceBundleRoot),
    defaultLocale,
    Boolean(args.bundle),
);
let server;
const shutdownController = createShutdownController({
    getServer: () => server,
    terminateAllProcesses,
});
const devReload = createDevReload({ enabled: enableDevReload, distRoot, webRoot });

shutdownController.installParentMonitor();
shutdownController.installShutdownHandlers();

server = createServer(createRequestHandler({
    addDevReloadClient: devReload.addClient,
    bundleRoot,
    defaultLocale,
    distRoot,
    enableDevReload,
    localizedBundleLoader,
    maxBodyBytes,
    repoRoot,
    runProcess,
    shutdown: shutdownController.shutdown,
    webRoot,
}));

server.listen(port, host, () => {
    const address = server?.address();
    const boundPort = typeof address === "object" && address ? address.port : port;
    console.log(`GUI for CLI Web UI: http://${host}:${boundPort}/`);
    console.log(`Bundle source: ${sourceBundleRoot}`);
    console.log(`Bundle workspace: ${bundleRoot}`);
    if (process.env.GFC_PORT_FILE) {
        writeFile(process.env.GFC_PORT_FILE, `${boundPort}\n`).catch((error) => {
            console.error(`Could not write GFC_PORT_FILE: ${error.message}`);
            shutdownController.shutdown("portFileError");
        });
    }
});

devReload.installWatcher();
