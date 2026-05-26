import type {
    ActionSpec,
    BundleStateSnapshot,
    CommandContext,
    ConfigSetting,
    ConfigFileSpec,
    ControlOption,
    DataSourcePayload,
    Labels,
    LooseRecord,
    ManifestResponse,
    RunProcess,
    RowColumnSpec,
    RowSpec,
    RowTemplateSpec,
    SetupSpec,
    SetupRun,
    StateValue,
    StringMap,
    TerminalEntry,
    ValueMap,
} from "../shared/types.js";
import type { TUIColorTheme } from "./rendering-format.js";
import type { TUIThemePreference } from "./theme.js";

export type TUIOption = ControlOption & {
    group?: string;
    status?: string;
};

export type TUIConfigSetting = ConfigSetting & {
    kind?: string;
    options?: TUIOption[];
    pathKind?: string;
    defaultDirectory?: string;
};

export type TUIAction = ActionSpec & {
    id?: string;
    estimatedDurationMinutes?: number;
};

export interface TUIControl {
    id: string;
    kind: string;
    label?: string;
    title?: string;
    value?: StateValue;
    placeholder?: string;
    configFile?: ConfigFileSpec;
    items?: LooseRecord[];
    rows?: RowSpec[];
    rowTemplate?: RowTemplateSpec;
    columns?: RowColumnSpec[];
    settings?: TUIConfigSetting[];
    options?: TUIOption[];
    rowActions?: TUIAction[];
    actions?: TUIAction[];
    dataSource?: LooseRecord;
    text?: string;
    [key: string]: unknown;
}

export interface TUISection {
    id?: string;
    title?: string;
    subtitle?: string;
    summary?: string;
    controls?: TUIControl[];
    actions?: TUIAction[];
    dataSource?: LooseRecord;
    [key: string]: unknown;
}

export interface TUIPage {
    id: string;
    title: string;
    sections?: TUISection[];
    sidebarGroup?: string;
    textIcon?: string;
    iconName?: string;
    summary?: string;
    [key: string]: unknown;
}

export interface TUIManifest {
    id?: string;
    displayName?: string;
    iconPath?: string;
    pages: TUIPage[];
    setup?: SetupSpec;
    uninstall?: SetupSpec;
    defaultLocalizationCode?: string;
    summary?: string;
    [key: string]: unknown;
}

export type TUILabels = Labels & {
    actionDisabledFallback?: string;
    actionMissingInputsFormat?: string;
    libraryStatusLabels?: StringMap;
    libraryTagLabels?: StringMap;
    setupTitle?: string;
};

export type TUITerminalEntry = TerminalEntry & {
    abortController?: AbortController;
    body: string;
    command: string;
    kind: string;
    title: string;
};

export type TUIBundle = Omit<ManifestResponse, "manifest" | "labels"> & {
    manifest: TUIManifest;
    labels: TUILabels;
    bundleState?: BundleStateSnapshot | null;
};

export type TUIState = TUIBundle & {
    manifest: TUIManifest;
    labels: TUILabels;
    bundleState?: BundleStateSnapshot | null;
    fieldValues: ValueMap;
    checkedOptions: Record<string, Set<string> | string[] | string>;
    configValues: ValueMap;
    configFilePaths: StringMap;
    dataSourcePayloads: Map<string, DataSourcePayload>;
    dataSourceErrors: Map<string, string>;
    terminalEntries: TUITerminalEntry[];
    activePageID: string;
    selectedItemIndex: number;
    selectedTerminalEntryIndex: number;
    focusPane: string;
    terminalTheme: TUIThemePreference;
    terminalResolvedTheme: TUIColorTheme;
    terminalHeightRows: number;
    terminalScrollOffset: number;
    sidebarScrollOffset?: number;
    contentScrollOffset?: number;
    homePath: string;
    setupRun: SetupRun | null;
    setupAutorunStarted?: boolean;
};

export type TUIRenderState = TUIState;

export type TUICommandContext = CommandContext;

export type TUIRunProcess = RunProcess;
