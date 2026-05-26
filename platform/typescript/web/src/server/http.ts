import { createReadStream } from "node:fs";
import { stat } from "node:fs/promises";
import path from "node:path";
import { errnoCode } from "./errors.js";
export async function readJSONBody(request, maxBodyBytes) {
    const chunks: Buffer[] = [];
    let size = 0;
    for await (const chunk of request) {
        const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
        size += buffer.length;
        if (size > maxBodyBytes) {
            throw new Error("Request body is too large.");
        }
        chunks.push(buffer);
    }
    return chunks.length ? JSON.parse(Buffer.concat(chunks).toString("utf8")) : {};
}
export async function staticFile(filePath, type, response, headOnly = false) {
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
    response.writeHead(200, { "content-type": type, "content-length": info.size });
    if (headOnly) {
        response.end();
        return;
    }
    streamFile(filePath, response);
}
export function streamFile(filePath, response) {
    const stream = createReadStream(filePath);
    stream.on("error", (error) => {
        if (!response.headersSent) {
            response.writeHead(500, { "content-type": "text/plain; charset=utf-8" });
            response.end("Could not read file");
            return;
        }
        response.destroy(error);
    });
    stream.pipe(response);
}
export async function json(response, body, statusCode = 200) {
    response.writeHead(statusCode, { "content-type": "application/json; charset=utf-8" });
    response.end(JSON.stringify(body));
}
export async function notFound(response) {
    response.writeHead(404, { "content-type": "text/plain; charset=utf-8" });
    response.end("Not found");
}
export function contentType(filePath) {
    const extension = path.extname(filePath).toLowerCase();
    return ({
        ".png": "image/png",
        ".jpg": "image/jpeg",
        ".jpeg": "image/jpeg",
        ".gif": "image/gif",
        ".svg": "image/svg+xml",
        ".webp": "image/webp",
        ".ico": "image/x-icon",
        ".css": "text/css; charset=utf-8",
        ".woff": "font/woff",
        ".woff2": "font/woff2",
        ".json": "application/json; charset=utf-8",
    }[extension] ?? "application/octet-stream");
}
