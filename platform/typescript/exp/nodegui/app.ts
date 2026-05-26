import { performance } from "node:perf_hooks";
import { saveBundleState, configSettingBindings, saveConfig } from "../../web/src/server/config-store.js";
import { runAction, runDataSource } from "../../web/src/server/action-runner.js";
import {
    commandContextFromState,
    configValueKey,
    disabledReason,
    displayCommand,
    hydrateRows,
    isActionVisible,
    missingPlaceholders,
    normalizeSelectedIDs,
    rowContext,
} from "../../shared/rendering.js";
import {
    activePage,
    controlWithDataSource,
    optionTitle,
} from "../../tui/rendering-model.js";
import type { BundleStateSnapshot, LooseRecord } from "../../shared/types.js";
import type { TUIAction, TUICommandContext, TUIConfigSetting, TUIControl, TUIRenderState, TUIRunProcess, TUISection } from "../../tui/types.js";

type NodeGui = typeof import("@nodegui/nodegui");
type NodeGuiBoxLayout = InstanceType<NodeGui["QBoxLayout"]>;
type NodeGuiComboBox = InstanceType<NodeGui["QComboBox"]>;
type NodeGuiMainWindow = InstanceType<NodeGui["QMainWindow"]>;
type NodeGuiPlainTextEdit = InstanceType<NodeGui["QPlainTextEdit"]>;
type NodeGuiScrollArea = InstanceType<NodeGui["QScrollArea"]>;

export type NodeGuiAppOptions = {
    runProcess: TUIRunProcess;
    terminateAllProcesses: () => void;
    benchmark: boolean;
    bootStartedAt: number;
};

export async function refreshDataSources(state: TUIRenderState, runProcess: TUIRunProcess) {
    const page = activePage(state);
    if (!page) {
        return;
    }
    for (const section of page.sections ?? []) {
        const sectionKey = `section:${section.id}`;
        if (section.dataSource) {
            await loadDataSource(state, runProcess, sectionKey, section.dataSource, commandContextFromState(state));
        }
        const sectionValues = state.dataSourcePayloads.get(sectionKey)?.values ?? {};
        const sectionContext = commandContextFromState(state, {}, sectionValues);
        for (const rawControl of section.controls ?? []) {
            const control = controlWithDataSource(state, rawControl);
            if (control.dataSource) {
                await loadDataSource(state, runProcess, `control:${control.id}`, control.dataSource, sectionContext);
            }
        }
    }
}

async function loadDataSource(state: TUIRenderState, runProcess: TUIRunProcess, key: string, dataSource: LooseRecord, context: TUICommandContext) {
    try {
        state.dataSourcePayloads.set(key, await runDataSource(dataSource, context, state.bundleRootPath, runProcess));
        state.dataSourceErrors.delete(key);
    } catch (error) {
        state.dataSourcePayloads.delete(key);
        state.dataSourceErrors.set(key, errorMessage(error));
    }
}

export class NodeGuiApp {
    nodegui: NodeGui;
    state: TUIRenderState;
    window!: NodeGuiMainWindow;
    pageSelector!: NodeGuiComboBox;
    scrollArea!: NodeGuiScrollArea;
    terminal!: NodeGuiPlainTextEdit;
    runProcess: TUIRunProcess;
    terminateAllProcesses: () => void;
    benchmark: boolean;
    bootStartedAt: number;
    actionInFlight: boolean;

    constructor(nodegui: NodeGui, state: TUIRenderState, options: NodeGuiAppOptions) {
        this.nodegui = nodegui;
        this.state = state;
        this.runProcess = options.runProcess;
        this.terminateAllProcesses = options.terminateAllProcesses;
        this.benchmark = options.benchmark;
        this.bootStartedAt = options.bootStartedAt;
        this.actionInFlight = false;
    }

