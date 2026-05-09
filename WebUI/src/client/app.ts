import {
  applyDataSourcePayload,
  checkedOptionsForContext,
  configEditorControls,
  configValueKey,
  disabledReason,
  displayCommand,
  hydrateRows,
  initialCheckedOptions,
  initialConfigValues,
  initialFieldValues,
  isActionVisible,
  missingPlaceholders,
  rowContext,
} from "../shared/rendering.js";
import { api } from "./api.js";
import { clamp, escapeAttribute, escapeHTML } from "./dom.js";
import { bootstrapIconMap, emojiIconMap, normalizeColorTheme, normalizeIconSet } from "./icons.js";
import { createInitialState } from "./state.js";

const app = document.querySelector("#app") as HTMLElement;
let activeTooltip: { target: HTMLElement; tooltip: HTMLElement } | null = null;
let tooltipCleanup = () => {};
const runningActionControllers = new Map<string, AbortController>();
const state = createInitialState();

await bootstrap();

async function bootstrap(locale?: string) {
  try {
    const bundle = await api(`/api/manifest${locale ? `?locale=${encodeURIComponent(locale)}` : ""}`);
    state.manifest = bundle.manifest;
    state.labels = bundle.labels;
    state.localizationCode = bundle.localizationCode;
    state.localizationOptions = bundle.localizationOptions;
    state.iconSet = normalizeIconSet(bundle.bundleState?.iconSet);
    state.colorTheme = normalizeColorTheme(bundle.bundleState?.colorTheme);
    state.exitCodeReference = new Map((bundle.manifest.exitCodeReference ?? []).map((entry) => [Number(entry.code), entry]));
    state.bundleRootPath = bundle.bundleRootPath;
    ensureMainTerminal();
    state.activePageID = state.activePageID || bundle.manifest.pages[0]?.id;
    state.fieldValues = bundle.fieldValues ?? initialFieldValues(bundle.manifest);
    state.checkedOptions = Object.fromEntries(
      Object.entries(bundle.checkedOptions ?? {}).map(([key, value]) => [
        key,
        new Set(Array.isArray(value) ? value : []),
      ]),
    );
    for (const [key, value] of Object.entries(initialCheckedOptions(bundle.manifest))) {
      state.checkedOptions[key] ??= value;
    }
    state.configValues = bundle.configValues ?? initialConfigValues(bundle.manifest);
    state.configFilePaths =
      bundle.configFilePaths ??
      Object.fromEntries(
        configEditorControls(bundle.manifest)
          .filter((control) => control.configFile)
          .map((control) => [control.id, control.configFile.path]),
      );
    render();
  } catch (error) {
    renderError(error);
  }
}

async function loadInitialConfigs() {
  for (const control of configEditorControls(state.manifest)) {
    if (!control.configFile) {
      continue;
    }
    try {
      const result = await api("/api/config/load", {
        method: "POST",
        body: { control, path: state.configFilePaths[control.id] },
      });
      state.configFilePaths[control.id] = result.path;
      for (const setting of control.settings ?? []) {
        const value = result.values[setting.key] ?? setting.value ?? "";
        state.configValues[configValueKey(control, setting)] = value;
        syncSharedField(setting, value);
      }
      appendTerminal("config", `Loaded settings from ${result.path}`);
    } catch (error) {
      appendTerminal("error", `Could not load ${control.label}: ${error.message}`);
    }
  }
}

function render() {
  updateDocumentMetadata();
  document.documentElement.lang = state.localizationCode || "en";
  document.documentElement.dir = state.labels.layoutDirection || "ltr";
  applyDocumentPreferences();
  const activePage = state.manifest.pages.find((page) => page.id === state.activePageID) ?? state.manifest.pages[0];
  state.activePageID = activePage?.id;
  app.dataset.state = "ready";
  app.classList.toggle("terminal-hidden", !state.isTerminalVisible);
  app.style.setProperty("--sidebar-width", `${clamp(state.sidebarWidth, 160, 420)}px`);
  app.style.setProperty("--terminal-height", `${clamp(state.terminalHeight, 96, Math.max(96, window.innerHeight - 260))}px`);
  app.innerHTML = `
    <aside class="sidebar">
      ${renderBundleHeader()}
      <nav class="page-nav" aria-label="Pages">${renderNavigation()}</nav>
    </aside>
    <div class="sidebar-resizer" data-sidebar-resizer role="separator" aria-orientation="vertical" aria-label="Resize sidebar" tabindex="0"></div>
    <div class="detail-shell">
      <main class="page-panel">${activePage ? renderPage(activePage) : ""}</main>
      ${state.isTerminalVisible ? `<div class="terminal-resizer" data-terminal-resizer role="separator" aria-orientation="horizontal" aria-label="Resize command output" tabindex="0"></div>` : ""}
      ${state.isTerminalVisible ? renderTerminalPane() : ""}
      <button type="button" class="terminal-toggle" data-terminal-toggle title="${escapeAttribute(terminalToggleTitle())}" aria-label="${escapeAttribute(
        terminalToggleTitle(),
      )}">▭</button>
    </div>
    ${state.pendingConfirmation ? renderConfirmationDialog() : ""}
  `;
  bindEvents();
}

function updateDocumentMetadata() {
  document.title = state.manifest?.displayName || "GUI for CLI";
  let favicon = document.querySelector<HTMLLinkElement>("link[data-bundle-favicon]");
  if (!favicon) {
    favicon = document.createElement("link");
    favicon.rel = "icon";
    favicon.sizes = "any";
    favicon.type = "image/x-icon";
    favicon.dataset.bundleFavicon = "";
    document.head.append(favicon);
  }
  const version = encodeURIComponent(state.manifest?.id || "bundle");
  favicon.href = `/favicon.ico?bundle=${version}`;
}

function applyDocumentPreferences() {
  document.documentElement.dataset.iconSet = state.iconSet;
  if (state.colorTheme === "light" || state.colorTheme === "dark") {
    document.documentElement.dataset.theme = state.colorTheme;
    document.documentElement.style.colorScheme = state.colorTheme;
  } else {
    delete document.documentElement.dataset.theme;
    document.documentElement.style.colorScheme = "light dark";
  }
}

