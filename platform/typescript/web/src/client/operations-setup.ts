import { setupResultLine } from "../../../shared/rendering.js";
import { api } from "./api.js";
import { errorMessage } from "./model.js";
import { scheduleRender } from "./rerender.js";
import { state } from "./state.js";
import { appendTerminal } from "./terminal.js";
import { persistBundleState } from "./operations-state.js";
import { resolveSetupPreflight } from "./operations-setup-preflight.js";

let setupElapsedTimer: ReturnType<typeof setInterval> | null = null;

export async function runSetup() {
    if (state.setupRun?.status === "running") {
        return;
    }
    const preflight = await resolveSetupPreflight();
    if (preflight?.severity === "warning") {
        const setupID = appendTerminal("error", preflight.title ?? state.labels.setupTitle ?? "Setup", preflight.message ?? "");
        state.activeTerminalID = setupID;
        state.setupRun = {
            status: "failed",
            results: [],
            ...(preflight.message != null ? { error: preflight.message } : {}),
            completedAt: new Date().toISOString(),
        };
        await persistBundleState();
        scheduleRender();
        return;
    }
    const setupID = appendTerminal("command", state.labels.setupTitle ?? "Setup", state.labels.setupRunningTitle ?? "Running setup...");
    state.activeTerminalID = setupID;
    clearSetupElapsedTimer();
    state.setupRun = { status: "running", results: [], currentStepID: null, currentStepStartedAt: null, currentStepElapsedMs: 0 };
    scheduleRender();
    const entry = () => state.terminalEntries.find((candidate) => candidate.id === setupID);
    try {
        const response = await fetch("/api/setup/stream", {
            method: "POST",
            headers: { "content-type": "application/json" },
            body: JSON.stringify({ locale: state.localizationCode }),
        });
        if (!response.ok) {
            throw new Error(response.statusText || `HTTP ${response.status}`);
        }
        if (!response.body) {
            throw new Error("Setup stream did not include a response body.");
        }
        const reader = response.body.pipeThrough(new TextDecoderStream()).getReader();
        let buffer = "";
        let sawComplete = false;
        while (true) {
            const { value, done } = await reader.read();
            if (done) {
                break;
            }
            buffer += value;
            const lines = buffer.split(/\r?\n/);
            buffer = lines.pop() ?? "";
            for (const line of lines) {
                if (line.trim()) {
                    const event = JSON.parse(line);
                    if (event?.type === "complete") {
                        sawComplete = true;
                    }
                    applySetupEvent(event, entry());
                }
            }
        }
        if (buffer.trim()) {
            const event = JSON.parse(buffer);
            if (event?.type === "complete") {
                sawComplete = true;
            }
            applySetupEvent(event, entry());
        }
        if (!sawComplete) {
            throw new Error("Setup stream ended before completion.");
        }
        if (state.setupRun?.status && state.setupRun.status !== "running") {
            await persistBundleState();
        }
    }
    catch (error) {
        clearSetupElapsedTimer();
        const tab = entry();
        if (tab) {
            tab.kind = "error";
            tab.body = [tab.body, errorMessage(error)].filter(Boolean).join("\n");
        }
        state.setupRun = { status: "failed", results: state.setupRun?.results ?? [], error: errorMessage(error), completedAt: new Date().toISOString() };
        await persistBundleState();
    }
    scheduleRender();
}
export async function openBundleWorkspace() {
    await api<void>("/api/open-bundle-workspace", { method: "POST", body: {} });
}
function applySetupEvent(event, tab) {
    if (!tab) {
        return;
    }
    switch (event.type) {
        case "step-start":
            startSetupElapsedTimer(event.step.id);
            state.setupRun = {
                ...(state.setupRun ?? {}),
                status: "running",
                currentStepID: event.step.id,
                currentStepStartedAt: new Date().toISOString(),
                currentStepElapsedMs: 0,
            };
            tab.body = [tab.body, `==> ${event.step.label}`, `$ ${event.step.command}\n`].filter(Boolean).join("\n");
            break;
        case "output":
            tab.body += event.text ?? "";
            break;
        case "step-complete":
            clearSetupElapsedTimer();
            state.setupRun = {
                ...(state.setupRun ?? {}),
                status: "running",
                currentStepID: null,
                currentStepStartedAt: null,
                currentStepElapsedMs: event.result.durationMs,
                results: [
                    ...(state.setupRun?.results ?? []).filter((result) => result.id !== event.result.id),
                    event.result,
                ],
            };
            tab.body = [tab.body, setupResultLine(event.result)].filter(Boolean).join("\n");
            break;
        case "complete":
            clearSetupElapsedTimer();
            state.setupRun = { ...event.result, completedAt: new Date().toISOString(), currentStepID: null, currentStepStartedAt: null, currentStepElapsedMs: 0 };
            tab.kind = event.result?.status === "failed" ? "error" : "success";
            if (event.result?.error) {
                tab.body = [tab.body, event.result.error].filter(Boolean).join("\n");
            }
            break;
    }
    scheduleRender();
}

function startSetupElapsedTimer(stepID) {
    clearSetupElapsedTimer();
    const startedAtMs = Date.now();
    setupElapsedTimer = setInterval(() => {
        if (state.setupRun?.status !== "running" || state.setupRun.currentStepID !== stepID) {
            clearSetupElapsedTimer();
            return;
        }
        state.setupRun = {
            ...state.setupRun,
            currentStepElapsedMs: Date.now() - startedAtMs,
        };
        scheduleRender();
    }, 1000);
}

function clearSetupElapsedTimer() {
    if (setupElapsedTimer == null) {
        return;
    }
    clearInterval(setupElapsedTimer);
    setupElapsedTimer = null;
}