    async show(timing: Record<string, number>) {
        const uiStartedAt = performance.now();
        const { QMainWindow, QWidget, QBoxLayout, QComboBox, QLabel, QScrollArea, QPlainTextEdit, Direction, QApplication } = this.nodegui;
        const win = new QMainWindow();
        win.setWindowTitle(`GUI for CLI NodeGui - ${this.state.manifest?.displayName ?? "Bundle"}`);
        win.setMinimumSize(960, 700);

        const root = new QWidget();
        const layout = new QBoxLayout(Direction.TopToBottom);
        root.setLayout(layout);
        root.setInlineStyle("padding: 12px;");

        const title = new QLabel();
        title.setText(`${this.state.manifest?.displayName ?? "GUI for CLI"}\n${this.state.manifest?.summary ?? ""}`);
        title.setInlineStyle("font-size: 18px; font-weight: 600; margin-bottom: 8px;");
        layout.addWidget(title);

        this.pageSelector = new QComboBox();
        this.pageSelector.addItems((this.state.manifest?.pages ?? []).map((page) => page.title ?? page.id));
        this.pageSelector.setCurrentIndex(Math.max(0, (this.state.manifest?.pages ?? []).findIndex((page) => page.id === this.state.activePageID)));
        this.pageSelector.addEventListener("currentIndexChanged", (index: number) => {
            void this.runUiTask("Failed to switch pages", async () => {
                const page = this.state.manifest?.pages?.[index];
                if (!page) {
                    return;
                }
                this.state.activePageID = page.id;
                await this.persistBundleState();
                await refreshDataSources(this.state, this.runProcess);
                this.renderPage();
            });
        });
        layout.addWidget(this.pageSelector);

        this.scrollArea = new QScrollArea();
        this.scrollArea.setWidgetResizable(true);
        this.scrollArea.setInlineStyle("flex: 1; margin-top: 8px;");
        layout.addWidget(this.scrollArea, 1);

        this.terminal = new QPlainTextEdit();
        this.terminal.setReadOnly(true);
        this.terminal.setPlainText("Terminal output appears here.");
        this.terminal.setMinimumSize(800, 160);
        layout.addWidget(this.terminal);

        win.setCentralWidget(root);
        this.window = win;
        this.renderPage();
        win.show();
        QApplication.instance().processEvents();
        this.printBenchmark(timing, uiStartedAt);
        if (this.benchmark) {
            setTimeout(() => {
                this.terminateAllProcesses();
                QApplication.instance().quit();
                process.exit(0);
            }, 250);
        }
        (globalThis as typeof globalThis & { nodeGuiWindow?: NodeGuiMainWindow }).nodeGuiWindow = win;
    }

    renderPage() {
        const { QWidget, QBoxLayout, QLabel, Direction } = this.nodegui;
        const page = activePage(this.state);
        const container = new QWidget();
        const layout = new QBoxLayout(Direction.TopToBottom);
        container.setLayout(layout);
        container.setInlineStyle("padding: 8px;");
        if (!page) {
            const empty = new QLabel();
            empty.setText("No pages are available.");
            layout.addWidget(empty);
            this.scrollArea.setWidget(container);
            return;
        }

        for (const section of page.sections ?? []) {
            this.addSection(layout, section);
        }
        layout.addStretch(1);
        this.scrollArea.setWidget(container);
    }

    addSection(layout: NodeGuiBoxLayout, section: TUISection) {
        const { QLabel } = this.nodegui;
        const title = new QLabel();
        title.setText(section.title ?? section.id ?? "Section");
        title.setInlineStyle("font-size: 15px; font-weight: 600; margin-top: 10px;");
        layout.addWidget(title);
        if (section.summary) {
            const summary = new QLabel();
            summary.setText(section.summary);
            layout.addWidget(summary);
        }

        const sectionValues = this.state.dataSourcePayloads.get(`section:${section.id}`)?.values ?? {};
        const sectionContext = commandContextFromState(this.state, {}, sectionValues);
        for (const rawControl of section.controls ?? []) {
            this.addControl(layout, controlWithDataSource(this.state, rawControl), sectionContext);
        }
        for (const action of section.actions ?? []) {
            if (isActionVisible(action, sectionContext)) {
                this.addAction(layout, action, sectionContext);
            }
        }
    }

