import { renderContentLines, renderSidebarLines, visibleContentLines } from "./rendering-content.js";
import { clamp, fillLines, frameBottom, frameLine, frameSeparator, frameTop, limit, renderHelp, splitLine, styleText, wrap, type TUIColorTheme } from "./rendering-format.js";
import { activePage, clampSelectedItem, type TUIRenderOptions } from "./rendering-model.js";
import { renderTerminalLines } from "./rendering-terminal.js";
import { resolveTerminalTheme } from "./theme.js";

export {
    activePage,
    clampSelectedItem,
    commandContext,
    controlWithDataSource,
    optionTitle,
    selectedIDs,
    selectedItem,
    tuiItemsForPage,
    type TUIItem,
    type TUIRenderOptions,
} from "./rendering-model.js";

export function renderTUIScreen(state: Record<string, any>, size: TUIRenderOptions = {}) {
    clampSelectedItem(state);
    const columns = Math.max(1, Math.floor(size.columns ?? 100));
    const totalRows = Math.max(1, Math.floor(size.rows ?? 32));
    const color = colorTheme(size.color, size.theme ?? state.terminalTheme);
    if (columns < 72 || totalRows < 12) {
        return renderTooSmall(columns, totalRows, color);
    }
    const lines: string[] = [];
    const page = activePage(state);
    const title = state.manifest?.displayName ?? "GUI for CLI";
    lines.push(frameTop(columns, ` GUI for CLI TUI - ${title} `, color));
    lines.push(frameLine(styleText(`Bundle ${state.bundleRootPath ?? ""}`, color, "muted"), columns, color));
    const summaryLimit = totalRows >= 20 ? 2 : totalRows >= 16 ? 1 : 0;
    const summary = wrap(state.manifest?.summary ?? "", columns - 4).slice(0, summaryLimit);
    for (const line of summary) {
        lines.push(frameLine(styleText(line, color, "muted"), columns, color));
    }
    lines.push(frameSeparator(columns, color));
    if (!page) {
        lines.push(frameLine("No pages are available.", columns, color));
        lines.push(frameBottom(columns, color));
        return lines.join("\n");
    }

    const innerWidth = columns - 2;
    const sidebarWidth = clamp(Math.floor(columns * 0.25), 22, 30);
    const contentWidth = innerWidth - sidebarWidth - 1;
    const defaultTerminalHeight = clamp(Math.floor(totalRows * 0.22), 2, 6);
    const maxTerminalHeight = Math.max(2, totalRows - lines.length - 7);
    const terminalHeight = clamp(Number(state.terminalHeightRows ?? defaultTerminalHeight), 2, maxTerminalHeight);
    const bodyHeight = Math.max(3, totalRows - lines.length - terminalHeight - 4);
    const sidebarLines = renderSidebarLines(state, sidebarWidth, bodyHeight, color);
    const contentLines = visibleContentLines(state, renderContentLines(state, contentWidth, color), bodyHeight, color);
    for (let index = 0; index < bodyHeight; index += 1) {
        lines.push(splitLine(sidebarLines[index] ?? "", contentLines[index] ?? "", sidebarWidth, contentWidth, color));
    }

    lines.push(frameSeparator(columns, color));
    for (const line of fillLines(renderTerminalLines(state, columns - 4, terminalHeight, color), terminalHeight)) {
        lines.push(frameLine(line, columns, color));
    }
    lines.push(frameSeparator(columns, color));
    lines.push(frameLine(renderHelp(color, String(state.terminalTheme ?? "auto")), columns, color));
    lines.push(frameBottom(columns, color));
    return lines.slice(0, totalRows).join("\n");
}

function renderTooSmall(columns: number, rows: number, color: TUIColorTheme) {
    const lines = [
        styleText("GUI for CLI TUI", color, "title"),
        styleText("Terminal too small", color, "warning"),
        `Current ${columns}x${rows}; minimum 72x12`,
    ].slice(0, rows).map((line) => limit(line, columns));
    return fillLines(lines, rows).map((line) => limit(line, columns)).join("\n");
}

function colorTheme(color: boolean | undefined, theme: TUIRenderOptions["theme"]): TUIColorTheme {
    if (!color) {
        return false;
    }
    return resolveTerminalTheme(theme);
}
