export function parseTomlStrings(text) {
    const values = {};
    const lines = text.split(/\r?\n/);
    let index = 0;
    while (index < lines.length) {
        const rawLine = lines[index];
        const lineNumber = index + 1;
        const line = rawLine.trim();
        index += 1;
        if (!line || line.startsWith("#")) {
            continue;
        }
        if (line.startsWith("[") && line.endsWith("]")) {
            throw new Error(`Invalid localization TOML at line ${lineNumber}: ${rawLine}`);
        }
        const equals = findUnescapedEquals(line);
        if (equals < 0) {
            throw new Error(`Invalid localization TOML at line ${lineNumber}: ${rawLine}`);
        }
        const key = unquoteKey(line.slice(0, equals).trim());
        let rawValue = line.slice(equals + 1).trimStart();
        if (rawValue.startsWith('"""')) {
            rawValue = rawValue.slice(3);
            const collected = [];
            const sameLineEnd = rawValue.indexOf('"""');
            if (sameLineEnd >= 0) {
                collected.push(rawValue.slice(0, sameLineEnd));
            }
            else {
                collected.push(rawValue);
                let foundEnd = false;
                while (index < lines.length) {
                    const nextLine = lines[index];
                    index += 1;
                    const end = nextLine.indexOf('"""');
                    if (end >= 0) {
                        collected.push(nextLine.slice(0, end));
                        foundEnd = true;
                        break;
                    }
                    collected.push(nextLine);
                }
                if (!foundEnd) {
                    throw new Error(`Unterminated multiline localization string: ${key}`);
                }
            }
            if (collected[0] === "") {
                collected.shift();
            }
            if (collected[collected.length - 1] === "") {
                collected.pop();
            }
            values[key] = collected.join("\n");
            continue;
        }
        if (!rawValue.startsWith('"')) {
            throw new Error(`Invalid localization TOML at line ${lineNumber}: ${rawLine}`);
        }
        const closing = findClosingQuote(rawValue);
        if (closing < 0) {
            throw new Error(`Invalid localization TOML at line ${lineNumber}: ${rawLine}`);
        }
        const trailing = rawValue.slice(closing + 1).trim();
        if (trailing && !trailing.startsWith("#")) {
            throw new Error(`Invalid localization TOML at line ${lineNumber}: ${rawLine}`);
        }
        values[key] = unescapeTomlString(rawValue.slice(1, closing));
    }
    return values;
}
export function mergeTables(...tables) {
    return Object.assign({}, ...tables.filter(Boolean));
}
export function localizationLabels(table = {}) {
    return {
        standardOptionsSectionTitle: table["app.standardOptions.title"] ?? "Standard Options",
        languageSectionTitle: table["language.setting.title"] ?? "Interface Language",
        languagePickerLabel: table["language.setting.label"] ?? "Language",
        languageSearchPlaceholder: table["language.setting.searchPlaceholder"] ?? "Search languages",
        languageSystemDefaultLabel: table["language.setting.systemDefault"] ?? "Use system default",
        iconSetPickerLabel: table["app.iconSet.label"] ?? "Icons",
        iconSetSwiftSymbolsLabel: table["app.iconSet.sfSymbols"] ?? "SF Symbols",
        iconSetBootstrapIconsLabel: table["app.iconSet.bootstrapIcons"] ?? "Bootstrap Icons",
        iconSetEmojiLabel: table["app.iconSet.emoji"] ?? "Emoji",
        colorThemePickerLabel: table["app.colorTheme.label"] ?? "Theme",
        colorThemeSystemLabel: table["app.colorTheme.system"] ?? "System",
        colorThemeLightLabel: table["app.colorTheme.light"] ?? "Light",
        colorThemeDarkLabel: table["app.colorTheme.dark"] ?? "Dark",
        layoutDirection: layoutDirection(table["language.layoutDirection"]),
        terminalMainTabTitle: table["app.terminal.mainTab.title"] ?? "Main",
        terminalCommandOutputLabel: table["app.terminal.commandOutput.label"] ?? "Command output",
        terminalShowOutputLabel: table["app.terminal.showOutput.label"] ?? "Show Command Output",
        terminalHideOutputLabel: table["app.terminal.hideOutput.label"] ?? "Hide Command Output",
        terminalCopyTextLabel: table["app.terminal.copyText.label"] ?? "Copy terminal text",
        setupTitle: table["app.setup.status.title"] ?? "Setup",
        setupRunButtonTitle: table["app.setup.runButton.title"] ?? "Run Setup",
        setupRunningTitle: table["app.setup.status.running"] ?? "Running setup...",
        setupNoStepsTitle: table["app.setup.status.none"] ?? "No setup steps are defined for this bundle.",
        setupStatusReadyTitle: table["app.setup.status.ready"] ?? "Review and run this bundle's setup steps.",
        setupStatusOkTitle: table["app.setup.status.ok"] ?? "Setup completed successfully.",
        setupStatusFailedTitle: table["app.setup.status.failed"] ?? "Setup failed. Review command output for details.",
        setupStepPendingTitle: table["app.setup.step.pending"] ?? "Pending",
        setupStepRunningTitle: table["app.setup.step.running"] ?? "Running",
        setupStepOkTitle: table["app.setup.step.ok"] ?? "OK",
        setupStepWarningTitle: table["app.setup.step.warning"] ?? "Warning",
        setupStepFailedTitle: table["app.setup.step.failed"] ?? "Failed",
        chooseButtonTitle: table["app.pathPicker.chooseButton.title"] ?? "Choose...",
        pathPickerErrorTitle: table["app.pathPicker.error.title"] ?? "Could not choose path",
        settingsFileLabel: table["app.settingsFile.label"] ?? "Settings File",
        loadButtonTitle: table["app.loadButton.title"] ?? "Load",
        saveButtonTitle: table["app.saveButton.title"] ?? "Save",
        actionsColumnTitle: table["app.actionsColumn.title"] ?? "Actions",
        loadingTitle: table["app.loading.title"] ?? "Loading...",
        refreshingTitle: table["app.refreshing.title"] ?? "Refreshing...",
        retryButtonTitle: table["app.retryButton.title"] ?? "Retry",
        loadWebUITitle: table["app.error.loadWebUI.title"] ?? "Could not load Web UI",
        libraryEmptyTitle: table["app.library.empty"] ?? "No library items are defined.",
        actionMissingInputsFormat: table["app.action.missingInputs.format"] ?? "Missing: %{inputs}",
        actionUnavailableTitle: table["app.action.unavailable.title"] ?? "This action is not available.",
        terminalCloseTabLabelFormat: table["app.terminal.closeTab.labelFormat"] ?? "Close %{title}",
        terminalExitCodeTitleFormat: table["app.terminal.exitCode.titleFormat"] ?? "Exit code %{code}",
        terminalExitDetailFormat: table["app.terminal.exitCode.detailFormat"] ?? "%{command} exited with code %{code}.",
        terminalNonzeroExitSummary: table["app.terminal.nonzeroExit.summary"] ??
            "The command exited with a non-zero status. Check the command output for details.",
        terminalProcessErrorTitle: table["app.terminal.processError.title"] ?? "Command failed",
        terminalProcessErrorSummary: table["app.terminal.processError.summary"] ?? "The command could not complete.",
        configLoadedFormat: table["app.config.loaded.format"] ?? "Loaded settings from %{path}",
        configLoadErrorFormat: table["app.config.loadError.format"] ?? "Could not load %{label}: %{error}",
        configSavedFormat: table["app.config.saved.format"] ?? "Saved %{count} setting(s) to %{path}",
        configSaveErrorFormat: table["app.config.saveError.format"] ?? "Could not save %{label}: %{error}",
        actionPrecheckDiskSpaceTitle: table["app.action.precheck.diskSpace.title"] ?? "Not enough free disk space",
        actionPrecheckDiskSpaceMessageFormat: table["app.action.precheck.diskSpace.messageFormat"] ??
            "Need %{required} GB free at %{path}, only %{available} GB available.",
        actionPrecheckDiskSpaceInfoTitle: table["app.action.precheck.diskSpace.infoTitle"] ?? "Disk space estimate",
        actionPrecheckDiskSpaceInfoFormat: table["app.action.precheck.diskSpace.infoFormat"] ??
            "Estimated %{required} GB needed at %{path} (%{available} GB free).",
        libraryStatusLabels: {
            installed: table["library.status.installed"] ?? "installed",
            unindexed: table["library.status.unindexed"] ?? "unindexed",
            incomplete: table["library.status.incomplete"] ?? "incomplete",
            missing: table["library.status.missing"] ?? "missing",
        },
        libraryTagLabels: {
            recommended: table["library.tags.recommended"] ?? "Recommended",
        },
    };
}
export function localizeManifest(rawManifest, table = {}) {
    const manifest = structuredClone(rawManifest);
    manifest.displayName = localized(manifest.displayName, table);
    manifest.summary = localized(manifest.summary, table);
    manifest.setup = manifest.setup ?? { steps: [] };
    manifest.setup.steps = (manifest.setup.steps ?? []).map((step) => ({
        ...step,
        label: localized(step.label, table),
    }));
    manifest.exitCodeReference = (manifest.exitCodeReference ?? []).map((entry) => ({
        ...entry,
        title: localized(entry.title, table),
        summary: localized(entry.summary, table),
    }));
    manifest.pages = (manifest.pages ?? []).map((page) => localizePage(page, table));
    return manifest;
}
function localizePage(page, table) {
    return {
        ...page,
        title: localized(page.title, table),
        summary: localized(page.summary, table),
        sidebarGroup: localizedOptional(page.sidebarGroup, table),
        sections: (page.sections ?? []).map((section) => localizeSection(section, table)),
    };
}
function localizeSection(section, table) {
    return {
        ...section,
        title: localizedOptional(section.title, table),
        subtitle: localizedOptional(section.subtitle, table),
        controls: (section.controls ?? []).map((control) => localizeControl(control, table)),
        actions: (section.actions ?? []).map((action) => localizeAction(action, table)),
    };
}
function localizeControl(control, table) {
    const localizedControl = {
        ...control,
        label: localized(control.label, table),
        placeholder: localizedOptional(control.placeholder, table),
        tooltip: localizedOptional(control.tooltip, table),
        options: (control.options ?? []).map((option) => ({
            ...option,
            title: localized(option.title, table),
        })),
        columns: (control.columns ?? []).map((column) => ({
            ...column,
            title: localized(column.title, table),
        })),
        rows: (control.rows ?? []).map((row) => localizeRow(row, table)),
        items: (control.items ?? []).map((item) => ({
            ...item,
            values: mapValues(item.values ?? item, (value) => localized(String(value), table)),
        })),
        rowActions: (control.rowActions ?? []).map((action) => localizeAction(action, table)),
        settings: (control.settings ?? []).map((setting) => localizeSetting(setting, table)),
    };
    if (control.rowTemplate) {
        localizedControl.rowTemplate = localizeRow(control.rowTemplate, table);
    }
    return localizedControl;
}
function localizeRow(row, table) {
    return {
        ...row,
        title: localizedOptional(row.title, table),
        status: localizedOptional(row.status, table),
        tags: (row.tags ?? []).map((tag) => ({
            ...tag,
            title: localized(tag.title, table),
        })),
        tooltip: localizedOptional(row.tooltip, table),
    };
}
function localizeAction(action, table) {
    return {
        ...action,
        title: localized(action.title, table),
        tooltip: localizedOptional(action.tooltip, table),
        disabledTooltip: localizedOptional(action.disabledTooltip, table),
        confirm: action.confirm ? localizeConfirmation(action.confirm, table) : undefined,
    };
}
function localizeConfirmation(confirm, table) {
    return {
        ...confirm,
        title: localized(confirm.title, table),
        message: localized(confirm.message, table),
        confirmButtonTitle: localized(confirm.confirmButtonTitle, table),
        cancelButtonTitle: localized(confirm.cancelButtonTitle, table),
        requiredText: localizedOptional(confirm.requiredText, table),
        prompt: localizedOptional(confirm.prompt, table),
    };
}
function localizeSetting(setting, table) {
    return {
        ...setting,
        label: localized(setting.label, table),
        placeholder: localizedOptional(setting.placeholder, table),
        tooltip: localizedOptional(setting.tooltip, table),
        options: (setting.options ?? []).map((option) => ({
            ...option,
            title: localized(option.title, table),
        })),
    };
}
function localized(value, table) {
    return table[value] ?? value;
}
function localizedOptional(value, table) {
    return value == null ? value : localized(value, table);
}
function mapValues(values, transform) {
    return Object.fromEntries(Object.entries(values).map(([key, value]) => [key, transform(value)]));
}
function layoutDirection(value) {
    const normalized = String(value ?? "").trim().toLowerCase();
    return ["rtl", "right-to-left", "righttoleft"].includes(normalized) ? "rtl" : "ltr";
}
function findUnescapedEquals(line) {
    let quoted = false;
    let escaped = false;
    for (let i = 0; i < line.length; i += 1) {
        const char = line[i];
        if (escaped) {
            escaped = false;
        }
        else if (char === "\\") {
            escaped = true;
        }
        else if (char === '"') {
            quoted = !quoted;
        }
        else if (char === "=" && !quoted) {
            return i;
        }
    }
    return -1;
}
function findClosingQuote(value) {
    let escaped = false;
    for (let i = 1; i < value.length; i += 1) {
        const char = value[i];
        if (escaped) {
            escaped = false;
        }
        else if (char === "\\") {
            escaped = true;
        }
        else if (char === '"') {
            return i;
        }
    }
    return -1;
}
function unquoteKey(key) {
    return key.startsWith('"') && key.endsWith('"') ? unescapeTomlString(key.slice(1, -1)) : key;
}
function unescapeTomlString(value) {
    return value.replace(/\\([nrt"\\])/g, (_, escaped) => {
        switch (escaped) {
            case "n":
                return "\n";
            case "r":
                return "\r";
            case "t":
                return "\t";
            case '"':
                return '"';
            case "\\":
                return "\\";
            default:
                return escaped;
        }
    });
}
