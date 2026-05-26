import type { StringMap } from "./types.js";

export function serializeFlatToml(values: Record<string, unknown>): string {
    return `${Object.entries(values)
        .sort(([left], [right]) => left.localeCompare(right))
        .map(([key, value]) => `${tomlKey(key)} = ${tomlValue(value)}`)
        .join("\n")}\n`;
}
export function parseFlatToml(text: string): StringMap {
    const values: StringMap = Object.create(null);
    for (const rawLine of text.split(/\r?\n/)) {
        const line = rawLine.trim();
        if (!line || line.startsWith("#") || !line.includes("=")) {
            continue;
        }
        const separator = assignmentSeparator(line);
        if (separator < 0) {
            continue;
        }
        const rawKey = line.slice(0, separator).trim();
        const rawValue = line.slice(separator + 1).trim();
        const key = rawKey.startsWith('"') ? parseTomlValue(rawKey) : rawKey;
        values[key] = parseTomlValue(rawValue);
    }
    return values;
}
function assignmentSeparator(line: string): number {
    let inQuotes = false;
    let escaped = false;
    for (let index = 0; index < line.length; index += 1) {
        const character = line[index];
        if (escaped) {
            escaped = false;
            continue;
        }
        if (character === "\\" && inQuotes) {
            escaped = true;
            continue;
        }
        if (character === '"') {
            inQuotes = !inQuotes;
            continue;
        }
        if (character === "=" && !inQuotes) {
            return index;
        }
    }
    return -1;
}

function tomlKey(key: string): string {
    return /^[A-Za-z0-9_-]+$/.test(key) ? key : tomlValue(key);
}
function tomlValue(value: unknown): string {
    return `"${String(value ?? "")
        .replaceAll("\\", "\\\\")
        .replaceAll('"', '\\"')
        .replaceAll("\n", "\\n")}"`;
}
function parseTomlValue(value: string): string {
    if (!value.startsWith('"') || !value.endsWith('"')) {
        return value;
    }
    return value
        .slice(1, -1)
        .replace(/\\([nrt"\\])/g, (_, escaped) => ({ n: "\n", r: "\r", t: "\t", '"': '"', "\\": "\\" })[escaped] ?? escaped);
}