function renderBundleHeader() {
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

function renderLanguagePicker() {
  return `
    <label class="language-picker">
      <span>${escapeHTML(state.labels.languagePickerLabel)}</span>
      <select data-locale-picker>
        ${state.localizationOptions
          .map(
            (option) =>
              `<option value="${escapeAttribute(option.code)}" ${option.code === state.localizationCode ? "selected" : ""}>${escapeHTML(
                option.displayName,
              )}</option>`,
          )
          .join("")}
      </select>
    </label>
  `;
}

function renderNavigation() {
  const bottomIDs = new Set(["library", "settings"]);
  const primaryPages = state.manifest.pages.filter((page) => !bottomIDs.has(page.id));
  const bottomPages = state.manifest.pages.filter((page) => bottomIDs.has(page.id));
  return `
    <div class="nav-primary">${renderNavigationGroups(primaryPages)}</div>
    ${bottomPages.length ? `<div class="nav-bottom">${renderNavigationGroups(bottomPages, false)}</div>` : ""}
  `;
}

function renderNavigationGroups(pages, showGroupTitles = true) {
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
    .map(
      (group) => `
      ${showGroupTitles && group.name ? `<h2>${escapeHTML(group.name)}</h2>` : ""}
      ${group.pages
        .map(
          (page) => `
          <button class="nav-item ${page.id === state.activePageID ? "active" : ""}" data-page-id="${escapeAttribute(page.id)}">
            <span class="nav-icon" aria-hidden="true">${renderIcon(page.iconName, page.iconEmoji, "◦")}</span>
            <span>${escapeHTML(page.title)}</span>
          </button>`,
        )
        .join("")}`,
    )
    .join("");
}

function renderPage(page) {
  return `
    <article>
      <header class="page-header">
        <h2>${renderIconTitle(page.title, page.iconName, page.iconEmoji, "📄")}</h2>
        <p>${escapeHTML(page.summary)}</p>
      </header>
      ${page.id === "settings" ? renderStandardOptionsAccessory() : ""}
      <div class="sections">
        ${(page.sections ?? []).map((section) => renderSection(section)).join("")}
      </div>
    </article>
  `;
}

function renderSection(section) {
  const key = `section:${section.id}`;
  if (section.dataSource) {
    ensureDataSource(key, section.dataSource, commandContext(section));
  }
  const sectionValues = state.dataSourcePayloads.get(key)?.values ?? {};
  const context = commandContext(section, {}, sectionValues);
  return `
    <section class="card" aria-labelledby="section-${escapeAttribute(section.id)}">
      <header class="section-header">
        ${
          section.title
            ? `<h3 id="section-${escapeAttribute(section.id)}">${renderIconTitle(section.title, section.iconName, section.iconEmoji, "▦")}</h3>`
            : ""
        }
        ${section.subtitle ? `<p>${escapeHTML(section.subtitle)}</p>` : ""}
      </header>
      <div class="controls">
        ${(section.controls ?? []).map((control) => renderControl(control, section, context)).join("")}
      </div>
      ${state.loadingDataSources.has(key) ? renderLoadingBox(state.labels.loadingTitle) : ""}
      ${
        state.dataSourceErrors.has(key)
          ? renderInlineError(state.dataSourceErrors.get(key), `<button type="button" data-retry-source="${escapeAttribute(key)}">${escapeHTML(
              state.labels.retryButtonTitle,
            )}</button>`)
          : ""
      }
      ${(section.actions ?? []).length ? `<div class="action-row">${renderActions(section.actions, context)}</div>` : ""}
    </section>
  `;
}

function renderControl(control, section, sectionContext) {
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
      ${
        error
          ? renderInlineError(error, `<button type="button" data-retry-source="${escapeAttribute(key)}">${escapeHTML(state.labels.retryButtonTitle)}</button>`)
          : ""
      }
    </div>
  `;
}

function renderTextControl(control) {
  const input = `<input type="text" value="${escapeAttribute(state.fieldValues[control.id] ?? control.value ?? "")}"
        placeholder="${escapeAttribute(control.placeholder ?? "")}" data-field-id="${escapeAttribute(control.id)}">`;
  return `
    <label class="form-row">
      <span class="row-label">${escapeHTML(control.label)}${renderTooltip(control.tooltip)}</span>
      ${
        control.kind === "path"
          ? `<span class="input-button-row">${input}<button type="button" class="secondary-button" data-path-prompt="${escapeAttribute(control.id)}">${escapeHTML(
              state.labels.chooseButtonTitle,
            )}</button></span>`
          : input
      }
    </label>
  `;
}

function renderDropdownControl(control) {
  const value = state.fieldValues[control.id] ?? control.value ?? control.options?.find((option) => option.selected)?.id ?? "";
  return `
    <label class="form-row">
      <span class="row-label">${escapeHTML(control.label)}${renderTooltip(control.tooltip)}</span>
      <select data-field-id="${escapeAttribute(control.id)}">
        ${(control.options ?? [])
          .map(
            (option) =>
              `<option value="${escapeAttribute(option.id)}" ${option.id === value ? "selected" : ""}>${escapeHTML(displayOption(option))}</option>`,
          )
          .join("")}
      </select>
    </label>
  `;
}

function renderToggleControl(control) {
  const checked = (state.fieldValues[control.id] ?? control.value ?? "") === "true";
  return `
    <label class="toggle-row">
      <span class="row-label">${escapeHTML(control.label)}${renderTooltip(control.tooltip)}</span>
      <input type="checkbox" ${checked ? "checked" : ""} data-field-id="${escapeAttribute(control.id)}" data-toggle>
    </label>
  `;
}

function renderCheckboxGroup(control) {
  const selected = state.checkedOptions[control.id] ?? new Set((control.options ?? []).filter((option) => option.selected).map((option) => option.id));
  return `
    <fieldset class="checkbox-group">
      <legend>${escapeHTML(control.label)}${renderTooltip(control.tooltip)}</legend>
      <div class="option-grid">
        ${(control.options ?? [])
          .map(
            (option) => `
            <label>
              <input type="checkbox" data-check-group="${escapeAttribute(control.id)}" value="${escapeAttribute(option.id)}" ${
                selected.has(option.id) ? "checked" : ""
              }>
              <span>${escapeHTML(displayOption(option))}</span>
            </label>`,
          )
          .join("")}
      </div>
    </fieldset>
  `;
}

function renderInfoGrid(control) {
  return `
    <div>
      <div class="control-label">${escapeHTML(control.label)}${renderTooltip(control.tooltip)}</div>
      <div class="info-grid">
        ${(control.options ?? []).map((option) => `<div>${escapeHTML(displayOption(option))}</div>`).join("")}
      </div>
    </div>
  `;
}

function renderLibraryList(control, context) {
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
      ${
        rows.length
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
                      ${
                        (control.rowActions ?? []).length
                          ? `<td><div class="row-actions">${renderActions(control.rowActions, contextForRow, true)}</div></td>`
                          : ""
                      }
                    </tr>`;
                  })
                  .join("")}
              </tbody>
            </table></div>`
          : `<p class="empty">No library items are defined.</p>`
      }
    </div>
  `;
}

