import { homedir } from "node:os";
import { stdin, stdout } from "node:process";
import {
    activateSelected,
    editConfigSetting,
    editControl,
    runBundleAction,
    runSetupSteps,
} from "./app-actions.js";
import {
    persistBundleState,
    persistConfig,
    refreshDataSources,
    updateCheckedOptions,
    updateConfigSetting,
    updateField,
} from "./app-data.js";
import {
    focusPane,
    handleInput,
    movePage,
    moveSelection,
    resizeTerminal,
    scrollTerminal,
    toggleFocusPane,
} from "./app-input.js";
import { prompt, promptCheckboxes, promptOption, promptPath } from "./app-prompts.js";
import { clampSelectedItem, renderTUIScreen } from "./rendering.js";
import type { TUIColorTheme } from "./rendering-format.js";
import { resolveTerminalTheme, type TUIThemePreference } from "./theme.js";
import type { TUIAction, TUICommandContext, TUIConfigSetting, TUIControl, TUIBundle, TUIOption, TUIRunProcess, TUIState, TUITerminalEntry } from "./types.js";

export type TUIAppOptions = {
    runProcess: TUIRunProcess;
    terminateAllProcesses: () => void;
    theme?: TUIThemePreference;
    autoRunSetup?: boolean;
    resolveTheme?: (preference: TUIThemePreference) => TUIColorTheme;
};

export class TUIApp {
    state: TUIState;
    running = false;
    inputHandler: ((data: Buffer | string) => void) | undefined;
    resizeHandler: (() => void) | undefined;
    resizeTimer: ReturnType<typeof setTimeout> | undefined;
    lastFrameLines: string[] = [];
    fullRedraw = true;
    runProcess: TUIRunProcess;
    terminateAllProcesses: () => void;
    resolveTheme: (preference: TUIThemePreference) => TUIColorTheme;
    autoRunSetup: boolean;
    nextThemeCheckAt = 0;

    constructor(bundle: TUIBundle, options: TUIAppOptions) {
        this.runProcess = options.runProcess;
        this.terminateAllProcesses = options.terminateAllProcesses;
        this.resolveTheme = options.resolveTheme ?? resolveTerminalTheme;
        this.autoRunSetup = Boolean(options.autoRunSetup);
        const selectedPageID = bundle.bundleState?.selectedPageID;
        const pages = bundle.manifest?.pages ?? [];
        const activePageID = selectedPageID && pages.some((page) => page.id === selectedPageID) ? selectedPageID : pages[0]?.id ?? "";
        const terminalTheme = options.theme ?? "auto";
        this.state = {
            ...bundle,
            manifest: bundle.manifest,
            labels: bundle.labels ?? {},
            fieldValues: bundle.fieldValues ?? {},
            checkedOptions: bundle.checkedOptions ?? {},
            configValues: bundle.configValues ?? {},
            configFilePaths: bundle.configFilePaths ?? {},
            activePageID,
            selectedItemIndex: 0,
            dataSourcePayloads: new Map(),
            dataSourceErrors: new Map(),
            terminalEntries: [],
            selectedTerminalEntryIndex: -1,
            focusPane: "main",
            terminalTheme,
            terminalResolvedTheme: this.resolveTheme(terminalTheme),
            terminalHeightRows: 0,
            terminalScrollOffset: 0,
            homePath: homedir(),
            setupRun: bundle.bundleState?.setupRun ?? null,
        };
    }

    async run(once: boolean) {
        let interactive = false;
        try {
            if (once) {
                await this.refreshDataSources();
                stdout.write(`${renderTUIScreen(this.state, { columns: stdout.columns || 100, rows: stdout.rows || 32, color: stdout.isTTY, theme: this.currentRenderTheme() })}\n`);
                return;
            }
            interactive = true;
            this.running = true;
            stdout.write("\x1b[?1049h\x1b[?25l");
            this.startInput();
            this.startResizeWatcher();
            this.render();
            void this.runStartupTasksAfterFirstRender().catch((error) => {
                this.reportError(error);
            });
            while (this.running) {
                await new Promise((resolve) => setTimeout(resolve, 50));
                if (this.refreshTerminalTheme()) {
                    this.render();
                }
            }
        } finally {
            if (interactive) {
                this.running = false;
                this.stopResizeWatcher();
                this.stopInput();
                stdout.write("\x1b[?25h\x1b[?1049l");
            }
            this.terminateAllProcesses();
        }
    }

