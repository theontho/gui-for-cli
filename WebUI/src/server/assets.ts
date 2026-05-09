import { createReadStream } from "node:fs";
import { stat } from "node:fs/promises";
import { contentType, notFound } from "./http.js";
import { resolveBundlePath } from "./paths.js";
export async function serveBundleFile(response, relativePath, bundleRoot) {
    const filePath = resolveBundlePath(relativePath, bundleRoot);
    const info = await stat(filePath);
    if (!info.isFile()) {
        await notFound(response);
        return;
    }
    response.writeHead(200, { "content-type": contentType(filePath) });
    createReadStream(filePath).pipe(response);
}
export async function serveBundleFavicon(response, headOnly, bundleRoot) {
    for (const relativePath of ["Assets/favicon.ico", "favicon.ico", "Assets/icon.png"]) {
        try {
            const filePath = resolveBundlePath(relativePath, bundleRoot);
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
        }
        catch (error) {
            if (error.code !== "ENOENT") {
                throw error;
            }
        }
    }
    await notFound(response);
}
