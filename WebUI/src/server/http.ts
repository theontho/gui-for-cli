import { createReadStream } from "node:fs";
import { stat } from "node:fs/promises";
import path from "node:path";
export async function readJSONBody(request, maxBodyBytes) {
    const chunks = [];
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
    const info = await stat(filePath);
    response.writeHead(200, { "content-type": type, "content-length": info.size });
    if (headOnly) {
        response.end();
        return;
    }
    createReadStream(filePath).pipe(response);
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
        ".json": "application/json; charset=utf-8",
    }[extension] ?? "application/octet-stream");
}