function renderConfigEditor(control) {
  return `
    <div class="config-editor">
      <div class="control-label">${escapeHTML(control.label)}${renderTooltip(control.tooltip)}</div>
      ${
        control.configFile
          ? `<label class="form-row">
              <span class="row-label">${escapeHTML(state.labels.settingsFileLabel)}</span>
              <span class="input-button-row">
                <input type="text" class="mono" value="${escapeAttribute(state.configFilePaths[control.id] ?? control.configFile.path)}"
                  data-config-path="${escapeAttribute(control.id)}">
                <button type="button" class="secondary-button" data-load-config="${escapeAttribute(control.id)}">${escapeHTML(state.labels.loadButtonTitle)}</button>
              </span>
            </label>
            <button type="button" class="visually-hidden" data-save-config="${escapeAttribute(control.id)}">${escapeHTML(state.labels.saveButtonTitle)}</button>`
          : ""
      }
      ${(control.settings ?? []).map((setting) => renderConfigSetting(control, setting)).join("")}
    </div>
  `;
}

function renderConfigSetting(control, setting) {
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
  return `
    <label class="form-row">
      <span class="row-label">${escapeHTML(setting.label)}${renderTooltip(setting.tooltip)}</span>
      ${
        setting.kind === "path"
          ? `<span class="input-button-row"><input type="text" value="${escapeAttribute(value)}" placeholder="${escapeAttribute(setting.placeholder ?? "")}" ${common}>
              <button type="button" class="secondary-button" data-config-path-prompt="${escapeAttribute(control.id)}:${escapeAttribute(setting.id)}">${escapeHTML(
                state.labels.chooseButtonTitle,
              )}</button></span>`
          : `<input type="text" value="${escapeAttribute(value)}" placeholder="${escapeAttribute(setting.placeholder ?? "")}" ${common}>`
      }
    </label>
  `;
}

function renderActions(actions, context, compact = false) {
  return actions
    .filter((action) => isActionVisible(action, context))
    .map((action) => {
      const missing = missingPlaceholders(action.command, context);
      const disabled = disabledReason(action, context);
      const precheckKey = action.precheck ? actionPrecheckKey(action, context) : "";
      const precheck = action.precheck ? ensureActionPrecheck(precheckKey, action.precheck, context) : null;
      const isLoadingPrecheck = precheckKey ? state.loadingActionPrechecks.has(precheckKey) : false;
      const precheckWarning = precheck?.severity === "warning" ? precheck.message : undefined;
      const disabledText = missing.length ? `Missing: ${missing.join(", ")}` : disabled ?? precheckWarning;
      const command = displayCommand(action.command, context);
      const roleClass = action.role === "destructive" ? "danger" : action.role === "secondary" ? "secondary" : "primary";
      return `
        <span class="action-stack ${compact ? "compact" : ""}">
          ${precheck ? renderPrecheckBanner(precheck) : isLoadingPrecheck ? renderLoadingInline(state.labels.refreshingTitle) : ""}
          ${
            state.actionPrecheckErrors.has(precheckKey)
              ? renderInlineError(state.actionPrecheckErrors.get(precheckKey))
              : ""
          }
          <button type="button" class="action-button ${roleClass} ${compact ? "compact" : ""} ${action.iconOnly ? "icon-only" : ""}" data-action-id="${escapeAttribute(
            action.id,
          )}"
            data-action="${escapeAttribute(JSON.stringify(action))}"
            data-action-context="${escapeAttribute(JSON.stringify(context))}" title="${escapeAttribute(disabledText ?? action.tooltip ?? command)}"
            ${disabledText || isLoadingPrecheck ? "disabled" : ""}>
            <span class="action-icon" aria-hidden="true">${renderIcon(action.iconName, action.iconEmoji, "▶")}</span>
            <span>${escapeHTML(action.iconOnly ? "" : action.title)}</span>
          </button>
        </span>
      `;
    })
    .join("");
}

function renderPrecheckBanner(precheck) {
  const icon = precheck.severity === "warning" ? "⚠️" : "💽";
  return `
    <span class="precheck-banner ${escapeAttribute(precheck.severity)}">
      <span aria-hidden="true">${icon}</span>
      <span><strong>${escapeHTML(precheck.title)}</strong><span>${escapeHTML(precheck.message)}</span></span>
    </span>
  `;
}

function renderRowCell(row, column) {
  const value = column.id === "name" ? row.title ?? row.values?.[column.id] ?? row.id : column.id === "status" ? localizedStatus(row.status ?? row.values?.status ?? "") : row.values?.[column.id] ?? "";
  const tags =
    column.id === "name"
      ? [
          row.status ? `<span class="pill ${tagStyle(row.status)}">${escapeHTML(localizedStatus(row.status))}</span>` : "",
          ...(row.tags ?? []).map((tag) => `<span class="pill ${escapeAttribute(tag.style ?? "secondary")}">${escapeHTML(localizedTag(tag))}</span>`),
        ].join("")
      : "";
  return `<div>${escapeHTML(value)}${tags ? `<div class="pill-row">${tags}</div>` : ""}</div>`;
}

