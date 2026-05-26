import { disabledReason, displayCommand, hydrateRows, isActionVisible, missingPlaceholders, rowContext } from "../shared/rendering.js";
import {
    actionButton,
    cardHeader,
    checkbox,
    clamp,
    ensureVisibleOffset,
    fieldRow,
    fillLines,
    limit,
    selectableLine,
    selectedPill,
    statusBadge,
    statusPill,
    stripANSI,
    styleText,
    type TUIColorTheme,
    wrap,
} from "./rendering-format.js";
import {
    activePage,
    commandContext,
    controlWithDataSource,
    fieldValue,
    configValueKey,
    optionTitle,
    selectedIDs,
    tuiItemsForPage,
    type TUIItem,
} from "./rendering-model.js";
import type { TUIAction, TUICommandContext, TUIControl, TUIPage, TUIRenderState, TUISection } from "./types.js";

export function renderSidebarLines(state: TUIRenderState, width: number, height: number, color: TUIColorTheme) {
    const pages = state.manifest?.pages ?? [];
    const header = [
        styleText("BUNDLE", color, "section"),
        styleText(state.manifest?.displayName ?? "GUI for CLI", color, "strong"),
        styleText("PAGES", color, "section"),
    ];
    const status = [
        styleText("STATUS", color, "section"),
        `  Setup ${statusBadge(state.setupRun?.status ?? state.bundleState?.setupRun?.status ?? "pending", color)}  Items ${styleText(String(tuiItemsForPage(state).length), color, "accent")}`,
    ];
    const available = Math.max(1, height - header.length - status.length);
    const entries: string[] = [];
    const activeEntryIndexes: number[] = [];
    let currentGroup = "";
    for (const page of pages) {
        const group = page.sidebarGroup ?? "";
        if (group && group !== currentGroup) {
            currentGroup = group;
            entries.push(styleText(group.toUpperCase(), color, "section"));
        }
        const active = page.id === state.activePageID;
        const icon = page.textIcon ?? state.iconMap?.emoji?.[page.iconName] ?? "◦";
        const label = `${icon} ${page.title ?? page.id}`;
        if (active) {
            activeEntryIndexes.push(entries.length);
        }
        entries.push(active ? selectedPill(label, width, color) : `  ${styleText(label, color, "muted")}`);
    }
    const activeIndex = activeEntryIndexes[0] ?? 0;
    const maxOffset = Math.max(0, entries.length - available);
    const currentOffset = clamp(state.sidebarScrollOffset ?? 0, 0, maxOffset);
    const offset = ensureVisibleOffset(currentOffset, activeIndex, available, maxOffset);
    state.sidebarScrollOffset = offset;
    const clippedEntries = entries.slice(offset, offset + available);
    if (offset > 0 && clippedEntries.length) {
        clippedEntries[0] = styleText("↑ more", color, "muted");
    }
    if (offset < maxOffset && clippedEntries.length) {
        clippedEntries[clippedEntries.length - 1] = styleText("↓ more", color, "muted");
    }
    return fillLines([...header, ...clippedEntries, ...status].map((line) => limit(line, width)), height);
}

export function renderContentLines(state: TUIRenderState, width: number, color: TUIColorTheme) {
    const page = activePage(state);
    if (!page) {
        return ["No page selected."];
    }
    const items = tuiItemsForPage(state);
    const selected = state.selectedItemIndex ?? 0;
    const pageTitle = page.title ?? page.id;
    const pageID = String(page.id ?? "");
    const pageIDHint = pageID && pageID.toLowerCase() !== String(pageTitle).toLowerCase() ? ` ${styleText(`#${pageID}`, color, "muted")}` : "";
    const lines = [
        `${styleText(pageTitle, color, "title")}${pageIDHint}`,
        ...wrap(page.summary ?? "", width).map((line) => styleText(line, color, "muted")),
        "",
    ];
    lines.push(...renderSetupLines(state, page, selected, items, width, color));
    for (const section of page.sections ?? []) {
        lines.push(...renderSectionLines(state, section, selected, items, width, color));
    }
    return lines.map((line) => limit(line, width));
}

export function visibleContentLines(state: TUIRenderState, lines: string[], height: number, color: TUIColorTheme) {
    const selectedLine = lines.findIndex((line) => stripANSI(line).trimStart().startsWith("›"));
    const maxOffset = Math.max(0, lines.length - height);
    const currentOffset = clamp(state.contentScrollOffset ?? 0, 0, maxOffset);
    const target = selectedLine >= 0 ? selectedLine : currentOffset;
    const offset = ensureVisibleOffset(currentOffset, target, height, maxOffset);
    state.contentScrollOffset = offset;
    const visible = lines.slice(offset, offset + height);
    if (offset > 0 && visible.length) {
        visible[0] = styleText("↑ more", color, "muted");
    }
    if (offset < maxOffset && visible.length) {
        visible[visible.length - 1] = styleText("↓ more", color, "muted");
    }
    return fillLines(visible, height);
}

