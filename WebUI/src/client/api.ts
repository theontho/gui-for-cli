export async function api(path, options: Record<string, any> = {}) {
    const response = await fetch(path, {
        method: options.method ?? "GET",
        headers: options.body ? { "content-type": "application/json" } : undefined,
        body: options.body ? JSON.stringify(options.body) : undefined,
        signal: options.signal,
    });
    const body = await response.json();
    if (!response.ok) {
        throw new Error(body.error ?? response.statusText);
    }
    return body;
}
