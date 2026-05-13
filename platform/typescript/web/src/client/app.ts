import { configEditorControls, initialCheckedOptions, initialConfigValues, initialFieldValues } from "../../../shared/rendering.js";
import { api } from "./api.js";
import { clamp, escapeAttribute, escapeHTML } from "./dom.js";
import { normalizeColorTheme, normalizeIconSet } from "./icons.js";
import { errorMessage } from "./model.js";
import { runSetup } from "./operations.js";
import { effectiveWebUIFont } from "./platform.js";
import { setRender } from "./rerender.js";
import { state } from "./state.js";
import { ensureMainTerminal, renderTerminalPane, terminalToggleTitle } from "./terminal.js";
import { renderBundleHeader, renderConfirmationDialog, renderNavigation, renderPage } from "./view.js";
const app = document.querySelector<HTMLElement>("#app");
if (!app) {
    throw new Error("Missing required root element: `#app`");
}
let bindEventsModulePromise: Promise<typeof import("./events.js")> | null = null;
setRender(render);
await bootstrap();
installDevReload();
async function bootstrap(locale?: string) {
    try {
        const bundle = await api(`/api/manifest${locale ? `?locale=${encodeURIComponent(locale)}` : ""}`);
        state.manifest = bundle.manifest;
        state.labels = bundle.labels;
        state.localizationCode = bundle.localizationCode;
        state.localizationOptions = bundle.localizationOptions;
        state.iconSet = normalizeIconSet(bundle.bundleState?.iconSet);
        state.colorTheme = normalizeColorTheme(bundle.bundleState?.colorTheme);
        state.webUIFont = bundle.bundleState?.webUIFont === "sfPro" ? "sfPro" : "system";
        state.setupRun = bundle.bundleState?.setupRun ?? null;
        state.exitCodeReference = new Map((bundle.manifest.exitCodeReference ?? []).map((entry) => [Number(entry.code), entry]));
        state.bundleRootPath = bundle.bundleRootPath;
        ensureMainTerminal();
        state.activePageID = validPageID(bundle.bundleState?.selectedPageID, bundle.manifest) ?? state.activePageID ?? bundle.manifest.pages[0]?.id;
        state.fieldValues = bundle.fieldValues ?? initialFieldValues(bundle.manifest);
        state.checkedOptions = Object.fromEntries(Object.entries(bundle.checkedOptions ?? {}).map(([key, value]) => [
            key,
            new Set(Array.isArray(value) ? value : []),
        ]));
        for (const [key, value] of Object.entries(initialCheckedOptions(bundle.manifest))) {
            state.checkedOptions[key] ??= value;
        }
        state.configValues = bundle.configValues ?? initialConfigValues(bundle.manifest);
        state.configFilePaths =
            bundle.configFilePaths ??
                Object.fromEntries(configEditorControls(bundle.manifest)
                    .filter((control) => control.configFile)
                    .map((control) => [control.id, control.configFile.path]));
        render();
        if (shouldAutoRunSetup(bundle)) {
            state.setupAutorunStarted = true;
            void runSetup();
        }
    }
    catch (error) {
        renderError(error);
    }
}
function validPageID(pageID: string | undefined | null, manifest: any) {
    return pageID && manifest.pages.some((page) => page.id === pageID) ? pageID : undefined;
}
function shouldAutoRunSetup(bundle: any) {
    return !state.setupAutorunStarted && (bundle.manifest.setup?.steps ?? []).length > 0 && !bundle.bundleState?.setupRun;
}
function render() {
    updateDocumentMetadata();
    document.documentElement.lang = state.localizationCode || "en";
    document.documentElement.dir = state.labels.layoutDirection || "ltr";
    applyDocumentPreferences();
    const activePage = state.manifest.pages.find((page) => page.id === state.activePageID) ?? state.manifest.pages[0];
    state.activePageID = activePage?.id;
    app.classList.toggle("terminal-hidden", !state.isTerminalVisible);
    app.classList.toggle("sidebar-hidden", !state.isSidebarVisible);
    app.style.setProperty("--sidebar-width", `${clamp(state.sidebarWidth, 160, 420)}px`);
    app.style.setProperty("--terminal-height", `${clamp(state.terminalHeight, 96, Math.max(96, window.innerHeight - 260))}px`);
    app.innerHTML = `
    ${state.isSidebarVisible
        ? `<aside class="sidebar">
      <button type="button" class="sidebar-toggle sidebar-toggle-inside" data-sidebar-toggle title="${escapeAttribute(sidebarToggleTitle())}" aria-label="${escapeAttribute(sidebarToggleTitle())}">◀</button>
      ${renderBundleHeader()}
      <nav class="page-nav" aria-label="Pages">${renderNavigation()}</nav>
    </aside>
    <div class="sidebar-resizer" data-sidebar-resizer role="separator" aria-orientation="vertical" aria-label="Resize sidebar" tabindex="0"></div>`
        : ""}
    <div class="detail-shell">
      <main class="page-panel">${activePage ? renderPage(activePage) : ""}</main>
      ${state.isTerminalVisible ? `<div class="terminal-resizer" data-terminal-resizer role="separator" aria-orientation="horizontal" aria-label="Resize command output" tabindex="0"></div>` : ""}
      ${state.isTerminalVisible ? renderTerminalPane() : ""}
      <button type="button" class="terminal-toggle" data-terminal-toggle title="${escapeAttribute(terminalToggleTitle())}" aria-label="${escapeAttribute(terminalToggleTitle())}">▭</button>
    </div>
    ${state.isSidebarVisible ? "" : `<button type="button" class="sidebar-toggle sidebar-toggle-floating" data-sidebar-toggle title="${escapeAttribute(sidebarToggleTitle())}" aria-label="${escapeAttribute(sidebarToggleTitle())}">▶</button>`}
    ${state.pendingConfirmation ? renderConfirmationDialog() : ""}
  `;
    app.dataset.state = "ready";
    window.dispatchEvent(new Event("gui-for-cli-rendered"));
    bindEventsAfterFirstPaint();
}
function sidebarToggleTitle() {
    return state.isSidebarVisible ? state.labels.sidebarHideLabel ?? "Hide Sidebar" : state.labels.sidebarShowLabel ?? "Show Sidebar";
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
    }
    else {
        delete document.documentElement.dataset.theme;
        document.documentElement.style.colorScheme = "light dark";
    }
    document.documentElement.dataset.font = effectiveWebUIFont(state.webUIFont);
}
function renderError(error: unknown) {
    const message = errorMessage(error);
    app.dataset.state = "error";
    app.innerHTML = `<main class="loading-screen"><h1>${escapeHTML(state.labels.loadWebUITitle ?? "Could not load Web UI")}</h1><p class="inline-error">${escapeHTML(message)}</p></main>`;
}
function installDevReload() {
    if (typeof EventSource === "undefined") {
        return;
    }
    const events = new EventSource("/api/dev/reload");
    events.addEventListener("reload", () => window.location.reload());
    events.addEventListener("error", () => events.close());
}
function bindEventsAfterFirstPaint() {
    requestAnimationFrame(() => {
        bindEventsModulePromise ??= import("./events.js");
        bindEventsModulePromise
            .then(({ bindEvents }) => bindEvents(bootstrap))
            .catch((error) => renderError(error));
    });
}