function renderSetupLines(state: TUIRenderState, page: TUIPage, selected: number, items: TUIItem[], columns: number, color: TUIColorTheme) {
    if (page.id !== "settings" || !(state.manifest?.setup?.steps ?? []).length) {
        return [];
    }
    const itemIndex = items.findIndex((item) => item.key === "setup");
    const setupRun = state.setupRun ?? state.bundleState?.setupRun;
    const status = setupRun?.status ?? "not run";
    return [
        selectableLine(itemIndex, selected, `Setup ${statusBadge(status, color)}`, columns, color),
        ...((state.manifest.setup.steps ?? []).map((step) => {
            const result = setupRun?.results?.find((candidate) => candidate.id === step.id);
            return limit(`  ${styleText("•", color, "muted")} ${step.label ?? step.id} ${statusBadge(result?.status ?? "pending", color)}`, columns);
        })),
        "",
    ];
}

function renderSectionLines(state: TUIRenderState, section: TUISection, selected: number, items: TUIItem[], columns: number, color: TUIColorTheme) {
    const lines: string[] = [];
    const sectionValues = state.dataSourcePayloads?.get(`section:${section.id}`)?.values ?? {};
    const context = commandContext(state, {}, sectionValues);
    if (section.title) {
        lines.push(cardHeader(section.title, columns, color));
    }
    if (section.subtitle || section.summary) {
        lines.push(...wrap(section.subtitle ?? section.summary, columns - 2).map((line) => `  ${styleText(line, color, "muted")}`));
    }
    const sectionError = state.dataSourceErrors?.get(`section:${section.id}`);
    if (sectionError) {
        lines.push(limit(`  ${styleText("Data source error:", color, "danger")} ${sectionError}`, columns));
    }
    for (const rawControl of section.controls ?? []) {
        const control = controlWithDataSource(state, rawControl);
        lines.push(...renderControlLines(state, control, context, selected, items, columns, color));
        const controlError = state.dataSourceErrors?.get(`control:${control.id}`);
        if (controlError) {
            lines.push(limit(`  ${styleText("Data source error:", color, "danger")} ${controlError}`, columns));
        }
    }
    for (const action of section.actions ?? []) {
        if (isActionVisible(action, context)) {
            lines.push(renderActionLine(state, action, context, selected, items, columns, color, `action:${section.id}:${action.id}`));
        }
    }
    if (section.title || (section.controls ?? []).length || (section.actions ?? []).length) {
        lines.push("");
    }
    return lines;
}

function renderControlLines(
    state: TUIRenderState,
    control: TUIControl,
    context: TUICommandContext,
    selected: number,
    items: TUIItem[],
    columns: number,
    color: TUIColorTheme,
) {
    if (control.kind === "configEditor") {
        return renderConfigEditorLines(state, control, selected, items, columns, color);
    }
    const itemIndex = items.findIndex((item) => item.key === `control:${control.id}`);
    const label = control.label ?? control.id;
    switch (control.kind) {
        case "text":
        case "path":
            return [selectableLine(itemIndex, selected, fieldRow(label, stateText(fieldValue(state, control)), color), columns, color)];
        case "dropdown": {
            const value = fieldValue(state, control);
            const option = (control.options ?? []).find((candidate) => candidate.id === value) ?? (control.options ?? [])[0];
            return [selectableLine(itemIndex, selected, fieldRow(label, option ? optionTitle(option, state.labels) : "", color), columns, color)];
        }
        case "toggle":
            return [selectableLine(itemIndex, selected, `${label} ${checkbox(fieldValue(state, control) === "true", color)}`, columns, color)];
        case "checkboxGroup": {
            const selectedOptions = new Set(selectedIDs(state.checkedOptions?.[control.id]));
            const titles = (control.options ?? [])
                .filter((option) => selectedOptions.has(option.id))
                .map((option) => optionTitle(option, state.labels));
            return [selectableLine(itemIndex, selected, fieldRow(label, titles.length ? titles.join(", ") : "(none)", color), columns, color)];
        }
        case "infoGrid":
            return [limit(`  ${styleText(label, color, "strong")} ${(control.options ?? []).map((option) => statusPill(optionTitle(option, state.labels), color)).join(" ")}`, columns)];
        case "libraryList":
            return renderLibraryListLines(state, control, context, selected, items, columns, color, itemIndex);
        default:
            return [selectableLine(itemIndex, selected, `${label}: unsupported control kind ${control.kind}`, columns, color)];
    }
}

