import { readdirSync, statSync } from "node:fs";
import { homedir } from "node:os";
import path from "node:path";
import type { TUILabels, TUIOption } from "./types.js";

export function pathCompletions(input: string, cwd = process.cwd()) {
    const raw = String(input ?? "");
    const expanded = expandHome(raw);
    const separatorIndex = Math.max(raw.lastIndexOf("/"), raw.lastIndexOf("\\"));
    const rawPrefix = separatorIndex >= 0 ? raw.slice(0, separatorIndex + 1) : "";
    const base = separatorIndex >= 0 ? raw.slice(separatorIndex + 1) : raw;
    const expandedDir = expanded.endsWith("/") || expanded.endsWith("\\") ? expanded : path.dirname(expanded);
    const lookupDir = path.isAbsolute(expandedDir) ? expandedDir : path.resolve(cwd, expandedDir);
    let entries: string[];
    try {
        entries = readdirSync(lookupDir);
    } catch {
        return [];
    }
    const lowerBase = base.toLowerCase();
    return entries
        .filter((entry) => entry.toLowerCase().startsWith(lowerBase))
        .sort((left, right) => left.localeCompare(right))
        .slice(0, 100)
        .map((entry) => {
            const resolved = path.join(lookupDir, entry);
            return `${rawPrefix}${entry}${isDirectory(resolved) ? "/" : ""}`;
        });
}

export function pathCompleter(cwd = process.cwd()): (line: string) => [string[], string] {
    return (line: string) => [pathCompletions(line, cwd), line];
}

export function optionCompletions(input: string, options: TUIOption[], labels: TUILabels = {}) {
    const query = normalize(input);
    const candidates = options.map((option) => ({ option, key: optionSearchText(option, labels), id: String(option.id ?? "") }));
    const prefixMatches = candidates.filter(({ option, id }) => !query || normalize(id).startsWith(query) || normalize(optionLabel(option, labels)).startsWith(query));
    const matches = prefixMatches.length ? prefixMatches : candidates.filter(({ key }) => key.includes(query));
    return matches
        .sort((left, right) => {
            const leftID = normalize(left.id).startsWith(query) ? 0 : 1;
            const rightID = normalize(right.id).startsWith(query) ? 0 : 1;
            return leftID - rightID || optionLabel(left.option, labels).localeCompare(optionLabel(right.option, labels));
        })
        .slice(0, 100)
        .map(({ option }) => String(option.id ?? option.title ?? ""));
}

export function optionCompleter(options: TUIOption[], labels: TUILabels = {}): (line: string) => [string[], string] {
    return (line: string) => [optionCompletions(line, options, labels), line];
}

export function resolveOptionInput(input: string, options: TUIOption[], current?: string, labels: TUILabels = {}, fallbackToCurrent = true) {
    const text = String(input ?? "").trim();
    if (!text) {
        return options.find((option) => option.id === current) ?? options[0];
    }
    const numericIndex = Number(text) - 1;
    if (Number.isInteger(numericIndex) && options[numericIndex]) {
        return options[numericIndex];
    }
    const normalized = normalize(text);
    const exact = options.find((option) => normalize(option.id) === normalized || normalize(optionLabel(option, labels)) === normalized);
    if (exact) {
        return exact;
    }
    const prefixMatches = options.filter((option) => normalize(option.id).startsWith(normalized) || normalize(optionLabel(option, labels)).startsWith(normalized));
    if (prefixMatches.length === 1) {
        return prefixMatches[0];
    }
    const fuzzyMatches = options.filter((option) => optionSearchText(option, labels).includes(normalized));
    if (fuzzyMatches.length === 1) {
        return fuzzyMatches[0];
    }
    return fallbackToCurrent ? options.find((option) => option.id === current) ?? options[0] : undefined;
}

export function resolveMultiOptionInput(input: string, options: TUIOption[], currentIDs: string[], labels: TUILabels = {}) {
    const text = String(input ?? "").trim();
    if (!text) {
        return [...currentIDs];
    }
    const tokens = text.split(",").map((token) => token.trim()).filter(Boolean);
    const patchMode = tokens.some((token) => token.startsWith("+") || token.startsWith("-"));
    const selected = new Set(patchMode ? currentIDs : []);
    for (const token of tokens) {
        const remove = token.startsWith("-");
        const raw = token.replace(/^[+-]/, "");
        const option = resolveOptionInput(raw, options, undefined, labels, false);
        if (!option?.id) {
            continue;
        }
        if (remove) {
            selected.delete(option.id);
        } else {
            selected.add(option.id);
        }
    }
    return [...selected];
}

function optionSearchText(option: TUIOption, labels: TUILabels) {
    return normalize([option.id, optionLabel(option, labels), option.status, option.group].filter(Boolean).join(" "));
}

function optionLabel(option: TUIOption, labels: TUILabels) {
    const status = option.status ? ` ${labels.libraryStatusLabels?.[String(option.status).toLowerCase()] ?? option.status}` : "";
    return `${option.title ?? option.id}${status}`;
}

function expandHome(value: string) {
    return value.replace(/^~(?=\/|\\|$)/, homedir());
}

function isDirectory(value: string) {
    try {
        return statSync(value).isDirectory();
    } catch {
        return false;
    }
}

function normalize(value: unknown) {
    return String(value ?? "").trim().toLowerCase();
}
