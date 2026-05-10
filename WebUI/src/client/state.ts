export type WebUIState = Record<string, any>;

export function createInitialState(): WebUIState {
    return {
        manifest: null,
        labels: {},
        localizationCode: "",
        localizationOptions: [],
        iconSet: "platform",
        colorTheme: "system",
        bundleRootPath: "",
        activePageID: "",
        fieldValues: {},
        checkedOptions: {},
        configValues: {},
        configFilePaths: {},
        dataSourcePayloads: new Map(),
        dataSourceErrors: new Map(),
        loadingDataSources: new Set(),
        fileStateValues: new Map(),
        loadingFileStates: new Set(),
        actionPrechecks: new Map(),
        actionPrecheckErrors: new Map(),
        loadingActionPrechecks: new Set(),
        exitCodeReference: new Map(),
        setupRun: null,
        setupAutorunStarted: false,
        terminalCopyFeedback: false,
        terminalEntries: [],
        activeTerminalIndex: 0,
        isTerminalVisible: true,
        pendingConfirmation: null,
        sidebarWidth: Number(localStorage.getItem("guiForCLI.sidebarWidth")) || 220,
        terminalHeight: Number(localStorage.getItem("guiForCLI.terminalHeight")) ||
            Math.round(window.innerHeight * 0.2),
    };
}
export const state: WebUIState = createInitialState();
