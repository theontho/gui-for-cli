#!/usr/bin/env node
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { performance } from "node:perf_hooks";
import {
    createOneShotBundlePreload,
    loadLocalizedBundle,
    loadManifestFromRoot,
} from "../server/bundle-loader.js";
import { saveBundleState } from "../server/config-store.js";
import { parseArgs } from "../server/paths.js";
import { createProcessManager } from "../server/process-runner.js";
import { runInitialSetupIfNeeded } from "../server/setup-runner.js";
import { prepareBundleWorkspace } from "../server/workspace.js";
import { runAction } from "../server/action-runner.js";
import { configSettingBindings, saveConfig } from "../server/config-store.js";
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
} from "../shared/rendering.js";
import { runDataSource } from "../server/action-runner.js";
import {
    activePage,
    controlWithDataSource,
    optionTitle,
} from "../tui/rendering-model.js";

type NodeGui = typeof import("@nodegui/nodegui");

const bootStartedAt = performance.now();
const nodeguiDir = path.dirname(fileURLToPath(import.meta.url));
const distRoot = path.resolve(nodeguiDir, "..");
const webuiRoot = path.resolve(distRoot, "..");
const repoRoot = path.resolve(webuiRoot, "..");
const args = parseArgs(process.argv.slice(2));

let sourceBundleRoot = "";
let bundleRoot = "";
let runProcess: any;
let terminateAllProcesses = () => {};
let shouldRunInitialSetup = false;

async function main() {
    if (args.help) {
        printHelp();
        return;
    }

    sourceBundleRoot = resolveBundleRoot(args.bundle);
    const sourceManifest = await loadManifestFromRoot(sourceBundleRoot);
    bundleRoot = await prepareBundleWorkspace(sourceManifest, sourceBundleRoot);
    const processManager = createProcessManager({ maxOutputBytes: 1_048_576, maxErrorBytes: 65_536 });
    runProcess = processManager.runProcess;
    terminateAllProcesses = processManager.terminateAllProcesses;
    shouldRunInitialSetup = Boolean(args.bundle) && args.setup !== "false";

    const localizedBundleLoader = createOneShotBundlePreload(loadBundleForNodeGui, args.locale, Boolean(args.bundle));
    if (localizedBundleLoader.preloaded) {
        await localizedBundleLoader.preloaded;
    }
    const bundle = await localizedBundleLoader.load(args.locale);
    const state = createState(bundle);
    await refreshDataSources(state);

    if (args.once === "true") {
        printSnapshot(state);
        terminateAllProcesses();
        return;
    }

    const loadStartedAt = performance.now();
    const nodegui = await import("@nodegui/nodegui");
    const app = new NodeGuiApp(nodegui, state);
    await app.show({ importedAtMs: loadStartedAt - bootStartedAt });
}

async function loadBundleForNodeGui(locale?: string) {
    const bundle = await loadLocalizedBundle(locale, repoRoot, bundleRoot, sourceBundleRoot);
    const setupRun = await runInitialSetupIfNeeded(
        bundle,
        bundleRoot,
        runProcess,
        (state) => saveBundleState(state, bundleRoot),
        () => {},
        shouldRunInitialSetup,
    );
    return setupRun ? loadLocalizedBundle(locale, repoRoot, bundleRoot, sourceBundleRoot) : bundle;
}

function createState(bundle: Record<string, any>) {
    const selectedPageID = bundle.bundleState?.selectedPageID;
    const pages = bundle.manifest?.pages ?? [];
    const activePageID = pages.some((page) => page.id === selectedPageID) ? selectedPageID : pages[0]?.id ?? "";
    return {
        ...bundle,
        activePageID,
        dataSourcePayloads: new Map(),
        dataSourceErrors: new Map(),
        terminalEntries: [],
        homePath: homedir(),
        setupRun: bundle.bundleState?.setupRun ?? null,
    };
}

