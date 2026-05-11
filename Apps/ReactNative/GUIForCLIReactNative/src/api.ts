const DEFAULT_API_BASE = 'http://127.0.0.1:8787';

function normalizedApiBase(): string {
  const value =
    process.env.GUI_FOR_CLI_REACT_NATIVE_API_BASE ?? DEFAULT_API_BASE;
  return value.replace(/\/+$/, '');
}

export function apiBase(): string {
  return normalizedApiBase();
}

export async function api(
  path: string,
  options: {
    method?: string;
    body?: Record<string, unknown>;
    signal?: AbortSignal;
  } = {},
): Promise<any> {
  const response = await fetch(`${normalizedApiBase()}${path}`, {
    method: options.method ?? 'GET',
    headers: options.body ? {'content-type': 'application/json'} : undefined,
    body: options.body ? JSON.stringify(options.body) : undefined,
    signal: options.signal,
  });
  const text = await response.text();
  const body = text.trim() ? JSON.parse(text) : {};
  if (!response.ok) {
    throw new Error(body.error ?? response.statusText ?? `HTTP ${response.status}`);
  }
  return body;
}
