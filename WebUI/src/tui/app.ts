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
import type { TUIThemePreference } from "./theme.js";

export type TUIAppOptions = {
    runProcess: any;
    terminateAllProcesses: () => void;
    theme?: TUIThemePreference;
};

export class TUIApp {
    state: Record<string, any>;
    running = false;
    inputHandler?: (data: Buffer | string) => void;
    lastFrameLines: string[] = [];
    fullRedraw = true;
    runProcess: any;
    terminateAllProcesses: () => void;

    constructor(bundle: Record<string, any>, options: TUIAppOptions) {
        this.runProcess = options.runProcess;
        this.terminateAllProcesses = options.terminateAllProcesses;
        const selectedPageID = bundle.bundleState?.selectedPageID;
        const pages = bundle.manifest?.pages ?? [];
        const activePageID = pages.some((page) => page.id === selectedPageID) ? selectedPageID : pages[0]?.id ?? "";
        this.state = {
            ...bundle,
            activePageID,
            selectedItemIndex: 0,
            dataSourcePayloads: new Map(),
            dataSourceErrors: new Map(),
            terminalEntries: [],
            focusPane: "main",
            terminalTheme: options.theme ?? "auto",
            terminalHeightRows: 0,
            terminalScrollOffset: 0,
            homePath: homedir(),
            setupRun: bundle.bundleState?.setupRun ?? null,
        };
    }

    async run(once: boolean) {
        let interactive = false;
        try {
            await this.refreshDataSources();
            if (once) {
                stdout.write(`${renderTUIScreen(this.state, { columns: stdout.columns || 100, rows: stdout.rows || 32, color: stdout.isTTY, theme: this.state.terminalTheme })}\n`);
                return;
            }
            interactive = true;
            this.running = true;
            stdout.write("\x1b[?1049h\x1b[?25l");
            this.startInput();
            this.render();
            while (this.running) {
                await new Promise((resolve) => setTimeout(resolve, 50));
            }
        } finally {
            if (interactive) {
                this.running = false;
                this.stopInput();
                stdout.write("\x1b[?25h\x1b[?1049l");
            }
            this.terminateAllProcesses();
        }
    }

    close(exitCode = 0) {
        this.running = false;
        process.exitCode = exitCode;
    }

    render() {
        clampSelectedItem(this.state);
        const frame = renderTUIScreen(this.state, { columns: stdout.columns || 100, rows: stdout.rows || 32, color: true, theme: this.state.terminalTheme });
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

    startInput() {
        if (stdin.setRawMode) {
            stdin.setRawMode(true);
        }
        stdin.resume();
        this.inputHandler = (data) => {
            this.handleInput(String(data)).catch((error) => {
                this.appendOutput("Error", error instanceof Error ? error.message : String(error), "", "error");
                if (this.running) {
                    this.render();
                }
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

    editControl(control: Record<string, any>) {
        return editControl(this, control);
    }

    editConfigSetting(control: Record<string, any>, setting: Record<string, any>) {
        return editConfigSetting(this, control, setting);
    }

    runBundleAction(action: Record<string, any>, context: Record<string, any>) {
        return runBundleAction(this, action, context);
    }

    runSetupSteps() {
        return runSetupSteps(this);
    }

    refreshDataSources() {
        return refreshDataSources(this);
    }

    updateField(control: Record<string, any>, value: string) {
        return updateField(this, control, value);
    }

    updateCheckedOptions(control: Record<string, any>, ids: string[]) {
        return updateCheckedOptions(this, control, ids);
    }

    updateConfigSetting(control: Record<string, any>, setting: Record<string, any>, value: string) {
        return updateConfigSetting(this, control, setting, value);
    }

    persistConfig(control: Record<string, any>) {
        return persistConfig(this, control);
    }

    persistBundleState(partial: Record<string, any> = {}) {
        return persistBundleState(this, partial);
    }

    appendOutput(title: string, body: string, command = "", kind = "info") {
        const entry = { id: `${Date.now()}-${this.state.terminalEntries.length}`, kind, title, body, command };
        this.state.terminalEntries.push(entry);
        this.state.terminalScrollOffset = 0;
        return entry;
    }

    prompt(label: string, current: string, completer?: (line: string) => [string[], string]) {
        return prompt(this, label, current, completer);
    }

    promptPath(label: string, current: string) {
        return promptPath(this, label, current);
    }

    promptOption(label: string, options: Record<string, any>[], current: string) {
        return promptOption(this, label, options, current);
    }

    promptCheckboxes(control: Record<string, any>) {
        return promptCheckboxes(this, control);
    }
}