async function refreshDataSources(state: Record<string, any>) {
    const page = activePage(state);
    if (!page) {
        return;
    }
    for (const section of page.sections ?? []) {
        const sectionKey = `section:${section.id}`;
        if (section.dataSource) {
            await loadDataSource(state, sectionKey, section.dataSource, commandContextFromState(state));
        }
        const sectionValues = state.dataSourcePayloads.get(sectionKey)?.values ?? {};
        const sectionContext = commandContextFromState(state, {}, sectionValues);
        for (const rawControl of section.controls ?? []) {
            const control = controlWithDataSource(state, rawControl);
            if (control.dataSource) {
                await loadDataSource(state, `control:${control.id}`, control.dataSource, sectionContext);
            }
        }
    }
}

async function loadDataSource(state: Record<string, any>, key: string, dataSource: Record<string, any>, context: Record<string, any>) {
    try {
        state.dataSourcePayloads.set(key, await runDataSource(dataSource, context, state.bundleRootPath, runProcess));
        state.dataSourceErrors.delete(key);
    } catch (error) {
        state.dataSourcePayloads.delete(key);
        state.dataSourceErrors.set(key, errorMessage(error));
    }
}

class NodeGuiApp {
    nodegui: NodeGui;
    state: Record<string, any>;
    window: any;
    pageSelector: any;
    scrollArea: any;
    terminal: any;