function renderTerminal() {
  const entry = terminalTabs()[state.activeTerminalIndex] ?? terminalTabs()[0];
  return `<pre>${escapeHTML(entry.body)}</pre>`;
}

function renderTerminalPane() {
  const tabs = terminalTabs();
  return `
    <section class="terminal-panel" aria-label="${escapeHTML(state.labels.terminalCommandOutputLabel)}">
      <header class="terminal-header">
        <span class="terminal-glyph" aria-hidden="true">⌘</span>
        <div class="terminal-tabs">
          ${tabs
            .map(
              (tab, index) => `
              <span class="terminal-tab-wrap ${index === state.activeTerminalIndex ? "active" : ""} ${escapeAttribute(tab.kind)}">
                <button type="button" class="terminal-tab" data-terminal-tab="${index}" ${
                  tab.status ? `data-tooltip="${escapeAttribute(terminalStatusTooltip(tab.status))}"` : ""
                }>
                  ${tab.kind === "command" ? `<span class="mini-spinner" aria-hidden="true"></span>` : terminalStatusGlyph(tab.kind, tab.status)}
                  <span>${escapeHTML(tab.title)}</span>
                </button>
                ${
                  tab.kind === "main"
                    ? ""
                    : `<button type="button" class="terminal-tab-close" data-terminal-tab-close="${index}" aria-label="Close ${escapeAttribute(
                        tab.title,
                      )}">×</button>`
                }
              </span>`,
            )
            .join("")}
        </div>
      </header>
      <div class="terminal-log">${renderTerminal()}</div>
    </section>
  `;
}

function renderTooltip(text) {
  return text
    ? `<span class="tooltip" tabindex="0" role="button" aria-label="${escapeAttribute(text)}" data-tooltip="${escapeAttribute(
        text,
      )}">i</span>`
    : "";
}

function renderInlineError(message, accessory = "") {
  return `<div class="inline-error"><span aria-hidden="true">⚠</span><span>${escapeHTML(message)}</span>${accessory}</div>`;
}

function renderLoadingInline(message) {
  return `<p class="loading-inline"><span class="spinner small" aria-hidden="true"></span>${escapeHTML(message)}</p>`;
}

function renderLoadingBox(message) {
  return `<div class="loading-box"><span class="spinner small" aria-hidden="true"></span>${escapeHTML(message)}</div>`;
}

