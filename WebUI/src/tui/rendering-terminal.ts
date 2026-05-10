import { clamp, limit, statusBadge, styleText, type TUIColorTheme } from "./rendering-format.js";

export function renderTerminalLines(state: Record<string, any>, columns: number, maxLines: number, color: TUIColorTheme) {
    const focused = state.focusPane === "terminal";
    const title = focused ? styleText("› Terminal", color, "focus") : styleText("Terminal", color, "section");
    const entries = state.terminalEntries ?? [];
    if (!entries.length) {
        return [`${title} ${styleText("(no commands run yet)", color, "muted")}`];
    }
    const latest = entries[entries.length - 1];
    const lines = [`${title} ${statusBadge(latest.kind ?? "info", color)} ${latest.title ?? "command"}`];
    const body = [latest.command ? `$ ${latest.command}` : "", latest.body ?? ""].filter(Boolean).join("\n");
    const bodyLines = body ? body.split(/\r?\n/) : [];
    const bodyHeight = Math.max(0, maxLines - 1);
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
