import { watch } from "node:fs";
import type { ServerResponse } from "node:http";
import path from "node:path";

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
                return;
            }
            for (const directory of [path.join(distRoot, "web", "src", "client"), path.join(distRoot, "shared"), webRoot]) {
                try {
                    const watcher = watch(directory, { persistent: false }, (_event, fileName) => {
                        const name = String(fileName ?? "");
                        if (directory === webRoot && !["index.html", "styles.css"].includes(name)) {
                            return;
                        }
                        notifyClients(clients);
                    });
                    process.once("exit", () => watcher.close());
                }
                catch (error) {
                    console.warn(`Could not watch ${directory}: ${error.message}`);
                }
            }
        },
    };
}

function notifyClients(clients) {
    for (const client of [...clients]) {
        client.write("event: reload\ndata: changed\n\n");
    }
}