function renderStandardOptionsAccessory() {
  const currentName = state.localizationOptions.find((option) => option.code === state.localizationCode)?.displayName ?? state.localizationCode;
  return `
    <section class="card standard-options-card">
      <header class="section-header">
        <h3>${renderIconTitle(state.labels.standardOptionsSectionTitle, "slider.horizontal.3", undefined, "⚙️")}</h3>
      </header>
      <div class="controls">
        ${
          state.localizationOptions.length > 1
            ? `<label class="form-row">
                <span class="row-label">${escapeHTML(state.labels.languagePickerLabel)}</span>
                <span>
                  <select data-locale-picker aria-label="${escapeAttribute(state.labels.languagePickerLabel)}">
                    ${state.localizationOptions
                      .map(
                        (option) =>
                          `<option value="${escapeAttribute(option.code)}" ${option.code === state.localizationCode ? "selected" : ""}>${escapeHTML(
                            option.displayName,
                          )}</option>`,
                      )
                      .join("")}
                  </select>
                  <span class="field-note">${escapeHTML(currentName)}</span>
                </span>
              </label>`
            : ""
        }
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

function renderConfirmationDialog() {
  const { action, context, input = "" } = state.pendingConfirmation;
  const confirmation = action.confirm;
  const requiredText = resolveText(confirmation.requiredText ?? "", context);
  const canConfirm = !requiredText || input === requiredText;
  return `
    <div class="modal-backdrop" role="presentation">
      <section class="confirmation-modal" role="dialog" aria-modal="true" aria-labelledby="confirm-title">
        <h2 id="confirm-title">${renderIconTitle(resolveText(confirmation.title ?? action.title, context), action.role === "destructive" ? "exclamationmark.triangle.fill" : action.iconName, action.iconEmoji, "?")}</h2>
        ${confirmation.message ? `<p>${escapeHTML(resolveText(confirmation.message, context))}</p>` : ""}
        ${
          requiredText
            ? `<label class="form-row stacked">
                <span>${escapeHTML(resolveText(confirmation.prompt ?? `Type "${requiredText}" to confirm.`, context))}</span>
                <input type="text" data-confirm-input value="${escapeAttribute(input)}" placeholder="${escapeAttribute(resolveText(requiredText, context))}" autofocus>
              </label>`
            : ""
        }
        <div class="modal-actions">
          <button type="button" class="secondary-button" data-confirm-cancel>${escapeHTML(confirmation.cancelButtonTitle ?? "Cancel")}</button>
          <button type="button" class="action-button ${action.role === "destructive" ? "danger" : "primary"}" data-confirm-run ${canConfirm ? "" : "disabled"}>${escapeHTML(
            confirmation.confirmButtonTitle ?? action.title,
          )}</button>
        </div>
      </section>
    </div>
  `;
}

function bindEvents() {
  bindTooltipEvents();
  bindSplitters();
  elements("[data-page-id]").forEach((button) => {
    button.addEventListener("click", () => {
      state.activePageID = button.dataset.pageId;
      render();
    });
  });
  elements<HTMLSelectElement>("[data-locale-picker]").forEach((picker) => {
    picker.addEventListener("change", async (event) => {
      const target = event.currentTarget as HTMLSelectElement;
      state.dataSourcePayloads.clear();
      state.dataSourceErrors.clear();
      state.localizationCode = target.value;
      await persistBundleState();
      await bootstrap(target.value);
    });
  });
  app.querySelector<HTMLSelectElement>("[data-icon-set-picker]")?.addEventListener("change", async (event) => {
    state.iconSet = normalizeIconSet((event.currentTarget as HTMLSelectElement).value);
    await persistBundleState();
    render();
  });
  app.querySelector<HTMLSelectElement>("[data-color-theme-picker]")?.addEventListener("change", async (event) => {
    state.colorTheme = normalizeColorTheme((event.currentTarget as HTMLSelectElement).value);
    await persistBundleState();
    render();
  });
  elements<HTMLInputElement>("[data-field-id]").forEach((input) => {
    input.addEventListener("change", async () => {
      const control = findControl(input.dataset.fieldId);
      await fieldValueChanged(input.dataset.toggle != null ? String(input.checked) : input.value, control);
      state.dataSourcePayloads.clear();
      render();
    });
  });
  elements("[data-path-prompt]").forEach((button) => {
    button.addEventListener("click", async () => {
      const id = button.dataset.pathPrompt;
      const value = window.prompt(state.labels.chooseButtonTitle, state.fieldValues[id] ?? "");
      if (value != null) {
        await fieldValueChanged(value, findControl(id));
        state.dataSourcePayloads.clear();
        render();
      }
    });
  });
  elements<HTMLInputElement>("[data-check-group]").forEach((input) => {
    input.addEventListener("change", async () => {
      const selected = state.checkedOptions[input.dataset.checkGroup] ?? new Set();
      input.checked ? selected.add(input.value) : selected.delete(input.value);
      await checkedOptionsChanged(selected, findControl(input.dataset.checkGroup));
      state.dataSourcePayloads.clear();
      render();
    });
  });
  elements<HTMLInputElement>("[data-config-path]").forEach((input) => {
    input.addEventListener("change", async () => {
      state.configFilePaths[input.dataset.configPath] = input.value;
      await persistBundleState();
    });
  });
  elements<HTMLInputElement>("[data-config-control][data-config-setting]").forEach((input) => {
    input.addEventListener("change", async () => {
      const control = findControl(input.dataset.configControl);
      const setting = control.settings.find((candidate) => candidate.id === input.dataset.configSetting);
      const value = input.dataset.toggle != null ? String(input.checked) : input.value;
      await configSettingChanged(value, setting, control);
      state.dataSourcePayloads.clear();
      render();
    });
  });
  elements("[data-config-path-prompt]").forEach((button) => {
    button.addEventListener("click", async () => {
      const [controlID, settingID] = button.dataset.configPathPrompt.split(":");
      const control = findControl(controlID);
      const setting = control.settings.find((candidate) => candidate.id === settingID);
      const key = configValueKey(control, setting);
      const value = window.prompt(state.labels.chooseButtonTitle, state.configValues[key] ?? "");
      if (value != null) {
        await configSettingChanged(value, setting, control);
        state.dataSourcePayloads.clear();
        render();
      }
    });
  });
  elements("[data-load-config]").forEach((button) => {
    button.addEventListener("click", async () => {
      await loadConfig(findControl(button.dataset.loadConfig));
      render();
    });
  });
  elements("[data-save-config]").forEach((button) => {
    button.addEventListener("click", async () => {
      await saveConfig(findControl(button.dataset.saveConfig), true);
      render();
    });
  });
  elements("[data-action-id]").forEach((button) => {
    button.addEventListener("click", async () => {
      const action = JSON.parse(button.dataset.action);
      const context = JSON.parse(button.dataset.actionContext);
      await runAction(action, context);
    });
  });
  elements("[data-terminal-tab]").forEach((button) => {
    button.addEventListener("click", () => {
      state.activeTerminalIndex = Number(button.dataset.terminalTab);
      render();
    });
  });
  elements("[data-terminal-tab-close]").forEach((button) => {
    button.addEventListener("click", () => {
      closeTerminalTab(Number(button.dataset.terminalTabClose));
      render();
    });
  });
  app.querySelector("[data-terminal-toggle]")?.addEventListener("click", () => {
    state.isTerminalVisible = !state.isTerminalVisible;
    render();
  });
  elements("[data-retry-source]").forEach((button) => {
    button.addEventListener("click", () => {
      state.dataSourceErrors.delete(button.dataset.retrySource);
      render();
    });
  });
  app.querySelector("[data-confirm-cancel]")?.addEventListener("click", () => {
    state.pendingConfirmation = null;
    render();
  });
  app.querySelector<HTMLInputElement>("[data-confirm-input]")?.addEventListener("input", (event) => {
    const target = event.currentTarget as HTMLInputElement;
    state.pendingConfirmation.input = target.value;
    const requiredText = resolveText(state.pendingConfirmation.action.confirm.requiredText ?? "", state.pendingConfirmation.context);
    const button = app.querySelector<HTMLButtonElement>("[data-confirm-run]");
    if (button) {
      button.disabled = Boolean(requiredText && target.value !== requiredText);
    }
  });
  app.querySelector("[data-confirm-run]")?.addEventListener("click", async () => {
    const pending = state.pendingConfirmation;
    state.pendingConfirmation = null;
    await runAction({ ...pending.action, confirm: undefined }, pending.context);
  });
}

function bindSplitters() {
  app.querySelector("[data-sidebar-resizer]")?.addEventListener("pointerdown", (event: Event) => {
    const pointerEvent = event as PointerEvent;
    event.preventDefault();
    const startX = pointerEvent.clientX;
    const startWidth = state.sidebarWidth;
    document.body.classList.add("resizing-sidebar");
    const move = (moveEvent: PointerEvent) => {
      state.sidebarWidth = clamp(startWidth + moveEvent.clientX - startX, 160, 420);
      app.style.setProperty("--sidebar-width", `${state.sidebarWidth}px`);
    };
    const up = () => {
      localStorage.setItem("guiForCLI.sidebarWidth", String(Math.round(state.sidebarWidth)));
      document.body.classList.remove("resizing-sidebar");
      window.removeEventListener("pointermove", move);
      window.removeEventListener("pointerup", up);
    };
    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", up, { once: true });
  });

  app.querySelector("[data-terminal-resizer]")?.addEventListener("pointerdown", (event: Event) => {
    const pointerEvent = event as PointerEvent;
    event.preventDefault();
    const startY = pointerEvent.clientY;
    const startHeight = state.terminalHeight;
    document.body.classList.add("resizing-terminal");
    const move = (moveEvent: PointerEvent) => {
      state.terminalHeight = clamp(startHeight - (moveEvent.clientY - startY), 96, Math.max(96, window.innerHeight - 260));
      app.style.setProperty("--terminal-height", `${state.terminalHeight}px`);
    };
    const up = () => {
      localStorage.setItem("guiForCLI.terminalHeight", String(Math.round(state.terminalHeight)));
      document.body.classList.remove("resizing-terminal");
      window.removeEventListener("pointermove", move);
      window.removeEventListener("pointerup", up);
    };
    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", up, { once: true });
  });
}

function bindTooltipEvents() {
  elements("[data-tooltip]").forEach((target) => {
    target.addEventListener("mouseenter", () => showFloatingTooltip(target));
    target.addEventListener("mouseleave", hideFloatingTooltip);
    target.addEventListener("focus", () => showFloatingTooltip(target));
    target.addEventListener("blur", hideFloatingTooltip);
    target.addEventListener("keydown", (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        hideFloatingTooltip();
        target.blur();
      }
    });
  });
}

function showFloatingTooltip(target) {
  const text = target.dataset.tooltip?.trim();
  if (!text) {
    return;
  }
  hideFloatingTooltip();
  const tooltip = document.createElement("div");
  tooltip.className = "floating-tooltip";
  tooltip.setAttribute("role", "tooltip");
  tooltip.textContent = text;
  document.body.append(tooltip);
  activeTooltip = { target, tooltip };

  const update = () => positionFloatingTooltip(target, tooltip);
  const raf = requestAnimationFrame(update);
  window.addEventListener("resize", update);
  window.addEventListener("scroll", update, true);
  tooltipCleanup = () => {
    cancelAnimationFrame(raf);
    window.removeEventListener("resize", update);
    window.removeEventListener("scroll", update, true);
  };
}

function hideFloatingTooltip() {
  tooltipCleanup();
  tooltipCleanup = () => {};
  activeTooltip?.tooltip.remove();
  activeTooltip = null;
}

function positionFloatingTooltip(target, tooltip) {
  if (!document.body.contains(target)) {
    hideFloatingTooltip();
    return;
  }
  const margin = 12;
  const gap = 8;
  tooltip.style.maxWidth = `${Math.min(420, Math.max(260, window.innerWidth - margin * 2))}px`;
  tooltip.style.left = "0px";
  tooltip.style.top = "0px";
  const targetRect = target.getBoundingClientRect();
  const tooltipRect = tooltip.getBoundingClientRect();
  const preferredLeft = targetRect.left + targetRect.width / 2 - tooltipRect.width / 2;
  const left = Math.min(Math.max(margin, preferredLeft), window.innerWidth - tooltipRect.width - margin);
  const belowTop = targetRect.bottom + gap;
  const aboveTop = targetRect.top - tooltipRect.height - gap;
  const top = belowTop + tooltipRect.height + margin <= window.innerHeight ? belowTop : Math.max(margin, aboveTop);
  tooltip.style.left = `${left}px`;
  tooltip.style.top = `${top}px`;
}

async function loadConfig(control) {
  try {
    const result = await api("/api/config/load", {
      method: "POST",
      body: { control, path: state.configFilePaths[control.id] },
    });
    state.configFilePaths[control.id] = result.path;
    for (const setting of control.settings ?? []) {
      const value = result.values[setting.key] ?? setting.value ?? "";
      state.configValues[configValueKey(control, setting)] = value;
      syncSharedField(setting, value);
    }
    appendTerminal("config", `Loaded settings from ${result.path}`);
  } catch (error) {
    appendTerminal("error", `Could not load ${control.label}: ${error.message}`);
  }
}

async function fieldValueChanged(value, control) {
  state.fieldValues[control.id] = value;
  const bindings = configSettingBindings(control.id);
  if (!bindings.length) {
    await persistBundleState();
    return;
  }
  await persistBundleState({ removeFieldIDs: [control.id] });
  for (const binding of bindings) {
    state.configValues[configValueKey(binding.control, binding.setting)] = value;
    await saveConfig(binding.control);
  }
}

async function checkedOptionsChanged(selectedIDs, control) {
  state.checkedOptions[control.id] = selectedIDs;
  const bindings = configSettingBindings(control.id);
  const value = [...selectedIDs].sort().join(",");
  if (!bindings.length) {
    await persistBundleState();
    return;
  }
  await persistBundleState({ removeCheckedIDs: [control.id] });
  for (const binding of bindings) {
    state.configValues[configValueKey(binding.control, binding.setting)] = value;
    await saveConfig(binding.control);
  }
}

async function configSettingChanged(value, setting, control) {
  state.configValues[configValueKey(control, setting)] = value;
  const fieldKey = boundFieldKey(setting);
  if (fieldKey) {
    state.fieldValues[fieldKey] = value;
    await persistBundleState({ removeFieldIDs: [fieldKey] });
  }
  await saveConfig(control);
}

async function saveConfig(control, reportSuccess = false) {
  try {
    const values = Object.fromEntries(
      (control.settings ?? []).map((setting) => [setting.key, state.configValues[configValueKey(control, setting)] ?? setting.value ?? ""]),
    );
    const result = await api("/api/config/save", {
      method: "POST",
      body: { control, path: state.configFilePaths[control.id], values },
    });
    state.configFilePaths[control.id] = result.path;
    if (reportSuccess) {
      appendTerminal("config", `Saved ${result.keyCount} setting(s) to ${result.path}`);
    }
  } catch (error) {
    appendTerminal("error", `Could not save ${control.label}: ${error.message}`);
  }
}

async function runAction(action, context) {
  if (action.confirm) {
    state.pendingConfirmation = { action, context, input: "" };
    render();
    return;
  }
  const runningID = appendTerminal("command", action.title, displayCommand(action.command, context));
  const controller = new AbortController();
  runningActionControllers.set(runningID, controller);
  render();
  try {
    const result = await api("/api/run", { method: "POST", body: { action, context }, signal: controller.signal });
    const runningIndex = state.terminalEntries.findIndex((entry) => entry.id === runningID);
    if (runningIndex < 0) {
      return;
    }
    const status = result.exitCode === 0 ? null : terminalExitStatus(result.exitCode, result.command);
    state.terminalEntries[runningIndex] = {
      id: runningID,
      kind: result.exitCode === 0 ? "success" : status.severity,
      title: action.title,
      command: result.command,
      body: [`$ ${result.command}`, result.stdout, result.stderr, `exit ${result.exitCode}`].filter(Boolean).join("\n"),
      status,
    };
  } catch (error) {
    if (error.name === "AbortError") {
      return;
    }
    const runningIndex = state.terminalEntries.findIndex((entry) => entry.id === runningID);
    if (runningIndex < 0) {
      return;
    }
    state.terminalEntries[runningIndex] = {
      id: runningID,
      kind: "error",
      title: action.title,
      command: displayCommand(action.command, context),
      body: error.message,
      status: terminalProcessErrorStatus(displayCommand(action.command, context), error.message),
    };
  } finally {
    runningActionControllers.delete(runningID);
  }
  state.dataSourcePayloads.clear();
  render();
}

function ensureDataSource(key, dataSource, context) {
  if (state.dataSourcePayloads.has(key) || state.dataSourceErrors.has(key) || state.loadingDataSources.has(key)) {
    return;
  }
  state.loadingDataSources.add(key);
  api("/api/datasource", { method: "POST", body: { dataSource, context } })
    .then((payload) => {
      state.dataSourcePayloads.set(key, payload);
      selectDefaultDataSourceOption(key, payload);
      state.dataSourceErrors.delete(key);
    })
    .catch((error) => {
      state.dataSourceErrors.set(key, error.message);
    })
    .finally(() => {
      state.loadingDataSources.delete(key);
      render();
    });
}

function ensureActionPrecheck(key, precheck, context) {
  if (!key || state.actionPrechecks.has(key) || state.actionPrecheckErrors.has(key) || state.loadingActionPrechecks.has(key)) {
    return state.actionPrechecks.get(key) ?? null;
  }
  state.loadingActionPrechecks.add(key);
  api("/api/precheck", {
    method: "POST",
    body: { precheck, context, labels: state.labels },
  })
    .then((result) => {
      state.actionPrechecks.set(key, result);
      state.actionPrecheckErrors.delete(key);
    })
    .catch((error) => {
      state.actionPrecheckErrors.set(key, error.message);
    })
    .finally(() => {
      state.loadingActionPrechecks.delete(key);
      render();
    });
  return null;
}

function actionPrecheckKey(action, context) {
  return JSON.stringify({
    actionID: action.id,
    precheck: action.precheck,
    fieldValues: context.fieldValues,
    checkedOptions: context.checkedOptions,
    configValues: context.configValues,
    rowValues: context.rowValues,
    bundleRootPath: context.bundleRootPath,
  });
}

function selectDefaultDataSourceOption(key, payload) {
  const options = payload.options;
  if (!options?.length) {
    return;
  }
  const defaultValue = options.find((option) => option.selected)?.id ?? options[0].id;
  if (key.startsWith("control:")) {
    const controlID = key.slice("control:".length);
    const current = state.fieldValues[controlID]?.trim() ?? "";
    if (!current || !options.some((option) => option.id === current)) {
      state.fieldValues[controlID] = defaultValue;
    }
    return;
  }
  if (key.startsWith("setting:")) {
    const configKey = key.slice("setting:".length);
    const current = state.configValues[configKey]?.trim() ?? "";
    if (!current || !options.some((option) => option.id === current)) {
      state.configValues[configKey] = defaultValue;
    }
  }
}

function commandContext(_section, rowValues = {}, sectionValues = {}) {
  return {
    fieldValues: { ...state.fieldValues, ...sectionValues },
    checkedOptions: checkedOptionsForContext(state.checkedOptions),
    configValues: { ...state.configValues, ...state.fieldValues, ...sectionValues },
    rowValues,
    bundleRootPath: state.bundleRootPath,
  };
}

function configDataSourceContext(control) {
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

function syncSharedField(setting, value) {
  if (Object.hasOwn(state.fieldValues, setting.key)) {
    state.fieldValues[setting.key] = value;
  }
  if (Object.hasOwn(state.fieldValues, setting.id)) {
    state.fieldValues[setting.id] = value;
  }
}

function boundFieldKey(setting) {
  if (Object.hasOwn(state.fieldValues, setting.key)) return setting.key;
  if (Object.hasOwn(state.fieldValues, setting.id)) return setting.id;
  return undefined;
}

function configSettingBindings(fieldID) {
  return configEditorControls(state.manifest).flatMap((control) =>
    (control.settings ?? [])
      .filter((setting) => setting.id === fieldID || setting.key === fieldID)
      .map((setting) => ({ control, setting })),
  );
}

async function persistBundleState(options: Record<string, string[]> = {}) {
  const fieldValues = { ...state.fieldValues };
  for (const id of options.removeFieldIDs ?? []) {
    delete fieldValues[id];
  }
  const checkedOptions = Object.fromEntries(
    Object.entries(state.checkedOptions).map(([key, selected]) => [
      key,
      [...(selected instanceof Set ? selected : new Set(Array.isArray(selected) ? selected : []))].sort(),
    ]),
  );
  for (const id of options.removeCheckedIDs ?? []) {
    delete checkedOptions[id];
  }
  await api("/api/state/save", {
    method: "POST",
    body: {
      state: {
        localizationCode: state.localizationCode,
        configFilePaths: state.configFilePaths,
        fieldValues,
        checkedOptions,
        iconSet: state.iconSet,
        colorTheme: state.colorTheme,
      },
    },
  });
}

function appendTerminal(kind, title, body = "", command = "") {
  ensureMainTerminal();
  if (kind === "config") {
    const main = state.terminalEntries[0];
    main.body = [main.body, title, body].filter(Boolean).join("\n");
    state.activeTerminalIndex = 0;
    return "main";
  }
  const id = crypto.randomUUID();
  state.terminalEntries.push({ id, kind, title, body, command });
  state.terminalEntries = state.terminalEntries.slice(-40);
  state.activeTerminalIndex = Math.max(0, state.terminalEntries.length - 1);
  return id;
}

function elements<T extends Element = HTMLElement>(selector: string): T[] {
  return [...app.querySelectorAll<T>(selector)];
}

function findControl(id) {
  for (const page of state.manifest.pages ?? []) {
    for (const section of page.sections ?? []) {
      const control = (section.controls ?? []).find((candidate) => candidate.id === id);
      if (control) return control;
    }
  }
  return undefined;
}

function displayOption(option) {
  return option.status ? `${option.title} (${localizedStatus(option.status)})` : option.title;
}

function localizedStatus(status) {
  return state.labels.libraryStatusLabels?.[String(status).toLowerCase()] ?? status;
}

function localizedTag(tag) {
  return state.labels.libraryTagLabels?.[tag.id] ?? state.labels.libraryTagLabels?.[String(tag.title).toLowerCase()] ?? tag.title;
}

function tagStyle(status) {
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

function terminalTabs() {
  ensureMainTerminal();
  return state.terminalEntries;
}

function ensureMainTerminal() {
  if (state.terminalEntries[0]?.kind === "main") {
    state.terminalEntries[0].id ??= "main";
    state.terminalEntries[0].title = state.labels.terminalMainTabTitle ?? "Main";
    return;
  }
  state.terminalEntries.unshift({
    id: "main",
    kind: "main",
    title: state.labels.terminalMainTabTitle ?? "Main",
    body: "",
    command: "main",
  });
  state.activeTerminalIndex += 1;
}

function closeTerminalTab(index) {
  if (index <= 0 || index >= state.terminalEntries.length) {
    return;
  }
  const tab = state.terminalEntries[index];
  runningActionControllers.get(tab.id)?.abort();
  runningActionControllers.delete(tab.id);
  state.terminalEntries.splice(index, 1);
  if (state.activeTerminalIndex === index) {
    state.activeTerminalIndex = Math.max(0, index - 1);
  } else if (state.activeTerminalIndex > index) {
    state.activeTerminalIndex -= 1;
  }
  state.activeTerminalIndex = Math.min(state.activeTerminalIndex, state.terminalEntries.length - 1);
}

function terminalToggleTitle() {
  return state.isTerminalVisible ? state.labels.terminalHideOutputLabel : state.labels.terminalShowOutputLabel;
}

function terminalStatusGlyph(kind, status) {
  switch (kind) {
    case "success":
      return '<span class="terminal-status success" aria-hidden="true">●</span>';
    case "warning":
      return `<span class="terminal-status warning" aria-hidden="true">${status?.symbol ?? "▲"}</span>`;
    case "error":
      return `<span class="terminal-status error" aria-hidden="true">${status?.symbol ?? "●"}</span>`;
    case "config":
      return '<span class="terminal-status config" aria-hidden="true">●</span>';
    default:
      return "";
  }
}

function terminalExitStatus(exitCode, command) {
  const reference = state.exitCodeReference.get(Number(exitCode));
  const severity = reference?.severity === "warning" ? "warning" : "error";
  return {
    severity,
    symbol: severity === "warning" ? "▲" : "✕",
    title: reference?.title ?? `Exit code ${exitCode}`,
    blurb: reference?.summary ?? "The command exited with a non-zero status. Check the command output for details.",
    detail: `${command} exited with code ${exitCode}.`,
  };
}

function terminalProcessErrorStatus(command, message) {
  return {
    severity: "error",
    symbol: "✕",
    title: "Command failed",
    blurb: "The command could not complete.",
    detail: `${command}\n${message}`,
  };
}

function terminalStatusTooltip(status) {
  return `${status.title}\n${status.blurb}\n\n${status.detail}`;
}

function renderIconTitle(title, iconName, iconEmoji, fallback = "•") {
  return `<span class="icon-title"><span class="icon-title-icon" aria-hidden="true">${renderIcon(iconName, iconEmoji, fallback)}</span><span>${escapeHTML(title)}</span></span>`;
}

function renderIcon(iconName, iconEmoji, fallback) {
  const emoji = iconEmoji || emojiIconMap[iconName];
  const bootstrap = bootstrapIconMap[iconName];
  if (state.iconSet === "platform" && bootstrap) {
    return `<i class="bi bi-${escapeAttribute(bootstrap)} web-icon" aria-hidden="true"></i>`;
  }
  if (emoji) {
    return `<span class="emoji-icon">${escapeHTML(emoji)}</span>`;
  }
  if (bootstrap) {
    return `<i class="bi bi-${escapeAttribute(bootstrap)} web-icon" aria-hidden="true"></i>`;
  }
  return `<span class="emoji-icon">${escapeHTML(fallback)}</span>`;
}

function iconGlyph(iconName, fallback) {
  const map = {
    "doc.text": "📄",
    "point.3.connected.trianglepath.dotted": "🧬",
    terminal: "▸",
    hammer: "🔨",
    folder: "📁",
    "folder.badge.gearshape": "📁",
    gearshape: "⚙",
    checklist: "☑",
    globe: "🌐",
    "play.fill": "▶",
    play: "▶",
    "trash.fill": "🗑",
    "xmark": "×",
    "checkmark.seal": "✓",
    "rectangle.3.group": "▦",
    "exclamationmark.triangle.fill": "⚠",
  };
  return emojiIconMap[iconName] ?? map[iconName] ?? fallback;
}

function resolveText(value, context) {
  return String(value ?? "").replace(/\{\{([^}]+)\}\}/g, (_, raw) => {
    const placeholder = raw.trim();
    if (placeholder.startsWith("row.")) return context.rowValues?.[placeholder.slice(4)] ?? "";
    if (placeholder.startsWith("config.")) return context.configValues?.[placeholder.slice(7)] ?? "";
    return context.rowValues?.[placeholder] ?? context.fieldValues?.[placeholder] ?? context.configValues?.[placeholder] ?? "";
  });
}

function renderError(error) {
  app.dataset.state = "error";
  app.innerHTML = `<main class="loading-screen"><h1>Could not load Web UI</h1><p class="inline-error">${escapeHTML(error.message)}</p></main>`;
}
