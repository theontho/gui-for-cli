import { applyDataSourcePayload, configValueKey, hydrateRows, rowContext, } from "../../../shared/rendering.js";
import { escapeAttribute, escapeHTML } from "./dom.js";
import { buildTagStyle, commandContext, configDataSourceContext, displayOption, localizedStatus, localizedTag, renderIcon, renderIconTitle, renderInlineError, renderLoadingBox, renderLoadingInline, renderTooltip, resolveText, tagStyle, } from "./model.js";
import { ensureDataSource } from "./operations.js";
import { state } from "./state.js";
export { renderActions, renderPrecheckBanner } from "./view/actions.js";
import { renderActions } from "./view/actions.js";
export { renderSetupStatusSection, renderStandardOptionsAccessory } from "./view/settings.js";
import { renderSetupStatusSection, renderStandardOptionsAccessory } from "./view/settings.js";
export { renderSetupGlobalStatusBar, renderSetupPromptDialog, setupHasNeverRun, setupNeedsAttention, setupPageID, setupPromptMessage, } from "./view/setup.js";
import { renderSetupGlobalStatusBar, renderSetupPromptDialog } from "./view/setup.js";
export function renderBundleHeader() {
    const iconPath = state.manifest.iconPath ? `/api/file?path=${encodeURIComponent(state.manifest.iconPath)}` : "";
    const icon = iconPath
        ? `<img class="bundle-icon" src="${iconPath}" alt="">`
        : `<div class="bundle-emoji" aria-hidden="true">${renderIcon(state.manifest.iconName, state.manifest.textIcon, "🧰")}</div>`;
    return `
    <header class="bundle-header">
      ${icon}
      <h1 title="${escapeAttribute(state.manifest.summary)}">${escapeHTML(state.manifest.displayName)}${renderTooltip(state.manifest.summary)}</h1>
    </header>
  `;
}
export function renderLanguagePicker() {
    return `
    <label class="language-picker">
      <span>${escapeHTML(state.labels.languagePickerLabel)}</span>
      <select data-locale-picker>
        <option value="__system__" ${state.usingSystemDefaultLocale ? "selected" : ""}>${escapeHTML(systemLanguageOptionLabel())}</option>
        ${state.localizationOptions
        .map((option) => `<option value="${escapeAttribute(option.code)}" ${!state.usingSystemDefaultLocale && option.code === state.localizationCode ? "selected" : ""}>${escapeHTML(languageOptionLabel(option))}</option>`)
        .join("")}
      </select>
    </label>
  `;
}
function systemLanguageOptionLabel() {
    const currentOption = state.localizationOptions.find((option) => option.code === state.localizationCode);
    const currentName = currentOption ? languageOptionLabel(currentOption) : state.localizationCode;
    return currentName
        ? `${state.labels.languageSystemDefaultLabel ?? "Use system default"} — ${currentName}`
        : state.labels.languageSystemDefaultLabel ?? "Use system default";
}
function languageOptionLabel(option) {
    return option.isAITranslated
        ? `${option.displayName} - ${state.labels.languageAITranslatedLabel ?? "AI translated"}`
        : option.displayName;
}
export function renderNavigation() {
    const primaryPages = state.manifest.pages.filter((page) => page.sidebarPlacement !== "bottom");
    const bottomPages = state.manifest.pages.filter((page) => page.sidebarPlacement === "bottom");
    return `
    <div class="nav-primary">${renderNavigationGroups(primaryPages)}</div>
    ${bottomPages.length ? `<div class="nav-bottom">${renderNavigationGroups(bottomPages, false)}</div>` : ""}
  `;
}
export function renderNavigationGroups(pages, showGroupTitles = true) {
    const groups = [];
    for (const page of pages) {
        const groupName = page.sidebarGroup ?? "";
        let group = groups.find((candidate) => candidate.name === groupName);
        if (!group) {
            group = { name: groupName, pages: [] };
            groups.push(group);
        }
        group.pages.push(page);
    }
    return groups
        .map((group) => `
      ${showGroupTitles && group.name ? `<h2>${escapeHTML(group.name)}</h2>` : ""}
      ${group.pages
        .map((page) => `
          <button class="nav-item ${page.id === state.activePageID ? "active" : ""}" data-page-id="${escapeAttribute(page.id)}">
            <span class="nav-icon" aria-hidden="true">${renderIcon(page.iconName, page.textIcon, "◦")}</span>
            <span>${escapeHTML(page.title)}</span>
          </button>`)
        .join("")}`)
        .join("");
}
export function renderPage(page) {
    return `
    <article>
      <header class="page-header">
        <h2>${renderIconTitle(page.title, page.iconName, page.textIcon, "📄")}</h2>
        <p>${escapeHTML(page.summary)}</p>
      </header>
      ${page.id === "settings" ? `${renderSetupStatusSection()}${renderStandardOptionsAccessory()}` : ""}
      <div class="sections">
        ${(page.sections ?? []).map((section) => renderSection(section)).join("")}
      </div>
    </article>
  `;
}
export function renderSection(section) {
    const key = `section:${section.id}`;
    if (section.dataSource) {
        ensureDataSource(key, section.dataSource, commandContext(section));
    }
    const sectionValues = state.dataSourcePayloads.get(key)?.values ?? {};
    const context = commandContext(section, {}, sectionValues);
    return `
    <section class="card" aria-labelledby="section-${escapeAttribute(section.id)}">
      <header class="section-header">
        ${section.title
        ? `<h3 id="section-${escapeAttribute(section.id)}">${renderIconTitle(section.title, section.iconName, section.textIcon, "▦")}</h3>`
        : ""}
        ${section.subtitle ? `<p>${escapeHTML(section.subtitle)}</p>` : ""}
      </header>
      <div class="controls">
        ${(section.controls ?? []).map((control) => renderControl(control, section, context)).join("")}
      </div>
      ${state.loadingDataSources.has(key) ? renderLoadingBox(state.labels.loadingTitle) : ""}
      ${state.dataSourceErrors.has(key)
        ? renderInlineError(state.dataSourceErrors.get(key), `<button type="button" data-retry-source="${escapeAttribute(key)}">${escapeHTML(state.labels.retryButtonTitle)}</button>`)
        : ""}
      ${(section.actions ?? []).length ? `<div class="action-row">${renderActions(section.actions, context)}</div>` : ""}
    </section>
  `;
}
export function renderControl(control, section, sectionContext) {
    const key = `control:${control.id}`;
    let renderedControl = control;
    if (control.dataSource) {
        ensureDataSource(key, control.dataSource, commandContext(section));
        const payload = state.dataSourcePayloads.get(key);
        if (payload) {
            renderedControl = applyDataSourcePayload(control, payload);
        }
    }
    const error = state.dataSourceErrors.get(key);
    const loading = state.loadingDataSources.has(key);
    let body = "";
    switch (renderedControl.kind) {
        case "text":
        case "path":
            body = renderTextControl(renderedControl);
            break;
        case "dropdown":
            body = renderDropdownControl(renderedControl);
            break;
        case "toggle":
            body = renderToggleControl(renderedControl);
            break;
        case "checkboxGroup":
            body = renderCheckboxGroup(renderedControl);
            break;
        case "infoGrid":
            body = renderInfoGrid(renderedControl);
            break;
        case "libraryList":
            body = renderLibraryList(renderedControl, sectionContext);
            break;
        case "configEditor":
            body = renderConfigEditor(renderedControl);
            break;
        default:
            body = renderInlineError(`Unsupported control kind: ${renderedControl.kind}`);
    }
    return `
    <div class="control" title="${escapeAttribute(renderedControl.tooltip ?? "")}">
      ${body}
      ${loading && renderedControl.kind !== "libraryList" ? renderLoadingInline(state.labels.loadingTitle) : ""}
      ${error
        ? renderInlineError(error, `<button type="button" data-retry-source="${escapeAttribute(key)}">${escapeHTML(state.labels.retryButtonTitle)}</button>`)
        : ""}
    </div>
  `;
}
export function renderTextControl(control) {
    const inputID = `control-${control.id}`;
    const pathAttributes = control.kind === "path" ? ` class="path-input" dir="ltr"` : "";
    const input = `<input id="${escapeAttribute(inputID)}" type="text"${pathAttributes} value="${escapeAttribute(state.fieldValues[control.id] ?? control.value ?? "")}"
        placeholder="${escapeAttribute(control.placeholder ?? "")}" data-field-id="${escapeAttribute(control.id)}">`;
    return `
    <div class="form-row">
      <label class="row-label" for="${escapeAttribute(inputID)}">${escapeHTML(control.label)}${renderTooltip(control.tooltip)}</label>
      ${control.kind === "path"
        ? `<span class="input-button-row">${input}<button type="button" class="secondary-button" data-path-prompt="${escapeAttribute(control.id)}">${escapeHTML(state.labels.chooseButtonTitle)}</button></span>`
        : input}
    </div>
  `;
}
export function renderDropdownControl(control) {
    const value = state.fieldValues[control.id] ?? control.value ?? control.options?.find((option) => option.selected)?.id ?? "";
    return `
    <label class="form-row">
      <span class="row-label">${escapeHTML(control.label)}${renderTooltip(control.tooltip)}</span>
      <select data-field-id="${escapeAttribute(control.id)}">
        ${(control.options ?? [])
        .map((option) => `<option value="${escapeAttribute(option.id)}" ${option.id === value ? "selected" : ""}>${escapeHTML(displayOption(option))}</option>`)
        .join("")}
      </select>
    </label>
  `;
}
export function renderToggleControl(control) {
    const checked = (state.fieldValues[control.id] ?? control.value ?? "") === "true";
    return `
    <label class="toggle-row">
      <span class="row-label">${escapeHTML(control.label)}${renderTooltip(control.tooltip)}</span>
      <input type="checkbox" ${checked ? "checked" : ""} data-field-id="${escapeAttribute(control.id)}" data-toggle>
    </label>
  `;
}
export function renderCheckboxGroup(control) {
    const selected = state.checkedOptions[control.id] ?? new Set((control.options ?? []).filter((option) => option.selected).map((option) => option.id));
    const groups = groupedOptions(control.options ?? []);
    return `
    <fieldset class="checkbox-group">
      <legend>${escapeHTML(control.label)}${renderTooltip(control.tooltip)}</legend>
      ${groups
        .map((group) => `
        <div class="option-group">
          ${group.title ? `<h4>${escapeHTML(group.title)}</h4>` : ""}
          <div class="option-grid">
            ${group.options.map((option) => `
              <label>
                <input type="checkbox" data-check-group="${escapeAttribute(control.id)}" value="${escapeAttribute(option.id)}" ${selected.has(option.id) ? "checked" : ""}>
                <span>${escapeHTML(displayOption(option))}</span>
              </label>`).join("")}
          </div>
        </div>`)
        .join("")}
    </fieldset>
  `;
}
function groupedOptions(options) {
    const groups = [];
    for (const option of options) {
        const title = option.group ?? "";
        let group = groups.find((candidate) => candidate.title === title);
        if (!group) {
            group = { title, options: [] };
            groups.push(group);
        }
        group.options.push(option);
    }
    return groups;
}
export function renderInfoGrid(control) {
    return `
    <div>
      <div class="control-label">${escapeHTML(control.label)}${renderTooltip(control.tooltip)}</div>
      <div class="info-grid">
        ${(control.options ?? []).map((option) => `<div>${escapeHTML(displayOption(option))}</div>`).join("")}
      </div>
    </div>
  `;
}
export function renderLibraryList(control, context) {
    const rows = hydrateRows(control);
    const key = `control:${control.id}`;
    if (state.loadingDataSources.has(key) && !state.dataSourcePayloads.has(key)) {
        return `
      <div class="library-list">
        <div class="control-label">${escapeHTML(control.label)}${renderTooltip(control.tooltip)}</div>
        ${renderLoadingBox(state.labels.loadingTitle)}
      </div>
    `;
    }
    return `
    <div class="library-list">
      <div class="control-label">${escapeHTML(control.label)}${renderTooltip(control.tooltip)}</div>
      ${rows.length
        ? `<div class="table-wrap"><table>
              <thead><tr>
                ${(control.columns ?? []).map((column) => `<th>${escapeHTML(column.title)}</th>`).join("")}
                ${(control.rowActions ?? []).length ? `<th>${escapeHTML(state.labels.actionsColumnTitle)}</th>` : ""}
              </tr></thead>
              <tbody>
                ${rows
            .map((row) => {
            const contextForRow = rowContext(context, row);
            return `<tr>
                      ${(control.columns ?? []).map((column) => `<td>${renderRowCell(row, column)}</td>`).join("")}
                      ${(control.rowActions ?? []).length
                ? `<td><div class="row-actions">${renderActions(control.rowActions, contextForRow, true)}</div></td>`
                : ""}
                    </tr>`;
        })
            .join("")}
              </tbody>
            </table></div>`
        : `<p class="empty">${escapeHTML(state.labels.libraryEmptyTitle)}</p>`}
    </div>
  `;
}
export function renderConfigEditor(control) {
    return `
    <div class="config-editor">
      <div class="control-label">${escapeHTML(control.label)}${renderTooltip(control.tooltip)}</div>
      ${control.configFile
        ? `<label class="form-row">
              <span class="row-label">${escapeHTML(state.labels.settingsFileLabel)}</span>
              <span class="input-button-row">
                <input type="text" class="mono path-input" dir="ltr" value="${escapeAttribute(state.configFilePaths[control.id] ?? control.configFile.path)}"
                  data-config-path="${escapeAttribute(control.id)}">
                <button type="button" class="secondary-button" data-load-config="${escapeAttribute(control.id)}">${escapeHTML(state.labels.loadButtonTitle)}</button>
              </span>
            </label>
            <button type="button" class="visually-hidden" data-save-config="${escapeAttribute(control.id)}">${escapeHTML(state.labels.saveButtonTitle)}</button>`
        : ""}
      ${(control.settings ?? []).map((setting) => renderConfigSetting(control, setting)).join("")}
    </div>
  `;
}
export function renderConfigSetting(control, setting) {
    const key = `${control.id}.${setting.id}`;
    let options = setting.options ?? [];
    if (setting.dataSource) {
        const context = configDataSourceContext(control);
        ensureDataSource(`setting:${key}`, setting.dataSource, context);
        options = state.dataSourcePayloads.get(`setting:${key}`)?.options ?? options;
    }
    const value = state.configValues[configValueKey(control, setting)] ?? setting.value ?? "";
    const common = `data-config-control="${escapeAttribute(control.id)}" data-config-setting="${escapeAttribute(setting.id)}"`;
    if (setting.kind === "dropdown") {
        return `
      <label class="form-row">
        <span class="row-label">${escapeHTML(setting.label)}${renderTooltip(setting.tooltip)}</span>
        <select ${common}>
          ${options
            .map((option) => `<option value="${escapeAttribute(option.id)}" ${option.id === value ? "selected" : ""}>${escapeHTML(displayOption(option))}</option>`)
            .join("")}
        </select>
      </label>
    `;
    }
    if (setting.kind === "toggle") {
        return `
      <label class="toggle-row">
        <span class="row-label">${escapeHTML(setting.label)}${renderTooltip(setting.tooltip)}</span>
        <input type="checkbox" ${value === "true" ? "checked" : ""} ${common} data-toggle>
      </label>
    `;
    }
    const inputID = `setting-${control.id}-${setting.id}`;
    return `
    <div class="form-row">
      <label class="row-label" for="${escapeAttribute(inputID)}">${escapeHTML(setting.label)}${renderTooltip(setting.tooltip)}</label>
      ${setting.kind === "path"
        ? `<span class="input-button-row"><input id="${escapeAttribute(inputID)}" type="text" class="path-input" dir="ltr" value="${escapeAttribute(value)}" placeholder="${escapeAttribute(setting.placeholder ?? "")}" ${common}>
              <button type="button" class="secondary-button" data-config-path-prompt="${escapeAttribute(control.id)}:${escapeAttribute(setting.id)}">${escapeHTML(state.labels.chooseButtonTitle)}</button></span>`
        : `<input id="${escapeAttribute(inputID)}" type="text" value="${escapeAttribute(value)}" placeholder="${escapeAttribute(setting.placeholder ?? "")}" ${common}>`}
    </div>
  `;
}

