import { clamp, limit, statusBadge, styleText } from "./rendering-format.js";

export function renderTerminalLines(state: Record<string, any>, columns: number, maxLines: number, color: boolean) {
    const focused = state.focusPane === "terminal";
    const title = focused ? styleText("› Terminal", color, "focus") : styleText("Terminal", color, "section");
    const entries = state.terminalEntries ?? [];
    if (!entries.length) {
        return [`${title} ${styleText("(no commands run yet)", color, "muted")}`];
    }
    const latest = entries[entries.length - 1];
    const lines = [`${title} ${statusBadge(latest.kind ?? "info", color)} ${latest.title ?? "command"}`];
    const body = [latest.command ? `$ ${latest.command}` : "", latest.body ?? ""].filter(Boolean).join("\n");
    const bodyLines = body.split(/\r?\n/).filter(Boolean);
    const bodyHeight = Math.max(0, maxLines - 1);
    const maxOffset = Math.max(0, bodyLines.length - bodyHeight);
    const offsetFromBottom = clamp(state.terminalScrollOffset ?? 0, 0, maxOffset);
    state.terminalScrollOffset = offsetFromBottom;
    const end = bodyLines.length - offsetFromBottom;
    const start = Math.max(0, end - bodyHeight);
    const visible = bodyLines.slice(start, end).map((line) => limit(styleText(line, color, "code"), columns));
    if (start > 0 && visible.length) {
        visible[0] = styleText("↑ more output", color, "muted");
    }
    if (end < bodyLines.length && visible.length) {
        visible[visible.length - 1] = styleText("↓ newer output", color, "muted");
    }
    lines.push(...visible);
    return lines;
}
