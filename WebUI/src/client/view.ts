import { allControls, applyDataSourcePayload, configValueKey, disabledReason, displayCommand, hydrateRows, isActionVisible, isPrecheckReady, missingPlaceholders, rowContext, } from "../shared/rendering.js";
import { escapeAttribute, escapeHTML } from "./dom.js";
import { commandContext, configDataSourceContext, displayOption, formatLabel, localizedStatus, localizedTag, renderIcon, renderIconTitle, renderInlineError, renderLoadingBox, renderLoadingInline, renderTooltip, resolveText, tagStyle, } from "./model.js";
import { actionPrecheckKey, contextWithFileState, ensureActionPrecheck, ensureDataSource } from "./operations.js";
import { state } from "./state.js";
export function renderBundleHeader() {
    const iconPath = state.manifest.iconPath ? `/api/file?path=${encodeURIComponent(state.manifest.iconPath)}` : "";
    const icon = iconPath
        ? `<img class="bundle-icon" src="${iconPath}" alt="">`
        : `<div class="bundle-emoji" aria-hidden="true">${renderIcon(state.manifest.iconName, state.manifest.iconEmoji, "🧰")}</div>`;
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
        ${state.localizationOptions
        .map((option) => `<option value="${escapeAttribute(option.code)}" ${option.code === state.localizationCode ? "selected" : ""}>${escapeHTML(option.displayName)}</option>`)
        .join("")}
      </select>
    </label>
  `;
}
export function renderNavigation() {
    const bottomIDs = new Set(["library", "settings"]);
    const primaryPages = state.manifest.pages.filter((page) => !bottomIDs.has(page.id));
    const bottomPages = state.manifest.pages.filter((page) => bottomIDs.has(page.id));
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
            <span class="nav-icon" aria-hidden="true">${renderIcon(page.iconName, page.iconEmoji, "◦")}</span>
            <span>${escapeHTML(page.title)}</span>
          </button>`)
        .join("")}`)
        .join("");
}
export function renderPage(page) {
    return `
    <article>
      <header class="page-header">
        <h2>${renderIconTitle(page.title, page.iconName, page.iconEmoji, "📄")}</h2>
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
        ? `<h3 id="section-${escapeAttribute(section.id)}">${renderIconTitle(section.title, section.iconName, section.iconEmoji, "▦")}</h3>`
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
    const input = `<input id="${escapeAttribute(inputID)}" type="text" value="${escapeAttribute(state.fieldValues[control.id] ?? control.value ?? "")}"
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
    return `
    <fieldset class="checkbox-group">
      <legend>${escapeHTML(control.label)}${renderTooltip(control.tooltip)}</legend>
      <div class="option-grid">
        ${(control.options ?? [])
        .map((option) => `
            <label>
              <input type="checkbox" data-check-group="${escapeAttribute(control.id)}" value="${escapeAttribute(option.id)}" ${selected.has(option.id) ? "checked" : ""}>
              <span>${escapeHTML(displayOption(option))}</span>
            </label>`)
        .join("")}
      </div>
    </fieldset>
  `;
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
                <input type="text" class="mono" value="${escapeAttribute(state.configFilePaths[control.id] ?? control.configFile.path)}"
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
        ? `<span class="input-button-row"><input id="${escapeAttribute(inputID)}" type="text" value="${escapeAttribute(value)}" placeholder="${escapeAttribute(setting.placeholder ?? "")}" ${common}>
              <button type="button" class="secondary-button" data-config-path-prompt="${escapeAttribute(control.id)}:${escapeAttribute(setting.id)}">${escapeHTML(state.labels.chooseButtonTitle)}</button></span>`
        : `<input id="${escapeAttribute(inputID)}" type="text" value="${escapeAttribute(value)}" placeholder="${escapeAttribute(setting.placeholder ?? "")}" ${common}>`}
    </div>
  `;
}
export function renderActions(actions, context, compact = false) {
    const resolvedContext = contextWithFileState(context);
    return actions
        .filter((action) => isActionVisible(action, resolvedContext))
        .map((action) => {
        const missing = missingPlaceholders(action.command, resolvedContext);
        const disabled = disabledReason(action, resolvedContext, state.labels.actionUnavailableTitle);
        const shouldRunPrecheck = isPrecheckReady(action.precheck, resolvedContext);
        const precheckKey = shouldRunPrecheck ? actionPrecheckKey(action, resolvedContext) : "";
        const precheck = shouldRunPrecheck ? ensureActionPrecheck(precheckKey, action.precheck, resolvedContext) : null;
        const isLoadingPrecheck = precheckKey ? state.loadingActionPrechecks.has(precheckKey) : false;
        const precheckWarning = precheck?.severity === "warning" ? precheck.message : undefined;
        const disabledText = missing.length
            ? formatLabel(state.labels.actionMissingInputsFormat, { inputs: missing.map(actionPlaceholderLabel).join(", ") })
            : disabled ?? precheckWarning;
        const command = displayCommand(action.command, resolvedContext);
        const tooltipText = actionTooltipText(action.tooltip ?? command, disabledText ?? (isLoadingPrecheck ? state.labels.refreshingTitle : ""));
        const roleClass = action.role === "destructive" ? "danger" : action.role === "secondary" ? "secondary" : "primary";
        return `
        <span class="action-stack ${compact ? "compact" : ""}" data-tooltip="${escapeAttribute(tooltipText)}" ${disabledText || isLoadingPrecheck ? 'tabindex="0"' : ""}>
          ${precheck ? renderPrecheckBanner(precheck) : isLoadingPrecheck ? renderLoadingInline(state.labels.refreshingTitle) : ""}
          ${state.actionPrecheckErrors.has(precheckKey)
            ? renderInlineError(state.actionPrecheckErrors.get(precheckKey))
            : ""}
          <button type="button" class="action-button ${roleClass} ${compact ? "compact" : ""} ${action.iconOnly ? "icon-only" : ""}" data-action-id="${escapeAttribute(action.id)}"
            data-action="${escapeAttribute(JSON.stringify(action))}"
            data-action-context="${escapeAttribute(JSON.stringify(resolvedContext))}"
            ${disabledText || isLoadingPrecheck ? "disabled" : ""}>
            <span class="action-icon" aria-hidden="true">${renderIcon(action.iconName, action.iconEmoji, "▶")}</span>
            ${action.iconOnly ? "" : `<span>${escapeHTML(action.title)}</span>`}
          </button>
        </span>
      `;
    })
        .join("");
}
function actionTooltipText(baseTooltip, statusTooltip) {
    return [baseTooltip, statusTooltip].filter((text, index, values) => text && values.indexOf(text) === index).join("\n");
}
function actionPlaceholderLabel(placeholder) {
    const normalized = normalizedPlaceholderLabelKey(placeholder);
    for (const control of allControls(state.manifest)) {
        if (control.id === normalized) {
            return control.label ?? placeholder;
        }
        for (const setting of control.settings ?? []) {
            if (setting.id === normalized ||
                setting.key === normalized ||
                `${control.id}.${setting.id}` === normalized ||
                `${control.id}.${setting.key}` === normalized) {
                return setting.label ?? placeholder;
            }
        }
    }
    return placeholder;
}
function normalizedPlaceholderLabelKey(placeholder) {
    const key = String(placeholder ?? "").replace(/^(config|row)\./, "");
    const fileStateSeparator = key.lastIndexOf(".");
    if (fileStateSeparator > 0) {
        const suffix = key.slice(fileStateSeparator + 1);
        if (suffix === "fileSize" || suffix === "fileSizeGB") {
            return key.slice(0, fileStateSeparator);
        }
    }
    return key;
}
export function renderPrecheckBanner(precheck) {
    const icon = precheck.severity === "warning" ? "⚠️" : "💽";
    return `
    <span class="precheck-banner ${escapeAttribute(precheck.severity)}">
      <span aria-hidden="true">${icon}</span>
      <span><strong>${escapeHTML(precheck.title)}</strong><span>${escapeHTML(precheck.message)}</span></span>
    </span>
  `;
}
export function renderSetupStatusSection() {
    const steps = state.manifest.setup?.steps ?? [];
    const setupRun = state.setupRun ?? {};
    const resultsByID = new Map((setupRun.results ?? []).map((result) => [result.id, result]));
    const hasSteps = steps.length > 0;
    const isRunning = setupRun.status === "running";
    return `
    <section class="card setup-status-card">
      <div class="setup-status-header">
        <div>
          <h3>${escapeHTML(state.labels.setupTitle ?? "Setup")}</h3>
          <p class="muted">${escapeHTML(hasSteps ? setupStatusSummary(setupRun) : state.labels.setupNoStepsTitle ?? "No setup steps are defined for this bundle.")}</p>
        </div>
        ${hasSteps
        ? `<button type="button" class="action-button primary" data-run-setup ${isRunning ? "disabled" : ""}>${escapeHTML(isRunning ? state.labels.setupRunningTitle ?? "Running setup..." : state.labels.setupRunButtonTitle ?? "Run Setup")}</button>`
        : ""}
      </div>
      ${hasSteps
        ? `<ol class="setup-step-list">
          ${steps.map((step) => renderSetupStepStatus(step, resultsByID.get(step.id), setupRun.currentStepID === step.id)).join("")}
        </ol>`
        : ""}
    </section>
  `;
}
function renderSetupStepStatus(step, result, isRunning) {
    const status = isRunning ? "running" : result?.status ?? "pending";
    const statusLabel = setupStatusLabel(status);
    return `
    <li class="setup-step ${escapeAttribute(status)}">
      <span class="setup-step-status" aria-hidden="true">${setupStatusGlyph(status)}</span>
      <span class="setup-step-title">${escapeHTML(step.label)}</span>
      <span class="setup-step-kind">${escapeHTML(step.kind)}</span>
      <span class="setup-step-label">${escapeHTML(statusLabel)}</span>
    </li>
  `;
}
function setupStatusSummary(setupRun) {
    switch (setupRun.status) {
        case "running":
            return state.labels.setupRunningTitle ?? "Running setup...";
        case "ok":
            return state.labels.setupStatusOkTitle ?? "Setup completed successfully.";
        case "failed":
            return state.labels.setupStatusFailedTitle ?? "Setup failed. Review command output for details.";
        default:
            return state.labels.setupStatusReadyTitle ?? "Review and run this bundle's setup steps.";
    }
}
function setupStatusLabel(status) {
    switch (status) {
        case "running":
            return state.labels.setupStepRunningTitle ?? "Running";
        case "ok":
            return state.labels.setupStepOkTitle ?? "OK";
        case "warning":
            return state.labels.setupStepWarningTitle ?? "Warning";
        case "failed":
            return state.labels.setupStepFailedTitle ?? "Failed";
        default:
            return state.labels.setupStepPendingTitle ?? "Pending";
    }
}
function setupStatusGlyph(status) {
    switch (status) {
        case "running":
            return `<span class="mini-spinner" aria-hidden="true"></span>`;
        case "ok":
            return "✓";
        case "warning":
            return "!";
        case "failed":
            return "×";
        default:
            return "○";
    }
}
export function renderRowCell(row, column) {
    const value = column.id === "name" ? row.title ?? row.values?.[column.id] ?? row.id : column.id === "status" ? localizedStatus(row.status ?? row.values?.status ?? "") : row.values?.[column.id] ?? "";
    const tags = column.id === "name"
        ? [
            row.status ? `<span class="pill ${tagStyle(row.status)}">${escapeHTML(localizedStatus(row.status))}</span>` : "",
            ...(row.tags ?? []).map((tag) => `<span class="pill ${escapeAttribute(tag.style ?? "secondary")}">${escapeHTML(localizedTag(tag))}</span>`),
        ].join("")
        : "";
    return `<div>${escapeHTML(value)}${tags ? `<div class="pill-row">${tags}</div>` : ""}</div>`;
}
export function renderStandardOptionsAccessory() {
    const currentName = state.localizationOptions.find((option) => option.code === state.localizationCode)?.displayName ?? state.localizationCode;
    return `
    <section class="card standard-options-card">
      <header class="section-header">
        <h3>${renderIconTitle(state.labels.standardOptionsSectionTitle, "slider.horizontal.3", undefined, "⚙️")}</h3>
      </header>
      <div class="controls">
        ${state.localizationOptions.length > 1
        ? `<label class="form-row">
                <span class="row-label">${escapeHTML(state.labels.languagePickerLabel)}</span>
                <span>
                  <select data-locale-picker aria-label="${escapeAttribute(state.labels.languagePickerLabel)}">
                    ${state.localizationOptions
            .map((option) => `<option value="${escapeAttribute(option.code)}" ${option.code === state.localizationCode ? "selected" : ""}>${escapeHTML(option.displayName)}</option>`)
            .join("")}
                  </select>
                  <span class="field-note">${escapeHTML(currentName)}</span>
                </span>
              </label>`
        : ""}
        <label class="form-row">
          <span class="row-label">${escapeHTML(state.labels.iconSetPickerLabel)}</span>
          <select data-icon-set-picker aria-label="${escapeAttribute(state.labels.iconSetPickerLabel)}">
            <option value="emoji" ${state.iconSet === "emoji" ? "selected" : ""}>${escapeHTML(state.labels.iconSetEmojiLabel)}</option>
            <option value="platform" ${state.iconSet === "platform" ? "selected" : ""}>${escapeHTML(state.labels.iconSetBootstrapIconsLabel)}</option>
          </select>
        </label>
        <label class="form-row">
          <span class="row-label">${escapeHTML(state.labels.colorThemePickerLabel)}</span>
          <select data-color-theme-picker aria-label="${escapeAttribute(state.labels.colorThemePickerLabel)}">
            <option value="system" ${state.colorTheme === "system" ? "selected" : ""}>${escapeHTML(state.labels.colorThemeSystemLabel)}</option>
            <option value="light" ${state.colorTheme === "light" ? "selected" : ""}>${escapeHTML(state.labels.colorThemeLightLabel)}</option>
            <option value="dark" ${state.colorTheme === "dark" ? "selected" : ""}>${escapeHTML(state.labels.colorThemeDarkLabel)}</option>
          </select>
        </label>
      </div>
    </section>
  `;
}
export function renderConfirmationDialog() {
    const { action, context, input = "" } = state.pendingConfirmation;
    const confirmation = action.confirm;
    const requiredText = resolveText(confirmation.requiredText ?? "", context);
    const canConfirm = !requiredText || input === requiredText;
    return `
    <div class="modal-backdrop" role="presentation">
      <section class="confirmation-modal" role="dialog" aria-modal="true" aria-labelledby="confirm-title">
        <h2 id="confirm-title">${renderIconTitle(resolveText(confirmation.title ?? action.title, context), action.role === "destructive" ? "exclamationmark.triangle.fill" : action.iconName, action.iconEmoji, "?")}</h2>
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