export function renderRowCell(row, column) {
    const value = column.id === "name" ? row.title ?? row.values?.[column.id] ?? row.id : column.id === "status" ? localizedStatus(row.status ?? row.values?.status ?? "") : row.values?.[column.id] ?? "";
    if (column.id === "build") {
        const style = buildTagStyle(value);
        return style ? `<div><span class="pill build ${style}">${escapeHTML(value)}</span></div>` : "<div></div>";
    }
    const tags = column.id === "name"
        ? [
            row.status ? `<span class="pill ${tagStyle(row.status)}">${escapeHTML(localizedStatus(row.status))}</span>` : "",
            ...(row.tags ?? []).map((tag) => `<span class="pill ${escapeAttribute(tag.style ?? "secondary")}">${escapeHTML(localizedTag(tag))}</span>`),
        ].join("")
        : "";
    return `<div>${escapeHTML(value)}${tags ? `<div class="pill-row">${tags}</div>` : ""}</div>`;
}

export function renderConfirmationDialog() {
    const { action, context, input = "" } = state.pendingConfirmation;
    const confirmation = action.confirm;
    const requiredText = resolveText(confirmation.requiredText ?? "", context);
    const canConfirm = !requiredText || input === requiredText;
    return `
    <div class="modal-backdrop" role="presentation">
      <section class="confirmation-modal" role="dialog" aria-modal="true" aria-labelledby="confirm-title">
        <h2 id="confirm-title">${renderIconTitle(resolveText(confirmation.title ?? action.title, context), action.role === "destructive" ? "exclamationmark.triangle.fill" : action.iconName, action.role === "destructive" ? "⚠️" : action.textIcon, "?")}</h2>
        ${confirmation.message ? `<p>${escapeHTML(resolveText(confirmation.message, context))}</p>` : ""}
        ${requiredText
        ? `<label class="form-row stacked">
                <span>${escapeHTML(resolveText(confirmation.prompt ?? `Type "${requiredText}" to confirm.`, context))}</span>
                <input type="text" data-confirm-input value="${escapeAttribute(input)}" placeholder="${escapeAttribute(resolveText(requiredText, context))}" autofocus>
              </label>`
        : ""}
        <div class="modal-actions">
          <button type="button" class="secondary-button" data-confirm-cancel>${escapeHTML(confirmation.cancelButtonTitle ?? "Cancel")}</button>
          <button type="button" class="action-button ${action.role === "destructive" ? "danger" : "primary"}" data-confirm-run ${canConfirm ? "" : "disabled"}>${escapeHTML(confirmation.confirmButtonTitle ?? action.title)}</button>
        </div>
      </section>
    </div>
  `;
}
