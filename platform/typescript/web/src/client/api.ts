export async function api(path, options: Record<string, any> = {}) {
    const response = await fetch(path, {
        method: options.method ?? "GET",
        headers: options.body ? { "content-type": "application/json" } : undefined,
        body: options.body ? JSON.stringify(options.body) : undefined,
        signal: options.signal,
    });
    const text = await response.text();
    let body = null;
    if (text.trim()) {
        try {
            body = JSON.parse(text);
        }
        catch (_error) {
            if (!response.ok) {
                throw new Error(response.statusText || `HTTP ${response.status}`);
            }
            throw new Error(`Expected JSON response from ${path}.`);
        }
    }
    if (!response.ok) {
        const message = body && typeof body === "object" && "error" in body ? body.error : response.statusText || `HTTP ${response.status}`;
        throw new Error(String(message));
    }
    return body ?? {};
}
