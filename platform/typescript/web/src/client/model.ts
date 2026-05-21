import { checkedOptionsForContext, commandContextFromState, configEditorControls, configValueKey, optionTitle } from "../../../shared/rendering.js";
import { escapeAttribute, escapeHTML } from "./dom.js";
import { state } from "./state.js";
export function commandContext(_section, rowValues = {}, sectionValues = {}) {
    return commandContextFromState(state, rowValues, sectionValues);
}
export function configDataSourceContext(control) {
    const settingValues = { ...state.configValues };
    for (const setting of control.settings ?? []) {
        const value = state.configValues[configValueKey(control, setting)] ?? setting.value ?? "";
        settingValues[setting.id] = value;
        settingValues[setting.key] = value;
    }
    return {
        fieldValues: { ...state.fieldValues, ...settingValues },
        checkedOptions: checkedOptionsForContext(state.checkedOptions),
        configValues: settingValues,
        rowValues: {},
        bundleRootPath: state.bundleRootPath,
    };
}
export function syncSharedField(setting, value) {
    if (Object.hasOwn(state.fieldValues, setting.key)) {
        state.fieldValues[setting.key] = value;
    }
    if (Object.hasOwn(state.fieldValues, setting.id)) {
        state.fieldValues[setting.id] = value;
    }
}
export function boundFieldKey(setting) {
    if (Object.hasOwn(state.fieldValues, setting.key))
        return setting.key;
    if (Object.hasOwn(state.fieldValues, setting.id))
        return setting.id;
    return undefined;
}
export function configSettingBindings(fieldID) {
    return configEditorControls(state.manifest).flatMap((control) => (control.settings ?? [])
        .filter((setting) => setting.id === fieldID || setting.key === fieldID)
        .map((setting) => ({ control, setting })));
}
export function elements<T extends Element = any>(selector: string): T[] {
    const appRoot = document.querySelector("#app");
    if (!appRoot) {
        return [];
    }
    return [...appRoot.querySelectorAll<T>(selector)];
}
export function errorMessage(error: unknown) {
    return error instanceof Error ? error.message : String(error);
}
export function findControl(id) {
    for (const page of state.manifest.pages ?? []) {
        for (const section of page.sections ?? []) {
            const control = (section.controls ?? []).find((candidate) => candidate.id === id);
            if (control)
                return control;
        }
    }
    return undefined;
}
export function displayOption(option) {
    return optionTitle(option, state.labels);
}
export function localizedStatus(status) {
    return state.labels.libraryStatusLabels?.[String(status).toLowerCase()] ?? status;
}
export function localizedTag(tag) {
    return state.labels.libraryTagLabels?.[tag.id] ?? state.labels.libraryTagLabels?.[String(tag.title).toLowerCase()] ?? tag.title;
}
export function tagStyle(status) {
    switch (String(status).toLowerCase()) {
        case "installed":
            return "success";
        case "unindexed":
        case "incomplete":
            return "warning";
        case "missing":
            return "secondary";
        default:
            return "primary";
    }
}
export function buildTagStyle(build) {
    const value = String(build ?? "").trim().toLowerCase();
    if (!value) {
        return undefined;
    }
    if (value.includes("grch37") || value.includes("hg19")) {
        return "primary";
    }
    if (value.includes("grch38") || value.includes("hg38")) {
        return "success";
    }
    if (value.includes("t2t") || value.includes("chm13")) {
        return "warning";
    }
    return "secondary";
}
export function formatLabel(template, values = {}) {
    return String(template ?? "").replace(/%\{([^}]+)\}/g, (_, key) => values[key] ?? "");
}
export function renderTooltip(text) {
    return text
        ? `<span class="tooltip" tabindex="0" role="button" aria-label="${escapeAttribute(text)}" data-tooltip="${escapeAttribute(text)}">i</span>`
        : "";
}
export function renderInlineError(message, accessory = "") {
    return `<div class="inline-error"><span aria-hidden="true">⚠</span><span>${escapeHTML(message)}</span>${accessory}</div>`;
}
export function renderLoadingInline(message) {
    return `<p class="loading-inline"><span class="spinner small" aria-hidden="true"></span>${escapeHTML(message)}</p>`;
}
export function renderLoadingBox(message) {
    return `<div class="loading-box"><span class="spinner small" aria-hidden="true"></span>${escapeHTML(message)}</div>`;
}
export function renderIconTitle(title, iconName, textIcon, fallback = "•") {
    return `<span class="icon-title"><span class="icon-title-icon" aria-hidden="true">${renderIcon(iconName, textIcon, fallback)}</span><span>${escapeHTML(title)}</span></span>`;
}
export function renderIcon(iconName, textIcon, fallback) {
    const bootstrap = resolveIcon("bootstrap", iconName);
    const emoji = resolveIcon("emoji", iconName);
    const playIconClass = isPlayIcon(iconName, textIcon, fallback, bootstrap, emoji) ? " play-icon" : "";
    if (state.iconSet === "platform" && bootstrap) {
        return `<i class="bi bi-${escapeAttribute(bootstrap)} web-icon${playIconClass}" aria-hidden="true"></i>`;
    }
    if (textIcon) {
        return `<span class="emoji-icon${playIconClass}">${escapeHTML(textIcon)}</span>`;
    }
    if (state.iconSet === "emoji" && emoji) {
        return `<span class="emoji-icon${playIconClass}">${escapeHTML(emoji)}</span>`;
    }
    if (bootstrap) {
        return `<i class="bi bi-${escapeAttribute(bootstrap)} web-icon${playIconClass}" aria-hidden="true"></i>`;
    }
    return `<span class="emoji-icon${playIconClass}">${escapeHTML(fallback)}</span>`;
}
function resolveIcon(source, iconName) {
    const key = String(iconName ?? "").trim();
    return key ? state.iconMap?.[source]?.[key] : undefined;
}
function isPlayIcon(iconName, textIcon, fallback, bootstrap, emoji) {
    return iconName === "play" || iconName === "play.fill" || bootstrap === "play" || bootstrap === "play-fill" || emoji === "▶️" || (!iconName && !textIcon && fallback === "▶");
}
export function resolveText(value, context) {
    return String(value ?? "").replace(/\{\{([^}]+)\}\}/g, (_, raw) => {
        const placeholder = raw.trim();
        if (placeholder.startsWith("row."))
            return context.rowValues?.[placeholder.slice(4)] ?? "";
        if (placeholder.startsWith("config."))
            return context.configValues?.[placeholder.slice(7)] ?? "";
        return context.rowValues?.[placeholder] ?? context.fieldValues?.[placeholder] ?? context.configValues?.[placeholder] ?? "";
    });
}