    async runStartupTasksAfterFirstRender() {
        if (this.shouldAutoRunSetup()) {
            this.state.setupAutorunStarted = true;
            await this.runSetupSteps();
            return;
        }
        await this.refreshDataSourcesAfterFirstRender();
    }

    shouldAutoRunSetup() {
        return (this.autoRunSetup &&
            !this.state.setupAutorunStarted &&
            (this.state.manifest?.setup?.steps ?? []).length > 0 &&
            !this.state.setupRun);
    }

    async refreshDataSourcesAfterFirstRender() {
        try {
            await this.refreshDataSources();
            if (this.running) {
                this.fullRedraw = true;
                this.render();
            }
        } catch (error) {
            this.reportError(error);
        }
    }

    close(exitCode = 0) {
        this.running = false;
        process.exitCode = exitCode;
    }

    render() {
        clampSelectedItem(this.state);
        const frame = renderTUIScreen(this.state, { columns: stdout.columns || 100, rows: stdout.rows || 32, color: true, theme: this.currentRenderTheme() });
        const nextLines = frame.split("\n");
        if (this.fullRedraw || !this.lastFrameLines.length) {
            stdout.write(`\x1b[2J\x1b[H\x1b[?25l${frame}`);
        } else {
            const maxLines = Math.max(this.lastFrameLines.length, nextLines.length);
            const writes: string[] = [];
            for (let index = 0; index < maxLines; index += 1) {
                const next = nextLines[index] ?? "";
                if (next !== (this.lastFrameLines[index] ?? "")) {
                    writes.push(`\x1b[${index + 1};1H${next}\x1b[K`);
                }
            }
            if (writes.length) {
                stdout.write(writes.join(""));
            }
        }
        this.lastFrameLines = nextLines;
        this.fullRedraw = false;
    }

    currentRenderTheme() {
        const preference = this.state.terminalTheme === "light" || this.state.terminalTheme === "dark" ? this.state.terminalTheme : "auto";
        if (preference === "auto") {
            const resolved = this.resolveTheme(preference);
            this.state.terminalResolvedTheme = resolved;
            return resolved;
        }
        return preference;
    }

    refreshTerminalTheme(now = Date.now()) {
        if (this.state.terminalTheme !== "auto") {
            return false;
        }
        if (now < this.nextThemeCheckAt) {
            return false;
        }
        this.nextThemeCheckAt = now + 1_000;
        const resolved = this.resolveTheme("auto");
        if (resolved === this.state.terminalResolvedTheme) {
            return false;
        }
        this.state.terminalResolvedTheme = resolved;
        this.fullRedraw = true;
        return true;
    }

    startInput() {
        if (stdin.setRawMode) {
            stdin.setRawMode(true);
        }
        stdin.resume();
        this.inputHandler = (data) => {
            this.handleInput(String(data)).catch((error) => {
                this.reportError(error);
            });
        };
        stdin.on("data", this.inputHandler);
    }

    stopInput() {
        if (this.inputHandler) {
            stdin.off("data", this.inputHandler);
            this.inputHandler = undefined;
        }
        if (stdin.setRawMode) {
            stdin.setRawMode(false);
        }
        stdin.pause();
    }

    startResizeWatcher() {
        if (this.resizeHandler || typeof stdout.on !== "function") {
            return;
        }
        this.resizeHandler = () => this.scheduleResizeRender();
        stdout.on("resize", this.resizeHandler);
    }

    stopResizeWatcher() {
        if (this.resizeTimer) {
            clearTimeout(this.resizeTimer);
            this.resizeTimer = undefined;
        }
        if (this.resizeHandler && typeof stdout.off === "function") {
            stdout.off("resize", this.resizeHandler);
        }
        this.resizeHandler = undefined;
    }