    addControl(layout: NodeGuiBoxLayout, control: TUIControl, context: TUICommandContext) {
        switch (control.kind) {
            case "text":
            case "path":
                this.addTextField(layout, control);
                break;
            case "dropdown":
                this.addDropdown(layout, control);
                break;
            case "toggle":
                this.addToggle(layout, control);
                break;
            case "checkboxGroup":
                this.addCheckboxGroup(layout, control);
                break;
            case "configEditor":
                this.addConfigEditor(layout, control);
                break;
            case "libraryList":
                this.addLibraryList(layout, control, context);
                break;
            default:
                this.addReadOnly(layout, control.label ?? control.title ?? control.id, stateText(control.value ?? control.text));
        }
    }

    addTextField(layout: NodeGuiBoxLayout, control: TUIControl) {
        const { QLabel, QLineEdit } = this.nodegui;
        const label = new QLabel();
        label.setText(control.label ?? control.id);
        layout.addWidget(label);
        const input = new QLineEdit();
        input.setText(String(this.state.fieldValues?.[control.id] ?? control.value ?? ""));
        input.setPlaceholderText(control.placeholder ?? "");
        input.addEventListener("editingFinished", () => {
            void this.runUiTask(`Failed to update ${control.id}`, async () => {
                await this.updateField(control, input.text());
            });
        });
        layout.addWidget(input);
    }

    addDropdown(layout: NodeGuiBoxLayout, control: TUIControl) {
        const { QLabel, QComboBox } = this.nodegui;
        const options = control.options ?? [];
        const label = new QLabel();
        label.setText(control.label ?? control.id);
        layout.addWidget(label);
        const combo = new QComboBox();
        combo.addItems(options.map((item) => optionTitle(item, this.state.labels)));
        const selected = String(this.state.fieldValues?.[control.id] ?? control.value ?? options.find((item) => item.selected)?.id ?? "");
        combo.setCurrentIndex(Math.max(0, options.findIndex((item) => item.id === selected)));
        combo.addEventListener("currentIndexChanged", (index: number) => {
            void this.runUiTask(`Failed to update ${control.id}`, async () => {
                if (options[index]) {
                    await this.updateField(control, options[index].id);
                }
            });
        });
        layout.addWidget(combo);
    }

    addToggle(layout: NodeGuiBoxLayout, control: TUIControl) {
        const { QCheckBox } = this.nodegui;
        const checkbox = new QCheckBox();
        checkbox.setText(control.label ?? control.id);
        checkbox.setChecked(String(this.state.fieldValues?.[control.id] ?? control.value ?? "false") === "true");
        checkbox.addEventListener("toggled", (checked: boolean) => {
            void this.runUiTask(`Failed to update ${control.id}`, async () => {
                await this.updateField(control, checked ? "true" : "false");
            });
        });
        layout.addWidget(checkbox);
    }

    addCheckboxGroup(layout: NodeGuiBoxLayout, control: TUIControl) {
        const { QLabel, QCheckBox } = this.nodegui;
        const label = new QLabel();
        label.setText(control.label ?? control.id);
        layout.addWidget(label);
        const selected = new Set(normalizeSelectedIDs(this.state.checkedOptions?.[control.id] ?? []));
        for (const option of control.options ?? []) {
            const checkbox = new QCheckBox();
            checkbox.setText(optionTitle(option, this.state.labels));
            checkbox.setChecked(selected.has(option.id));
            checkbox.addEventListener("toggled", (checked: boolean) => {
                void this.runUiTask(`Failed to update ${control.id}`, async () => {
                    if (checked) selected.add(option.id);
                    else selected.delete(option.id);
                    this.state.checkedOptions[control.id] = [...selected];
                    await this.persistBundleState();
                    await refreshDataSources(this.state, this.runProcess);
                    this.renderPage();
                });
            });
            layout.addWidget(checkbox);
        }
    }

    addConfigEditor(layout: NodeGuiBoxLayout, control: TUIControl) {
        for (const setting of control.settings ?? []) {
            if (setting.kind === "dropdown") {
                this.addConfigDropdown(layout, control, setting);
            } else {
                this.addConfigTextField(layout, control, setting);
            }
        }
    }