function renderConfigEditorLines(state: TUIRenderState, control: TUIControl, selected: number, items: TUIItem[], columns: number, color: TUIColorTheme) {
    const lines = [limit(`  ${styleText(control.label ?? control.id, color, "strong")}`, columns)];
    for (const setting of control.settings ?? []) {
        const itemIndex = items.findIndex((item) => item.key === `config:${control.id}:${setting.id}`);
        const value = state.configValues?.[configValueKey(control, setting)] ?? setting.value ?? "";
        if (setting.kind === "dropdown") {
            const option = (setting.options ?? []).find((candidate) => candidate.id === value) ?? (setting.options ?? [])[0];
            lines.push(selectableLine(itemIndex, selected, fieldRow(setting.label ?? setting.id, option ? optionTitle(option, state.labels) : "", color), columns, color));
        } else {
            lines.push(selectableLine(itemIndex, selected, fieldRow(setting.label ?? setting.id, stateText(value), color), columns, color));
        }
    }
    return lines;
}

function renderLibraryListLines(
    state: TUIRenderState,
    control: TUIControl,
    context: TUICommandContext,
    selected: number,
    items: TUIItem[],
    columns: number,
    color: TUIColorTheme,
    itemIndex: number,
) {
    const rows = hydrateRows(control);
    const lines = [selectableLine(itemIndex, selected, `${control.label ?? control.id} ${statusPill(`${rows.length} rows`, color)}`, columns, color)];
    const selectedKey = items[selected]?.key ?? "";
    const selectedRowID = rows.find((row) =>
        (control.rowActions ?? []).some((action) => selectedKey === `action:${control.id}:${row.id}:${action.id}`)
    )?.id;
    const selectedRowIndex = Math.max(0, rows.findIndex((row) => row.id === selectedRowID));
    const maxRows = 8;
    const rowOffset = clamp(selectedRowIndex - 3, 0, Math.max(0, rows.length - maxRows));
    const visibleRows = rows.slice(rowOffset, rowOffset + maxRows);
    if (rowOffset > 0) {
        lines.push(styleText("  ↑ more rows", color, "muted"));
    }
    for (const row of visibleRows) {
        const values = control.columns?.length
            ? control.columns.map((column) => row.values?.[column.id] ?? "").filter(Boolean).join(" | ")
            : row.title ?? row.id;
        const status = row.status ? ` ${statusBadge(row.status, color)}` : "";
        lines.push(limit(`  ${styleText("•", color, "muted")} ${styleText(row.title ?? row.id, color, "strong")}${status}${values ? ` ${styleText(values, color, "muted")}` : ""}`, columns));
        const rowActionContext = rowContext(context, row);
        for (const action of control.rowActions ?? []) {
            if (isActionVisible(action, rowActionContext)) {
                lines.push(renderActionLine(state, action, rowActionContext, selected, items, columns, color, `action:${control.id}:${row.id}:${action.id}`, `    ${row.title ?? row.id}: `));
            }
        }
    }
    if (rowOffset + visibleRows.length < rows.length) {
        lines.push(styleText(`  ↓ ${rows.length - rowOffset - visibleRows.length} more rows`, color, "muted"));
    }
    return lines;
}

function renderActionLine(
    state: TUIRenderState,
    action: TUIAction,
    context: TUICommandContext,
    selected: number,
    items: TUIItem[],
    columns: number,
    color: TUIColorTheme,
    key: string,
    prefix = "",
) {
    const itemIndex = items.findIndex((item) => item.key === key);
    const missing = action.command ? missingPlaceholders(action.command, context) : [];
    const disabled = missing.length
        ? state.labels?.actionMissingInputsFormat?.replace("%{inputs}", missing.join(", ")) ?? `Missing: ${missing.join(", ")}`
        : disabledReason(action, context, state.labels?.actionDisabledFallback ?? "This action is not available.");
    const command = action.command ? ` ${styleText(displayCommand(action.command, context), color, "code")}` : "";
    const suffix = disabled ? ` ${styleText(`[disabled: ${disabled}]`, color, "muted")}` : command;
    return selectableLine(itemIndex, selected, `${prefix}${actionButton(action, color)}${suffix}`, columns, color);
}

function stateText(value: unknown) {
    return value == null ? "" : String(value);
}
