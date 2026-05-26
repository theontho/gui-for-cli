import {
    applyDataSourcePayload,
    commandContextFromState,
    configValueKey,
    hydrateRows,
    isActionVisible,
    normalizeSelectedIDs,
    optionTitle as sharedOptionTitle,
    rowContext,
} from "../shared/rendering.js";
import type { ValueMap } from "../shared/types.js";
import { clamp, type TUIColorTheme } from "./rendering-format.js";
import type { TUIThemePreference } from "./theme.js";
import type { TUIAction, TUICommandContext, TUIConfigSetting, TUIControl, TUILabels, TUIOption, TUIRenderState, TUISection } from "./types.js";

export type TUIItem =
    | { kind: "setup"; key: string; label: string }
    | { kind: "control"; key: string; control: TUIControl; section: TUISection; label: string }
    | { kind: "configSetting"; key: string; control: TUIControl; setting: TUIConfigSetting; label: string }
    | { kind: "action"; key: string; action: TUIAction; context: TUICommandContext; label: string };

export type TUIRenderOptions = {
    columns?: number;
    rows?: number;
    color?: boolean;
    theme?: TUIColorTheme | TUIThemePreference;
};

export function activePage(state: TUIRenderState) {
    const pages = state.manifest?.pages ?? [];
    return pages.find((page) => page.id === state.activePageID) ?? pages[0] ?? null;
}

export function commandContext(state: TUIRenderState, rowValues: ValueMap = {}, sectionValues: ValueMap = {}) {
    return commandContextFromState(state, rowValues, sectionValues);
}

export function tuiItemsForPage(state: TUIRenderState): TUIItem[] {
    const page = activePage(state);
    if (!page) {
        return [];
    }
    const items: TUIItem[] = [];
    if (page.id === "settings" && (state.manifest?.setup?.steps ?? []).length) {
        items.push({ kind: "setup", key: "setup", label: state.labels?.setupTitle ?? "Setup" });
    }
    for (const section of page.sections ?? []) {
        const sectionValues = state.dataSourcePayloads?.get(`section:${section.id}`)?.values ?? {};
        const sectionContext = commandContext(state, {}, sectionValues);
        for (const rawControl of section.controls ?? []) {
            const control = controlWithDataSource(state, rawControl);
            if (control.kind === "configEditor") {
                for (const setting of control.settings ?? []) {
                    items.push({
                        kind: "configSetting",
                        key: `config:${control.id}:${setting.id}`,
                        control,
                        setting,
                        label: setting.label ?? setting.id,
                    });
                }
            } else {
                items.push({ kind: "control", key: `control:${control.id}`, control, section, label: control.label ?? control.id });
            }
            if (control.kind === "libraryList") {
                for (const row of hydrateRows(control)) {
                    const context = rowContext(sectionContext, row);
                    for (const action of control.rowActions ?? []) {
                        if (isActionVisible(action, context)) {
                            items.push({
                                kind: "action",
                                key: `action:${control.id}:${row.id}:${action.id}`,
                                action,
                                context,
                                label: `${row.title ?? row.id}: ${action.title ?? action.id}`,
                            });
                        }
                    }
                }
            }
        }
        for (const action of section.actions ?? []) {
            if (isActionVisible(action, sectionContext)) {
                items.push({
                    kind: "action",
                    key: `action:${section.id}:${action.id}`,
                    action,
                    context: sectionContext,
                    label: action.title ?? action.id ?? "Action",
                });
            }
        }
    }
    return items;
}

export function selectedItem(state: TUIRenderState) {
    const items = tuiItemsForPage(state);
    if (!items.length) {
        return undefined;
    }
    const index = clamp(state.selectedItemIndex ?? 0, 0, items.length - 1);
    return items[index];
}

export function clampSelectedItem(state: TUIRenderState) {
    const count = tuiItemsForPage(state).length;
    state.selectedItemIndex = count ? clamp(state.selectedItemIndex ?? 0, 0, count - 1) : 0;
}

export function controlWithDataSource(state: TUIRenderState, control: TUIControl): TUIControl {
    const payload = state.dataSourcePayloads?.get(`control:${control.id}`);
    return payload ? applyDataSourcePayload(control, payload) : control;
}

export function selectedIDs(value: unknown): string[] {
    return normalizeSelectedIDs(value);
}

export function optionTitle(option: TUIOption, labels: TUILabels = {}) {
    return sharedOptionTitle(option, labels);
}

export function fieldValue(state: TUIRenderState, control: TUIControl) {
    return state.fieldValues?.[control.id] ?? control.value ?? control.options?.find((option) => option.selected)?.id ?? "";
}

export { configValueKey };