    addConfigTextField(layout: NodeGuiBoxLayout, control: TUIControl, setting: TUIConfigSetting) {
        const { QLabel, QLineEdit } = this.nodegui;
        const key = configValueKey(control, setting);
        const label = new QLabel();
        label.setText(setting.label ?? setting.id);
        layout.addWidget(label);
        const input = new QLineEdit();
        input.setText(String(this.state.configValues?.[key] ?? setting.value ?? ""));
        input.addEventListener("editingFinished", () => {
            void this.runUiTask(`Failed to update ${setting.id}`, async () => {
                await this.updateConfigSetting(control, setting, input.text());
            });
        });
        layout.addWidget(input);
    }

    addConfigDropdown(layout: NodeGuiBoxLayout, control: TUIControl, setting: TUIConfigSetting) {
        const { QLabel, QComboBox } = this.nodegui;
        const key = configValueKey(control, setting);
        const options = setting.options ?? [];
        const label = new QLabel();
        label.setText(setting.label ?? setting.id);
        layout.addWidget(label);
        const combo = new QComboBox();
        combo.addItems(options.map((item) => optionTitle(item, this.state.labels)));
        const selected = String(this.state.configValues?.[key] ?? setting.value ?? options.find((item) => item.selected)?.id ?? "");
        combo.setCurrentIndex(Math.max(0, options.findIndex((item) => item.id === selected)));
        combo.addEventListener("currentIndexChanged", (index: number) => {
            void this.runUiTask(`Failed to update ${setting.id}`, async () => {
                if (options[index]) {
                    await this.updateConfigSetting(control, setting, options[index].id);
                }
            });
        });
        layout.addWidget(combo);
    }

    addLibraryList(layout: NodeGuiBoxLayout, control: TUIControl, context: TUICommandContext) {
        const { QLabel } = this.nodegui;
        const title = new QLabel();
        title.setText(control.label ?? control.id);
        layout.addWidget(title);
        for (const row of hydrateRows(control)) {
            const rowLabel = new QLabel();
            rowLabel.setText(`${row.title ?? row.id}${row.status ? ` — ${row.status}` : ""}`);
            layout.addWidget(rowLabel);
            const actionContext = rowContext(context, row);
            for (const action of control.rowActions ?? []) {
                if (isActionVisible(action, actionContext)) {
                    this.addAction(layout, action, actionContext, row.title ?? row.id);
                }
            }
        }
    }

    addAction(layout: NodeGuiBoxLayout, action: TUIAction, context: TUICommandContext, prefix = "") {
        const { QPushButton } = this.nodegui;
        const button = new QPushButton();
        const title = [prefix, action.title ?? action.id].filter(Boolean).join(": ");
        button.setText(title);
        const missing = action.command ? missingPlaceholders(action.command, context) : [];
        const disabled = disabledReason(action, context) ?? (missing.length ? `Missing: ${missing.join(", ")}` : undefined);
        button.setEnabled(!disabled && !this.actionInFlight);
        button.addEventListener("clicked", () => {
            void this.runUiTask(`Failed to run ${action.id}`, async () => {
                await this.runBundleAction(action, context);
            });
        });
        layout.addWidget(button);
        if (disabled) {
            this.addReadOnly(layout, "", disabled);
        }
    }

    addReadOnly(layout: NodeGuiBoxLayout, title: string, value: string) {
        const { QLabel } = this.nodegui;
        const label = new QLabel();
        label.setText([title, value].filter(Boolean).join(": ") || "(empty)");
        layout.addWidget(label);
    }

    async updateField(control: TUIControl, value: string) {
        this.state.fieldValues[control.id] = value;
        for (const binding of configSettingBindings(this.state.manifest, control.id)) {
            this.state.configValues[configValueKey(binding.control, binding.setting)] = value;
            await this.persistConfig(binding.control);
        }
        await this.persistBundleState();
        await refreshDataSources(this.state, this.runProcess);
        this.renderPage();
    }