    scheduleResizeRender(delay = 80) {
        if (!this.running) {
            return;
        }
        if (this.resizeTimer) {
            clearTimeout(this.resizeTimer);
        }
        this.resizeTimer = setTimeout(() => {
            this.resizeTimer = undefined;
            if (!this.running) {
                return;
            }
            this.fullRedraw = true;
            this.lastFrameLines = [];
            this.render();
        }, delay);
    }

    handleInput(data: string) {
        return handleInput(this, data);
    }

    moveSelection(delta: number) {
        return moveSelection(this, delta);
    }

    toggleFocusPane() {
        return toggleFocusPane(this);
    }

    focusPane() {
        return focusPane(this);
    }

    scrollTerminal(delta: number) {
        return scrollTerminal(this, delta);
    }

    resizeTerminal(delta: number) {
        return resizeTerminal(this, delta);
    }

    movePage(delta: number) {
        return movePage(this, delta);
    }

    activateSelected() {
        return activateSelected(this);
    }

    editControl(control: TUIControl) {
        return editControl(this, control);
    }

    editConfigSetting(control: TUIControl, setting: TUIConfigSetting) {
        return editConfigSetting(this, control, setting);
    }

    runBundleAction(action: TUIAction, context: TUICommandContext) {
        return runBundleAction(this, action, context);
    }

    runSetupSteps() {
        return runSetupSteps(this);
    }

    refreshDataSources() {
        return refreshDataSources(this);
    }

    updateField(control: TUIControl, value: string) {
        return updateField(this, control, value);
    }

    updateCheckedOptions(control: TUIControl, ids: string[]) {
        return updateCheckedOptions(this, control, ids);
    }

    updateConfigSetting(control: TUIControl, setting: TUIConfigSetting, value: string) {
        return updateConfigSetting(this, control, setting, value);
    }

    persistConfig(control: TUIControl) {
        return persistConfig(this, control);
    }

    persistBundleState(partial: Partial<NonNullable<TUIState["bundleState"]>> = {}) {
        return persistBundleState(this, partial);
    }

    appendOutput(title: string, body: string, command = "", kind = "info", abortController?: AbortController) {
        const entry: TUITerminalEntry = { id: `${Date.now()}-${this.state.terminalEntries.length}`, kind, title, body, command };
        if (abortController) {
            entry.abortController = abortController;
        }
        this.state.terminalEntries.push(entry);
        this.state.selectedTerminalEntryIndex = this.state.terminalEntries.length - 1;
        this.state.terminalScrollOffset = 0;
        return entry;
    }

    reportError(error: unknown) {
        this.appendOutput("Error", error instanceof Error ? error.message : String(error), "", "error");
        if (this.running) {
            this.render();
        }
    }

    cancelActiveTerminalEntry() {
        const entries = this.state.terminalEntries ?? [];
        const index = selectedTerminalEntryIndex(entries, this.state.selectedTerminalEntryIndex);
        const entry = entries[index];
        if (!entry?.abortController || entry.abortController.signal.aborted) {
            return false;
        }
        entry.body = `${entry.body ?? ""}\nCancelling...`.trim();
        entry.kind = "cancelling";
        entry.abortController.abort();
        this.fullRedraw = true;
        return true;
    }

    prompt(label: string, current: string, completer?: (line: string) => [string[], string]) {
        return prompt(this, label, current, completer);
    }

    promptPath(label: string, current: string) {
        return promptPath(this, label, current);
    }

    promptOption(label: string, options: TUIOption[], current: string) {
        return promptOption(this, label, options, current);
    }

    promptCheckboxes(control: TUIControl) {
        return promptCheckboxes(this, control);
    }
}

function selectedTerminalEntryIndex(entries: TUITerminalEntry[], rawIndex: unknown) {
    if (!entries.length) {
        return -1;
    }
    const index = Number(rawIndex);
    return Number.isFinite(index) ? Math.min(Math.max(index, 0), entries.length - 1) : entries.length - 1;
}
