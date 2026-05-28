import { readdirSync, watch } from "node:fs";
import type { FSWatcher } from "node:fs";
import type { ServerResponse } from "node:http";
import { platform } from "node:os";
import path from "node:path";
import { errorMessage } from "./errors.js";

export function createDevReload({ enabled, distRoot, webRoot }) {
    const clients = new Set<ServerResponse>();
    return {
        addClient(response) {
            response.writeHead(200, {
                "content-type": "text/event-stream; charset=utf-8",
                "cache-control": "no-cache",
                connection: "keep-alive",
            });
            response.write("event: ready\ndata: ok\n\n");
            clients.add(response);
            response.on("close", () => clients.delete(response));
        },
        installWatcher() {
            if (!enabled) {
                return () => { };
            }
            const installedWatchers: FSWatcher[] = [];
            for (const directory of [path.join(distRoot, "web", "src", "client"), path.join(distRoot, "shared"), webRoot]) {
                try {
                    const watchers = watchSourceDirectories(directory, directory === webRoot, (fileName) => {
                        const name = String(fileName ?? "");
                        if (directory === webRoot && !["index.html", "styles.css"].includes(name)) {
                            return;
                        }
                        notifyClients(clients);
                    });
                    installedWatchers.push(...watchers);
                }
                catch (error) {
                    console.warn(`Could not watch ${directory}: ${errorMessage(error)}`);
                }
            }
            const close = () => installedWatchers.splice(0).forEach((watcher) => watcher.close());
            process.once("exit", close);
            return close;
        },
    };
}

function watchSourceDirectories(directory, rootOnly, listener) {
    if (rootOnly || !supportsRecursiveWatch()) {
        const directories = rootOnly ? [directory] : recursiveDirectories(directory);
        return directories.map((watchedDirectory) => watch(watchedDirectory, { persistent: false }, (_event, fileName) => listener(fileName)));
    }
    return [watch(directory, { persistent: false, recursive: true }, (_event, fileName) => listener(fileName))];
}

function supportsRecursiveWatch() {
    return platform() === "win32" || platform() === "darwin";
}

function recursiveDirectories(directory) {
    const directories = [directory];
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
        if (entry.isDirectory()) {
            directories.push(...recursiveDirectories(path.join(directory, entry.name)));
        }
    }
    return directories;
}

function notifyClients(clients) {
    for (const client of [...clients]) {
        client.write("event: reload\ndata: changed\n\n");
    }
}
