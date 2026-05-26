type ApiOptions = {
    method?: string;
    body?: unknown;
    signal?: AbortSignal;
};

export async function api<T = unknown>(path: string, options: ApiOptions = {}): Promise<T> {
    const init: RequestInit = {
        method: options.method ?? "GET",
        ...(options.body ? { headers: { "content-type": "application/json" }, body: JSON.stringify(options.body) } : {}),
        ...(options.signal ? { signal: options.signal } : {}),
    };
    const response = await fetch(path, init);
    const text = await response.text();
    let body: unknown = null;
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
    return (body ?? {}) as T;
}