    async updateConfigSetting(control: TUIControl, setting: TUIConfigSetting, value: string) {
        this.state.configValues[configValueKey(control, setting)] = value;
        if (setting.key && Object.hasOwn(this.state.fieldValues, setting.key)) this.state.fieldValues[setting.key] = value;
        if (Object.hasOwn(this.state.fieldValues, setting.id)) this.state.fieldValues[setting.id] = value;
        await this.persistConfig(control);
        await this.persistBundleState();
        await refreshDataSources(this.state, this.runProcess);
        this.renderPage();
    }

    async persistConfig(control: TUIControl) {
        const values = Object.fromEntries((control.settings ?? []).map((setting) => [
            setting.key,
            this.state.configValues[configValueKey(control, setting)] ?? setting.value ?? "",
        ]));
        const result = await saveConfig(control, this.state.configFilePaths?.[control.id], values, this.state.bundleRootPath);
        this.state.configFilePaths[control.id] = result.path;
    }

    async persistBundleState(partial: Partial<BundleStateSnapshot> = {}) {
        this.state.bundleState = await saveBundleState({
            fieldValues: this.state.fieldValues,
            checkedOptions: Object.fromEntries(Object.entries(this.state.checkedOptions ?? {}).map(([key, value]) => [key, normalizeSelectedIDs(value)])),
            configFilePaths: this.state.configFilePaths,
            selectedPageID: this.state.activePageID,
            setupRun: this.state.setupRun,
            ...partial,
        }, this.state.bundleRootPath);
    }

    async runBundleAction(action: TUIAction, context: TUICommandContext) {
        if (this.actionInFlight) {
            return;
        }
        if (!action.command) {
            this.appendOutput(`${action.title ?? action.id}\nNo command configured.`);
            return;
        }
        this.actionInFlight = true;
        this.renderPage();
        const command = displayCommand(action.command, context);
        this.appendOutput(`${action.title ?? action.id}\n$ ${command}\nRunning...`);
        try {
            const result = await runAction(action, context, new AbortController().signal, this.state.bundleRootPath, this.runProcess);
            this.appendOutput(`${result.command ?? command}\n${result.stdout ?? ""}${result.stderr ?? ""}\nexit ${result.exitCode}`);
            this.state.dataSourcePayloads.clear();
            await refreshDataSources(this.state, this.runProcess);
        } catch (error) {
            this.appendOutput(errorMessage(error));
            console.error(`NodeGui action failed: ${action.title ?? action.id}`, error);
        } finally {
            this.actionInFlight = false;
            this.renderPage();
        }
    }

    appendOutput(text: string) {
        const existing = this.terminal.toPlainText();
        this.terminal.setPlainText(existing === "Terminal output appears here." ? text : `${existing}\n\n${text}`);
    }

    async runUiTask(label: string, task: () => Promise<void>) {
        try {
            await task();
        } catch (error) {
            console.error(label, error);
            this.appendOutput(`${label}\n${errorMessage(error)}`);
        }
    }

    printBenchmark(timing: Record<string, number>, uiStartedAt: number) {
        if (!this.benchmark) {
            return;
        }
        const bootToBundleLoadedMs = Math.round((uiStartedAt - this.bootStartedAt) * 10) / 10;
        const importedAtMs = timing.importedAtMs ?? uiStartedAt;
        const nodeguiImportMs = Math.round(importedAtMs * 10) / 10;
        const bootToWindowShownMs = Math.round((performance.now() - this.bootStartedAt) * 10) / 10;
        console.log(`metric bundleLoaded_ms=${bootToBundleLoadedMs}`);
        console.log(`metric nodeguiImport_ms=${nodeguiImportMs}`);
        console.log(`metric windowShown_ms=${bootToWindowShownMs}`);
        console.log(JSON.stringify({
            surface: "nodegui",
            bootToBundleLoadedMs,
            nodeguiImportMs,
            bootToWindowShownMs,
            pageCount: this.state.manifest?.pages?.length ?? 0,
            bundleRoot: this.state.bundleRootPath,
        }));
    }
}


export function errorMessage(error: unknown) {
    return error instanceof Error ? error.message : String(error);
}

function stateText(value: unknown) {
    return value == null ? "" : String(value);
}
