import { stat } from "node:fs/promises";
import { contentType, notFound, streamFile } from "./http.js";
import { resolveBundlePath } from "./paths.js";
import { errnoCode } from "./errors.js";
export async function serveBundleFile(response, relativePath, bundleRoot) {
    const filePath = resolveBundlePath(relativePath, bundleRoot);
    let info;
    try {
        info = await stat(filePath);
    }
    catch (error) {
        if (errnoCode(error) === "ENOENT") {
            await notFound(response);
            return;
        }
        throw error;
    }
    if (!info.isFile()) {
        await notFound(response);
        return;
    }
    response.writeHead(200, { "content-type": contentType(filePath), "content-length": info.size });
    streamFile(filePath, response);
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
                streamFile(filePath, response);
                return;
            }
        }
        catch (error) {
            if (errnoCode(error) !== "ENOENT") {
                throw error;
            }
        }
    }
    await notFound(response);
}