    constructor(nodegui: NodeGui, state: Record<string, any>) {
        this.nodegui = nodegui;
        this.state = state;
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
        this.pageSelector.addEventListener("currentIndexChanged", async (index: number) => {
            const page = this.state.manifest?.pages?.[index];
            if (!page) {
                return;
            }
            this.state.activePageID = page.id;
            await this.persistBundleState();
            await refreshDataSources(this.state);
            this.renderPage();
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
        if (args.benchmark === "true") {
            setTimeout(() => {
                terminateAllProcesses();
                QApplication.instance().quit();
                process.exit(0);
            }, 250);
        }
        (globalThis as any).nodeGuiWindow = win;
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

    addSection(layout: any, section: Record<string, any>) {
        const { QLabel } = this.nodegui;
        const title = new QLabel();
        title.setText(section.title ?? section.id);
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

    addControl(layout: any, control: Record<string, any>, context: Record<string, any>) {
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
                this.addReadOnly(layout, control.label ?? control.title ?? control.id, control.value ?? control.text ?? "");
        }
    }

    addTextField(layout: any, control: Record<string, any>) {
        const { QLabel, QLineEdit } = this.nodegui;
        const label = new QLabel();
        label.setText(control.label ?? control.id);
        layout.addWidget(label);
        const input = new QLineEdit();
        input.setText(String(this.state.fieldValues?.[control.id] ?? control.value ?? ""));
        input.setPlaceholderText(control.placeholder ?? "");
        input.addEventListener("editingFinished", async () => {
            await this.updateField(control, input.text());
        });
        layout.addWidget(input);
    }

    addDropdown(layout: any, control: Record<string, any>) {
        const { QLabel, QComboBox } = this.nodegui;
        const options = control.options ?? [];
        const label = new QLabel();
        label.setText(control.label ?? control.id);
        layout.addWidget(label);
        const combo = new QComboBox();
        combo.addItems(options.map((item) => optionTitle(item, this.state.labels)));
        const selected = String(this.state.fieldValues?.[control.id] ?? control.value ?? options.find((item) => item.selected)?.id ?? "");
        combo.setCurrentIndex(Math.max(0, options.findIndex((item) => item.id === selected)));
        combo.addEventListener("currentIndexChanged", async (index: number) => {
            if (options[index]) {
                await this.updateField(control, options[index].id);
            }
        });
        layout.addWidget(combo);
    }

    addToggle(layout: any, control: Record<string, any>) {
        const { QCheckBox } = this.nodegui;
        const checkbox = new QCheckBox();
        checkbox.setText(control.label ?? control.id);
        checkbox.setChecked(String(this.state.fieldValues?.[control.id] ?? control.value ?? "false") === "true");
        checkbox.addEventListener("toggled", async (checked: boolean) => {
            await this.updateField(control, checked ? "true" : "false");
        });
        layout.addWidget(checkbox);
    }

    addCheckboxGroup(layout: any, control: Record<string, any>) {
        const { QLabel, QCheckBox } = this.nodegui;
        const label = new QLabel();
        label.setText(control.label ?? control.id);
        layout.addWidget(label);
        const selected = new Set(normalizeSelectedIDs(this.state.checkedOptions?.[control.id] ?? []));
        for (const option of control.options ?? []) {
            const checkbox = new QCheckBox();
            checkbox.setText(optionTitle(option, this.state.labels));
            checkbox.setChecked(selected.has(option.id));
            checkbox.addEventListener("toggled", async (checked: boolean) => {
                if (checked) selected.add(option.id);
                else selected.delete(option.id);
                this.state.checkedOptions[control.id] = [...selected];
                await this.persistBundleState();
                await refreshDataSources(this.state);
                this.renderPage();
            });
            layout.addWidget(checkbox);
        }
    }

    addConfigEditor(layout: any, control: Record<string, any>) {
        for (const setting of control.settings ?? []) {
            if (setting.kind === "dropdown") {
                this.addConfigDropdown(layout, control, setting);
            } else {
                this.addConfigTextField(layout, control, setting);
            }
        }
    }

    addConfigTextField(layout: any, control: Record<string, any>, setting: Record<string, any>) {
        const { QLabel, QLineEdit } = this.nodegui;
        const key = configValueKey(control, setting);
        const label = new QLabel();
        label.setText(setting.label ?? setting.id);
        layout.addWidget(label);
        const input = new QLineEdit();
        input.setText(String(this.state.configValues?.[key] ?? setting.value ?? ""));
        input.addEventListener("editingFinished", async () => {
            await this.updateConfigSetting(control, setting, input.text());
        });
        layout.addWidget(input);
    }

    addConfigDropdown(layout: any, control: Record<string, any>, setting: Record<string, any>) {
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
        combo.addEventListener("currentIndexChanged", async (index: number) => {
            if (options[index]) {
                await this.updateConfigSetting(control, setting, options[index].id);
            }
        });
        layout.addWidget(combo);
    }

    addLibraryList(layout: any, control: Record<string, any>, context: Record<string, any>) {
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

    addAction(layout: any, action: Record<string, any>, context: Record<string, any>, prefix = "") {
        const { QPushButton } = this.nodegui;
        const button = new QPushButton();
        const title = [prefix, action.title ?? action.id].filter(Boolean).join(": ");
        button.setText(title);
        const missing = missingPlaceholders(action.command ?? {}, context);
        const disabled = disabledReason(action, context) ?? (missing.length ? `Missing: ${missing.join(", ")}` : undefined);
        button.setEnabled(!disabled);
        button.addEventListener("clicked", async () => {
            await this.runBundleAction(action, context);
        });
        layout.addWidget(button);
        if (disabled) {
            this.addReadOnly(layout, "", disabled);
        }
    }

    addReadOnly(layout: any, title: string, value: string) {
        const { QLabel } = this.nodegui;
        const label = new QLabel();
        label.setText([title, value].filter(Boolean).join(": ") || "(empty)");
        layout.addWidget(label);
    }

    async updateField(control: Record<string, any>, value: string) {
        this.state.fieldValues[control.id] = value;
        for (const binding of configSettingBindings(this.state.manifest, control.id)) {
            this.state.configValues[configValueKey(binding.control, binding.setting)] = value;
            await this.persistConfig(binding.control);
        }
        await this.persistBundleState();
        await refreshDataSources(this.state);
        this.renderPage();
    }

    async updateConfigSetting(control: Record<string, any>, setting: Record<string, any>, value: string) {
        this.state.configValues[configValueKey(control, setting)] = value;
        if (Object.hasOwn(this.state.fieldValues, setting.key)) this.state.fieldValues[setting.key] = value;
        if (Object.hasOwn(this.state.fieldValues, setting.id)) this.state.fieldValues[setting.id] = value;
        await this.persistConfig(control);
        await this.persistBundleState();
        await refreshDataSources(this.state);
        this.renderPage();
    }

    async persistConfig(control: Record<string, any>) {
        const values = Object.fromEntries((control.settings ?? []).map((setting) => [
            setting.key,
            this.state.configValues[configValueKey(control, setting)] ?? setting.value ?? "",
        ]));
        const result = await saveConfig(control, this.state.configFilePaths?.[control.id], values, this.state.bundleRootPath);
        this.state.configFilePaths[control.id] = result.path;
    }

    async persistBundleState(partial: Record<string, any> = {}) {
        this.state.bundleState = await saveBundleState({
            fieldValues: this.state.fieldValues,
            checkedOptions: Object.fromEntries(Object.entries(this.state.checkedOptions ?? {}).map(([key, value]) => [key, normalizeSelectedIDs(value)])),
            configFilePaths: this.state.configFilePaths,
            selectedPageID: this.state.activePageID,
            setupRun: this.state.setupRun,
            ...partial,
        }, this.state.bundleRootPath);
    }

    async runBundleAction(action: Record<string, any>, context: Record<string, any>) {
        const command = displayCommand(action.command, context);
        this.appendOutput(`${action.title ?? action.id}\n$ ${command}\nRunning...`);
        try {
            const result = await runAction(action, context, new AbortController().signal, this.state.bundleRootPath, runProcess);
            this.appendOutput(`${result.command ?? command}\n${result.stdout ?? ""}${result.stderr ?? ""}\nexit ${result.exitCode}`);
        } catch (error) {
            this.appendOutput(errorMessage(error));
        }
        this.state.dataSourcePayloads.clear();
        await refreshDataSources(this.state);
        this.renderPage();
    }

    appendOutput(text: string) {
        const existing = this.terminal.toPlainText();
        this.terminal.setPlainText(existing === "Terminal output appears here." ? text : `${existing}\n\n${text}`);
    }

    printBenchmark(timing: Record<string, number>, uiStartedAt: number) {
        if (args.benchmark !== "true") {
            return;
        }
        console.log(JSON.stringify({
            surface: "nodegui",
            bootToBundleLoadedMs: Math.round((uiStartedAt - bootStartedAt) * 10) / 10,
            nodeguiImportMs: Math.round(timing.importedAtMs * 10) / 10,
            bootToWindowShownMs: Math.round((performance.now() - bootStartedAt) * 10) / 10,
            pageCount: this.state.manifest?.pages?.length ?? 0,
            bundleRoot: this.state.bundleRootPath,
        }));
    }
}

function printSnapshot(state: Record<string, any>) {
    const pages = state.manifest?.pages ?? [];
    const controls = pages.flatMap((page) => (page.sections ?? []).flatMap((section) => section.controls ?? []));
    const actions = pages.flatMap((page) => (page.sections ?? []).flatMap((section) => section.actions ?? []));
    console.log(JSON.stringify({
        surface: "nodegui",
        bundle: state.manifest?.displayName ?? "GUI for CLI",
        pages: pages.length,
        controls: controls.length,
        actions: actions.length,
        activePageID: state.activePageID,
    }, null, 2));
}

function resolveBundleRoot(value?: string) {
    if (!value) {
        return path.join(repoRoot, "Examples", "WGSExtract");
    }
    if (path.isAbsolute(value)) {
        return value;
    }
    const cwdCandidate = path.resolve(value);
    if (existsSync(path.join(cwdCandidate, "manifest.json"))) {
        return cwdCandidate;
    }
    return path.resolve(repoRoot, value);
}

function printHelp() {
    console.log(`GUI for CLI NodeGui

Usage:
  npm --prefix WebUI run nodegui -- [--bundle PATH] [--locale CODE] [--benchmark] [--once] [--no-setup]

Options:
  --bundle PATH   Bundle source root. Defaults to Examples/WGSExtract.
  --locale CODE   Localization code to load.
  --benchmark     Print startup timing JSON after showing the native Qt window.
  --once          Load the shared model and print a non-GUI snapshot.
  --no-setup      Do not run initial setup automatically for explicit bundles.
`);
}

function errorMessage(error: unknown) {
    return error instanceof Error ? error.message : String(error);
}

process.once("SIGINT", () => terminateAllProcesses());
process.once("SIGTERM", () => terminateAllProcesses());
process.once("beforeExit", () => terminateAllProcesses());

await main();
