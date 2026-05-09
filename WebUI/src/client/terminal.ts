import { escapeAttribute, escapeHTML } from "./dom.js";
import { formatLabel } from "./model.js";
import { state } from "./state.js";
export const runningActionControllers = new Map();
export function renderTerminal() {
    const entry = selectedTerminalEntry();
    return `<pre>${escapeHTML(entry.body)}</pre>`;
}
export function renderTerminalPane() {
    const tabs = terminalTabs();
    const selected = selectedTerminalEntry();
    const copyTitle = state.labels.terminalCopyOutputLabel ?? "Copy Output";
    return `
    <section class="terminal-panel" aria-label="${escapeHTML(state.labels.terminalCommandOutputLabel)}">
      <header class="terminal-header">
        <span class="terminal-glyph" aria-hidden="true">⌘</span>
        <div class="terminal-tabs">
          ${tabs
        .map((tab) => `
              <span class="terminal-tab-wrap ${tab.id === selected.id ? "active" : ""} ${escapeAttribute(tab.kind)}">
                <button type="button" class="terminal-tab" data-terminal-tab-id="${escapeAttribute(tab.id)}" ${tab.status ? `data-tooltip="${escapeAttribute(terminalStatusTooltip(tab.status))}"` : ""}>
                  ${tab.kind === "command" ? `<span class="mini-spinner" aria-hidden="true"></span>` : terminalStatusGlyph(tab.kind, tab.status)}
                  <span>${escapeHTML(tab.title)}</span>
                </button>
                ${tab.kind === "main"
        ? ""
        : `<button type="button" class="terminal-tab-close" data-terminal-tab-close-id="${escapeAttribute(tab.id)}" aria-label="${escapeAttribute(formatLabel(state.labels.terminalCloseTabLabelFormat, { title: tab.title }))}">×</button>`}
              </span>`)
        .join("")}
        </div>
        <button type="button" class="terminal-copy" data-terminal-copy ${selected.body ? "" : "disabled"} aria-label="${escapeAttribute(copyTitle)}" title="${escapeAttribute(copyTitle)}">
          <svg class="terminal-copy-icon" viewBox="0 0 16 16" aria-hidden="true" focusable="false">
            <path d="M4 2.5A1.5 1.5 0 0 1 5.5 1h6A1.5 1.5 0 0 1 13 2.5v8a1.5 1.5 0 0 1-1.5 1.5H10v1.5A1.5 1.5 0 0 1 8.5 15h-6A1.5 1.5 0 0 1 1 13.5v-8A1.5 1.5 0 0 1 2.5 4H4V2.5Zm1 0V4h3.5A1.5 1.5 0 0 1 10 5.5V11h1.5a.5.5 0 0 0 .5-.5v-8a.5.5 0 0 0-.5-.5h-6a.5.5 0 0 0-.5.5ZM2.5 5a.5.5 0 0 0-.5.5v8a.5.5 0 0 0 .5.5h6a.5.5 0 0 0 .5-.5v-8a.5.5 0 0 0-.5-.5h-6Z" />
          </svg>
        </button>
      </header>
      <div class="terminal-log">${renderTerminal()}</div>
    </section>
  `;
}
export function appendTerminal(kind, title, body = "", command = "") {
    ensureMainTerminal();
    if (kind === "config") {
        const main = state.terminalEntries[0];
        main.body = [main.body, title, body].filter(Boolean).join("\n");
        selectTerminalTab("main");
        return "main";
    }
    const id = crypto.randomUUID();
    state.terminalEntries.push({ id, kind, title, body, command });
    state.terminalEntries = state.terminalEntries.slice(-40);
    selectTerminalTab(id);
    return id;
}
export function terminalTabs() {
    ensureMainTerminal();
    return state.terminalEntries;
}
export function ensureMainTerminal() {
    if (state.terminalEntries[0]?.kind === "main") {
        state.terminalEntries[0].id ??= "main";
        state.terminalEntries[0].title = state.labels.terminalMainTabTitle ?? "Main";
        normalizeSelectedTerminal();
        return;
    }
    const hadEntries = state.terminalEntries.length > 0;
    state.terminalEntries.unshift({
        id: "main",
        kind: "main",
        title: state.labels.terminalMainTabTitle ?? "Main",
        body: "",
        command: "main",
    });
    if (!hadEntries) {
        selectTerminalTab("main");
    } else {
        normalizeSelectedTerminal();
    }
}
export function selectedTerminalEntry() {
    const tabs = terminalTabs();
    const index = normalizeSelectedTerminal();
    return tabs[index] ?? tabs[0];
}
export function selectedTerminalOutput() {
    return selectedTerminalEntry().body ?? "";
}
export function selectTerminalTab(id) {
    const tabs = terminalTabs();
    const index = tabs.findIndex((tab) => tab.id === id);
    if (index < 0) {
        normalizeSelectedTerminal();
        return;
    }
    state.activeTerminalID = tabs[index].id;
    state.activeTerminalIndex = index;
}
function normalizeSelectedTerminal() {
    const tabs = state.terminalEntries;
    const idIndex = tabs.findIndex((tab) => tab.id === state.activeTerminalID);
    if (idIndex >= 0) {
        state.activeTerminalIndex = idIndex;
        return idIndex;
    }
    const fallbackIndex = Math.min(Math.max(Number(state.activeTerminalIndex) || 0, 0), Math.max(tabs.length - 1, 0));
    state.activeTerminalID = tabs[fallbackIndex]?.id ?? "main";
    state.activeTerminalIndex = fallbackIndex;
    return fallbackIndex;
}
export function closeTerminalTab(id) {
    const index = terminalTabs().findIndex((tab) => tab.id === id);
    if (index <= 0 || index >= state.terminalEntries.length) {
        return;
    }
    const tab = state.terminalEntries[index];
    runningActionControllers.get(tab.id)?.abort();
    runningActionControllers.delete(tab.id);
    state.terminalEntries.splice(index, 1);
    if (state.activeTerminalID === id) {
        const nextIndex = Math.max(0, index - 1);
        selectTerminalTab(state.terminalEntries[nextIndex]?.id ?? "main");
    }
    else {
        normalizeSelectedTerminal();
    }
}
export function terminalToggleTitle() {
    return state.isTerminalVisible ? state.labels.terminalHideOutputLabel : state.labels.terminalShowOutputLabel;
}
export function terminalStatusGlyph(kind, status) {
    switch (kind) {
        case "success":
            return '<span class="terminal-status success" aria-hidden="true">●</span>';
        case "warning":
            return `<span class="terminal-status warning" aria-hidden="true">${escapeHTML(status?.symbol ?? "▲")}</span>`;
        case "error":
            return `<span class="terminal-status error" aria-hidden="true">${escapeHTML(status?.symbol ?? "●")}</span>`;
        case "config":
            return '<span class="terminal-status config" aria-hidden="true">●</span>';
        default:
            return "";
    }
}
export function terminalExitStatus(exitCode, command) {
    const reference = state.exitCodeReference.get(Number(exitCode));
    const severity = reference?.severity === "warning" ? "warning" : "error";
    return {
        severity,
        symbol: severity === "warning" ? "▲" : "✕",
        title: reference?.title ?? formatLabel(state.labels.terminalExitCodeTitleFormat, { code: exitCode }),
        blurb: reference?.summary ?? state.labels.terminalNonzeroExitSummary,
        detail: formatLabel(state.labels.terminalExitDetailFormat, { command, code: exitCode }),
    };
}
export function terminalProcessErrorStatus(command, message) {
    return {
        severity: "error",
        symbol: "✕",
        title: state.labels.terminalProcessErrorTitle,
        blurb: state.labels.terminalProcessErrorSummary,
        detail: `${command}\n${message}`,
    };
}
export function terminalStatusTooltip(status) {
    return `${status.title}\n${status.blurb}`;
}
