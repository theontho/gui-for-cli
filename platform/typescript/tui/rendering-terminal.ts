import { clamp, limit, statusBadge, styleText, type TUIColorTheme } from "./rendering-format.js";
import type { TUIRenderState, TUITerminalEntry } from "./types.js";

export function renderTerminalLines(state: TUIRenderState, columns: number, maxLines: number, color: TUIColorTheme) {
    const focused = state.focusPane === "terminal";
    const title = focused ? styleText("› Terminal", color, "focus") : styleText("Terminal", color, "section");
    const entries = state.terminalEntries ?? [];
    if (!entries.length) {
        return [`${title} ${styleText("(no commands run yet)", color, "muted")}`];
    }
    const rawSelectedIndex = Number(state.selectedTerminalEntryIndex);
    const selectedIndex = Number.isFinite(rawSelectedIndex) ? clamp(rawSelectedIndex, 0, entries.length - 1) : entries.length - 1;
    state.selectedTerminalEntryIndex = selectedIndex;
    const active = entries[selectedIndex];
    const cancelHint = active.abortController ? ` ${styleText("[x] cancel", color, "key")}` : "";
    const lines = [`${title} ${statusBadge(active.kind ?? "info", color)} ${active.title ?? "command"}${cancelHint}`];
    lines.push(renderTerminalTabs(entries, selectedIndex, columns, color));
    const body = [active.command ? `$ ${active.command}` : "", active.body ?? ""].filter(Boolean).join("\n");
    const bodyLines = body ? body.split(/\r?\n/) : [];
    const bodyHeight = Math.max(0, maxLines - lines.length);
    const maxOffset = Math.max(0, bodyLines.length - bodyHeight);
    const offsetFromBottom = clamp(state.terminalScrollOffset ?? 0, 0, maxOffset);
    state.terminalScrollOffset = offsetFromBottom;
    const end = bodyLines.length - offsetFromBottom;
    const start = Math.max(0, end - bodyHeight);
    const visible = bodyLines.slice(start, end).map((line) => limit(styleText(line, color, "code"), columns));
    if (start > 0 && visible.length) {
        visible[0] = limit(styleText("↑ more output", color, "muted"), columns);
    }
    if (end < bodyLines.length && visible.length) {
        visible[visible.length - 1] = limit(styleText("↓ newer output", color, "muted"), columns);
    }
    lines.push(...visible);
    return lines;
}

function renderTerminalTabs(entries: TUITerminalEntry[], selectedIndex: number, columns: number, color: TUIColorTheme) {
    const tabs = entries.map((entry, index) => {
        const label = `${index + 1}:${entry.title ?? "command"} ${statusBadge(entry.kind ?? "info", color)}`;
        return index === selectedIndex ? styleText(` ${label} `, color, "focus") : styleText(` ${label} `, color, "muted");
    });
    return limit(tabs.join(" "), columns);
}
