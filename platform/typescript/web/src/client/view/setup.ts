import { escapeHTML } from "../dom.js";
import { formatLabel, renderIcon } from "../model.js";
import { state } from "../state.js";
import { setupToolSummary } from "./setup-tool-summary.js";

export function setupNeedsAttention() {
    const status = state.setupRun?.status;
    return (state.manifest?.setup?.steps ?? []).length > 0 && status !== "ok" && status !== "warning";
}

export function setupHasNeverRun() {
    return (state.manifest?.setup?.steps ?? []).length > 0 && !state.setupRun;
}

export function setupPageID() {
    return state.manifest?.pages?.find((page) => page.id === "settings")?.id ?? state.manifest?.pages?.[0]?.id ?? "";
}

export function setupPromptMessage() {
    const body = setupPromptBody();
    const toolSummary = setupPromptToolSummary();
    return toolSummary ? `${body}\n\n${toolSummary}` : body;
}
function setupPromptBody() {
    const appName = state.manifest?.displayName?.trim() ||
        state.labels.setupPromptAppNameFallback ||
        "This app";
    return formatLabel(state.labels.setupPromptBodyFormat ||
        "Do you want to run setup? %{app} will probably not work properly without running setup.", { app: appName });
}
function setupPromptToolSummary() {
    return (state.manifest?.setup?.steps ?? []).map((step) => setupToolSummary(step, state.labels)).find(Boolean);
}

export function renderSetupGlobalStatusBar() {
    if (!setupNeedsAttention()) {
        return "";
    }
    const isRunning = state.setupRun?.status === "running";
    const title = setupGlobalStatusTitle();
    const message = setupGlobalStatusMessage();
    return `
      <button type="button" class="setup-global-banner" data-setup-global-start>
        <span class="setup-global-icon" aria-hidden="true">${isRunning ? `<span class="mini-spinner"></span>` : "⚠"}</span>
        <span class="setup-global-copy">
          <strong>${escapeHTML(title)}</strong>
          <span>${escapeHTML(message)}</span>
        </span>
        <span class="setup-global-action">${escapeHTML(isRunning ? state.labels.setupRunningTitle ?? "Running setup..." : state.labels.setupRunButtonTitle ?? "Run Setup")}</span>
      </button>
    `;
}

export function renderSetupPromptDialog() {
    if (!state.setupPromptVisible) {
        return "";
    }
    const body = setupPromptBody();
    const toolSummary = setupPromptToolSummary();
    return `
      <div class="modal-backdrop" role="presentation">
        <section class="confirmation-modal setup-prompt-modal" role="alertdialog" aria-modal="true" aria-labelledby="setup-prompt-title">
          <h2 id="setup-prompt-title">${escapeHTML(state.labels.setupTitle ?? "Setup")}</h2>
          <p>${escapeHTML(body)}</p>
          ${toolSummary ? `<p class="setup-prompt-tool">${escapeHTML(toolSummary)}</p>` : ""}
          <div class="modal-actions">
            <button type="button" class="secondary-button" data-setup-prompt-dismiss autofocus>${escapeHTML(state.labels.terminalCancelButtonTitle ?? "Cancel")}</button>
            <button type="button" class="action-button primary" data-setup-prompt-run>${renderIcon("play.fill", undefined, "▶")}${escapeHTML(state.labels.setupRunButtonTitle ?? "Run Setup")}</button>
          </div>
        </section>
      </div>
    `;
}

function setupGlobalStatusTitle() {
    switch (state.setupRun?.status) {
        case "running":
            return state.labels.setupRunningTitle ?? "Running setup...";
        case "failed":
            return state.labels.setupStatusFailedTitle ?? "Setup failed. Review command output for details.";
        default:
            return state.labels.setupTitle ?? "Setup";
    }
}

function setupGlobalStatusMessage() {
    switch (state.setupRun?.status) {
        case "running":
            return state.labels.setupRunningTitle ?? "Running setup...";
        case "failed":
            return state.labels.setupStatusFailedTitle ?? "Setup failed. Review command output for details.";
        default:
            return state.labels.setupStatusReadyTitle ?? "Review and run this bundle's setup steps.";
    }
}
