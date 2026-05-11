import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { api, apiBase } from './api';
import {
  actionPrecheckCacheKey,
  configSettingBindings,
  createMainTerminal,
  errorMessage,
  normalizeColorTheme,
  normalizeIconSet,
  normalizeWebUIFont,
  pathPickerKind,
  pathPickerTitle,
  terminalExitStatus,
  terminalProcessErrorStatus,
} from './model';
import { configValueKey, displayCommand, setupResultLine } from './webuiCore';

function createInitialSnapshot() {
  return {
    status: 'loading',
    error: '',
    manifest: null as any,
    labels: {} as Record<string, any>,
    localizationCode: '',
    localizationOptions: [],
    iconSet: 'platform',
    colorTheme: 'system',
    webUIFont: 'system',
    bundleRootPath: '',
    sourceRootPath: '',
    activePageID: '',
    fieldValues: {},
    checkedOptions: {},
    configValues: {},
    configFilePaths: {},
    dataSourcePayloads: new Map<string, any>(),
    dataSourceErrors: new Map<string, string>(),
    loadingDataSources: new Set<string>(),
    fileStateValues: new Map<string, Record<string, string>>(),
    loadingFileStates: new Set<string>(),
    actionPrechecks: new Map<string, any>(),
    actionPrecheckErrors: new Map<string, string>(),
    loadingActionPrechecks: new Set<string>(),
    exitCodeReference: new Map<number, any>(),
    setupRun: null,
    setupAutorunStarted: false,
    terminalEntries: [] as any[],
    activeTerminalID: 'main',
    isSidebarVisible: true,
    isTerminalVisible: true,
    pendingConfirmation: null as any,
  };
}

function randomID(prefix: string): string {
  return `${prefix}-${Date.now().toString(36)}-${Math.random()
    .toString(36)
    .slice(2, 8)}`;
}

function formatConfigMessage(
  template: string | undefined,
  path: string,
  count?: number,
): string {
  return String(template ?? path)
    .replace(/%\{path\}/g, path)
    .replace(/%\{count\}/g, String(count ?? ''));
}

async function readNDJSONEvents(
  response: Response,
  onEvent: (event: any) => void,
) {
  const body = response.body as any;
  if (body?.getReader && typeof TextDecoder !== 'undefined') {
    const reader = body.getReader();
    const decoder = new TextDecoder();
    let buffer = '';
    while (true) {
      const { value, done } = await reader.read();
      if (done) {
        break;
      }
      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split(/\r?\n/);
      buffer = lines.pop() ?? '';
      for (const line of lines) {
        if (line.trim()) {
          onEvent(JSON.parse(line));
        }
      }
    }
    buffer += decoder.decode();
    if (buffer.trim()) {
      onEvent(JSON.parse(buffer));
    }
    return;
  }

  const text = await response.text();
  for (const line of text.split(/\r?\n/)) {
    if (line.trim()) {
      onEvent(JSON.parse(line));
    }
  }
}

function applySetupEventToSnapshot(snapshot: any, setupID: string, event: any) {
  const terminalEntries = snapshot.terminalEntries.map((entry: any) => ({
    ...entry,
  }));
  const tab = terminalEntries.find((entry: any) => entry.id === setupID);
  let setupRun = snapshot.setupRun;
  if (!tab) {
    return snapshot;
  }
  switch (event.type) {
    case 'step-start':
      setupRun = {
        ...(setupRun ?? {}),
        status: 'running',
        currentStepID: event.step.id,
      };
      tab.body = [
        tab.body,
        `==> ${event.step.label}`,
        `$ ${event.step.command}\n`,
      ]
        .filter(Boolean)
        .join('\n');
      break;
    case 'output':
      tab.body += event.text ?? '';
      break;
    case 'step-complete':
      setupRun = {
        ...(setupRun ?? {}),
        status: 'running',
        currentStepID: null,
        results: [
          ...(setupRun?.results ?? []).filter(
            (result: any) => result.id !== event.result.id,
          ),
          event.result,
        ],
      };
      tab.body = [tab.body, setupResultLine(event.result)]
        .filter(Boolean)
        .join('\n');
      break;
    case 'complete':
      setupRun = {
        ...event.result,
        completedAt: new Date().toISOString(),
        currentStepID: null,
      };
      tab.kind = event.result?.status === 'ok' ? 'success' : 'error';
      break;
  }
  return { ...snapshot, setupRun, terminalEntries };
}

export function useGuiForCLIApp() {
  const [snapshot, setSnapshot] = useState(createInitialSnapshot);
  const snapshotRef = useRef(snapshot);
  const runningActionControllersRef = useRef(
    new Map<string, AbortController>(),
  );

  useEffect(() => {
    snapshotRef.current = snapshot;
  }, [snapshot]);

  const replaceTerminalEntry = useCallback((id: string, next: any) => {
    setSnapshot(current => ({
      ...current,
      terminalEntries: current.terminalEntries.map(entry =>
        entry.id === id ? next : entry,
      ),
    }));
  }, []);

  const clearDerivedCaches = useCallback(() => {
    setSnapshot(current => ({
      ...current,
      dataSourcePayloads: new Map(),
      dataSourceErrors: new Map(),
      fileStateValues: new Map(),
      actionPrechecks: new Map(),
      actionPrecheckErrors: new Map(),
    }));
  }, []);

  const persistState = useCallback(async (state: Record<string, unknown>) => {
    await api('/api/state/save', { method: 'POST', body: { state } });
  }, []);

  const appendTerminalEntry = useCallback((entry: any) => {
    const id = entry.id ?? randomID(entry.kind ?? 'entry');
    setSnapshot(current => ({
      ...current,
      terminalEntries: [...current.terminalEntries, { ...entry, id }].slice(
        -40,
      ),
      activeTerminalID: id,
    }));
    return id;
  }, []);

  const reportError = useCallback(
    (error: unknown, title = 'React Native interaction') => {
      appendTerminalEntry({
        kind: 'error',
        title,
        body: errorMessage(error),
        command: 'react-native',
      });
    },
    [appendTerminalEntry],
  );

  const loadManifest = useCallback(async (locale?: string) => {
    setSnapshot(current => ({ ...current, status: 'loading', error: '' }));
    try {
      const body = await api(
        locale
          ? `/api/manifest?locale=${encodeURIComponent(locale)}`
          : '/api/manifest',
      );
      const exitCodeReference = new Map<number, any>(
        (body.manifest?.exitCodeReference ?? []).map((entry: any) => [
          entry.code,
          entry,
        ]),
      );
      const requestedPageID = body.bundleState?.selectedPageID;
      const activePageID =
        requestedPageID &&
        body.manifest?.pages?.some((page: any) => page.id === requestedPageID)
          ? requestedPageID
          : body.manifest?.pages?.[0]?.id ?? '';
      setSnapshot(current => ({
        ...current,
        status: 'ready',
        error: '',
        manifest: body.manifest,
        labels: body.labels ?? {},
        localizationCode: body.localizationCode ?? '',
        localizationOptions: body.localizationOptions ?? [],
        iconSet: normalizeIconSet(body.bundleState?.iconSet),
        colorTheme: normalizeColorTheme(body.bundleState?.colorTheme),
        webUIFont: normalizeWebUIFont(body.bundleState?.webUIFont),
        bundleRootPath: body.bundleRootPath ?? '',
        sourceRootPath: body.sourceRootPath ?? '',
        activePageID,
        fieldValues: body.fieldValues ?? {},
        checkedOptions: body.checkedOptions ?? {},
        configValues: body.configValues ?? {},
        configFilePaths: body.configFilePaths ?? {},
        dataSourcePayloads: new Map(),
        dataSourceErrors: new Map(),
        loadingDataSources: new Set(),
        fileStateValues: new Map(),
        loadingFileStates: new Set(),
        actionPrechecks: new Map(),
        actionPrecheckErrors: new Map(),
        loadingActionPrechecks: new Set(),
        exitCodeReference,
        setupRun: body.bundleState?.setupRun ?? null,
        terminalEntries:
          current.terminalEntries.length > 0
            ? current.terminalEntries
            : [createMainTerminal(body.labels)],
        activeTerminalID:
          current.activeTerminalID || createMainTerminal(body.labels).id,
      }));
    } catch (error) {
      setSnapshot(current => ({
        ...current,
        status: 'error',
        error: errorMessage(error),
      }));
    }
  }, []);

  useEffect(() => {
    loadManifest().catch(error => {
      setSnapshot(current => ({
        ...current,
        status: 'error',
        error: errorMessage(error),
      }));
    });
  }, [loadManifest]);

  const updateActivePage = useCallback(
    async (pageID: string) => {
      setSnapshot(current => ({ ...current, activePageID: pageID }));
      await persistState({ selectedPageID: pageID });
    },
    [persistState],
  );

  const setFieldValue = useCallback(
    async (control: any, value: string) => {
      const manifest = snapshotRef.current.manifest;
      const nextFieldValues: Record<string, string> = {
        ...(snapshotRef.current.fieldValues ?? {}),
        [control.id]: value,
      };
      const nextConfigValues: Record<string, string> = {
        ...(snapshotRef.current.configValues ?? {}),
      };
      for (const binding of configSettingBindings(manifest, control.id)) {
        nextConfigValues[configValueKey(binding.control, binding.setting)] =
          value;
        await api('/api/config/save', {
          method: 'POST',
          body: {
            control: binding.control,
            path: (
              snapshotRef.current.configFilePaths as
                | Record<string, string>
                | undefined
            )?.[binding.control.id],
            values: Object.fromEntries(
              (binding.control.settings ?? []).map((setting: any) => [
                setting.key,
                setting.id === binding.setting.id
                  ? value
                  : nextConfigValues[
                      configValueKey(binding.control, setting)
                    ] ??
                    setting.value ??
                    '',
              ]),
            ),
          },
        });
      }
      setSnapshot(current => ({
        ...current,
        fieldValues: nextFieldValues,
        configValues: nextConfigValues,
      }));
      clearDerivedCaches();
      await persistState({
        fieldValues: nextFieldValues,
        checkedOptions: snapshotRef.current.checkedOptions,
      });
    },
    [clearDerivedCaches, persistState],
  );

  const setCheckedValues = useCallback(
    async (control: any, selectedIDs: string[], controlID?: string) => {
      const targetID = controlID ?? control.id;
      const nextCheckedOptions: Record<string, string[]> = {
        ...(snapshotRef.current.checkedOptions ?? {}),
        [targetID]: selectedIDs,
      };
      const nextConfigValues: Record<string, string> = {
        ...(snapshotRef.current.configValues ?? {}),
      };
      for (const binding of configSettingBindings(
        snapshotRef.current.manifest,
        targetID,
      )) {
        nextConfigValues[configValueKey(binding.control, binding.setting)] = [
          ...selectedIDs,
        ]
          .sort()
          .join(',');
        await api('/api/config/save', {
          method: 'POST',
          body: {
            control: binding.control,
            path: (
              snapshotRef.current.configFilePaths as
                | Record<string, string>
                | undefined
            )?.[binding.control.id],
            values: Object.fromEntries(
              (binding.control.settings ?? []).map((setting: any) => [
                setting.key,
                nextConfigValues[configValueKey(binding.control, setting)] ??
                  setting.value ??
                  '',
              ]),
            ),
          },
        });
      }
      setSnapshot(current => ({
        ...current,
        checkedOptions: nextCheckedOptions,
        configValues: nextConfigValues,
      }));
      clearDerivedCaches();
      await persistState({
        fieldValues: snapshotRef.current.fieldValues,
        checkedOptions: nextCheckedOptions,
      });
    },
    [clearDerivedCaches, persistState],
  );

  const setConfigValue = useCallback(
    async (control: any, setting: any, value: string) => {
      const key = configValueKey(control, setting);
      const nextConfigValues: Record<string, string> = {
        ...(snapshotRef.current.configValues ?? {}),
        [key]: value,
      };
      const nextFieldValues: Record<string, string> = {
        ...(snapshotRef.current.fieldValues ?? {}),
      };
      if (Object.hasOwn(nextFieldValues, setting.key)) {
        nextFieldValues[setting.key] = value;
      }
      if (Object.hasOwn(nextFieldValues, setting.id)) {
        nextFieldValues[setting.id] = value;
      }
      const result = await api('/api/config/save', {
        method: 'POST',
        body: {
          control,
          path: (
            snapshotRef.current.configFilePaths as
              | Record<string, string>
              | undefined
          )?.[control.id],
          values: Object.fromEntries(
            (control.settings ?? []).map((candidate: any) => [
              candidate.key,
              candidate.id === setting.id
                ? value
                : nextConfigValues[configValueKey(control, candidate)] ??
                  candidate.value ??
                  '',
            ]),
          ),
        },
      });
      setSnapshot(current => ({
        ...current,
        fieldValues: nextFieldValues,
        configValues: nextConfigValues,
        configFilePaths: {
          ...(current.configFilePaths ?? {}),
          [control.id]: result.path,
        },
      }));
      clearDerivedCaches();
      await persistState({
        fieldValues: nextFieldValues,
        checkedOptions: snapshotRef.current.checkedOptions,
      });
    },
    [clearDerivedCaches, persistState],
  );

  const ensureDataSource = useCallback(
    async (key: string, dataSource: any, context: any) => {
      const current = snapshotRef.current;
      if (
        current.dataSourcePayloads.has(key) ||
        current.loadingDataSources.has(key) ||
        current.dataSourceErrors.has(key)
      ) {
        return;
      }
      setSnapshot(state => ({
        ...state,
        loadingDataSources: new Set([...state.loadingDataSources, key]),
      }));
      try {
        const payload = await api('/api/datasource', {
          method: 'POST',
          body: { dataSource, context },
        });
        setSnapshot(state => {
          const nextPayloads = new Map(state.dataSourcePayloads);
          const nextLoading = new Set(state.loadingDataSources);
          const nextErrors = new Map(state.dataSourceErrors);
          const nextFieldValues = { ...(state.fieldValues ?? {}) };
          const nextConfigValues = { ...(state.configValues ?? {}) };
          nextPayloads.set(key, payload);
          nextLoading.delete(key);
          nextErrors.delete(key);
          const options = payload.options ?? [];
          const defaultValue =
            options.find((option: any) => option.selected)?.id ??
            options[0]?.id;
          if (defaultValue && key.startsWith('control:')) {
            const controlID = key.slice('control:'.length);
            const currentValue = String(
              nextFieldValues[controlID] ?? '',
            ).trim();
            if (
              !currentValue ||
              !options.some((option: any) => option.id === currentValue)
            ) {
              nextFieldValues[controlID] = defaultValue;
            }
          }
          if (defaultValue && key.startsWith('setting:')) {
            const settingKey = key.slice('setting:'.length);
            const currentValue = String(
              nextConfigValues[settingKey] ?? '',
            ).trim();
            if (
              !currentValue ||
              !options.some((option: any) => option.id === currentValue)
            ) {
              nextConfigValues[settingKey] = defaultValue;
            }
          }
          return {
            ...state,
            dataSourcePayloads: nextPayloads,
            dataSourceErrors: nextErrors,
            loadingDataSources: nextLoading,
            fieldValues: nextFieldValues,
            configValues: nextConfigValues,
          };
        });
      } catch (error) {
        setSnapshot(state => {
          const nextLoading = new Set(state.loadingDataSources);
          const nextErrors = new Map(state.dataSourceErrors);
          nextLoading.delete(key);
          nextErrors.set(key, errorMessage(error));
          return {
            ...state,
            dataSourceErrors: nextErrors,
            loadingDataSources: nextLoading,
          };
        });
      }
    },
    [],
  );

  const ensureFileState = useCallback(
    async (key: string, context: any) => {
      const current = snapshotRef.current;
      if (
        current.fileStateValues.has(key) ||
        current.loadingFileStates.has(key)
      ) {
        return;
      }
      setSnapshot(state => ({
        ...state,
        loadingFileStates: new Set([...state.loadingFileStates, key]),
      }));
      try {
        const result = await api('/api/file-state', {
          method: 'POST',
          body: { context },
        });
        setSnapshot(state => {
          const nextValues = new Map(state.fileStateValues);
          const nextLoading = new Set(state.loadingFileStates);
          nextValues.set(key, result.values ?? {});
          nextLoading.delete(key);
          return {
            ...state,
            fileStateValues: nextValues,
            loadingFileStates: nextLoading,
          };
        });
      } catch (error) {
        appendTerminalEntry({
          kind: 'warning',
          title:
            snapshotRef.current.labels.fileStateWarningTitle ?? 'File state',
          body: errorMessage(error),
          command: 'file-state',
        });
        setSnapshot(state => {
          const nextLoading = new Set(state.loadingFileStates);
          nextLoading.delete(key);
          const nextValues = new Map(state.fileStateValues);
          nextValues.set(key, {});
          return {
            ...state,
            fileStateValues: nextValues,
            loadingFileStates: nextLoading,
          };
        });
      }
    },
    [appendTerminalEntry],
  );

  const ensureActionPrecheck = useCallback(
    async (action: any, context: any) => {
      const key = actionPrecheckCacheKey(action, context);
      const current = snapshotRef.current;
      if (
        current.actionPrechecks.has(key) ||
        current.loadingActionPrechecks.has(key) ||
        current.actionPrecheckErrors.has(key)
      ) {
        return;
      }
      setSnapshot(state => ({
        ...state,
        loadingActionPrechecks: new Set([...state.loadingActionPrechecks, key]),
      }));
      try {
        const result = await api('/api/precheck', {
          method: 'POST',
          body: {
            precheck: action.precheck,
            context,
            labels: snapshotRef.current.labels,
          },
        });
        setSnapshot(state => {
          const nextValues = new Map(state.actionPrechecks);
          const nextLoading = new Set(state.loadingActionPrechecks);
          const nextErrors = new Map(state.actionPrecheckErrors);
          nextValues.set(key, result);
          nextLoading.delete(key);
          nextErrors.delete(key);
          return {
            ...state,
            actionPrechecks: nextValues,
            loadingActionPrechecks: nextLoading,
            actionPrecheckErrors: nextErrors,
          };
        });
      } catch (error) {
        setSnapshot(state => {
          const nextLoading = new Set(state.loadingActionPrechecks);
          const nextErrors = new Map(state.actionPrecheckErrors);
          nextLoading.delete(key);
          nextErrors.set(key, errorMessage(error));
          return {
            ...state,
            loadingActionPrechecks: nextLoading,
            actionPrecheckErrors: nextErrors,
          };
        });
      }
    },
    [],
  );

  const executeAction = useCallback(
    async (action: any, context: any) => {
      const id = randomID(action.id ?? 'action');
      const command = displayCommand(action.command, context);
      const runningEntry = {
        id,
        kind: 'command',
        title: action.title,
        body: `$ ${command}`,
        command,
      };
      const controller = new AbortController();
      runningActionControllersRef.current.set(id, controller);
      setSnapshot(state => ({
        ...state,
        terminalEntries: [...state.terminalEntries, runningEntry].slice(-40),
        activeTerminalID: id,
      }));
      try {
        const result = await api('/api/run', {
          method: 'POST',
          body: { action, context },
          signal: controller.signal,
        });
        const status =
          result.exitCode === 0
            ? null
            : terminalExitStatus(
                snapshotRef.current.labels,
                snapshotRef.current.exitCodeReference,
                result.exitCode,
                result.command,
              );
        replaceTerminalEntry(id, {
          id,
          kind: result.exitCode === 0 ? 'success' : status.severity,
          title: action.title,
          command: result.command,
          body: [
            `$ ${result.command}`,
            result.stdout,
            result.stderr,
            `exit ${result.exitCode}`,
          ]
            .filter(Boolean)
            .join('\n'),
          status,
        });
        clearDerivedCaches();
      } catch (error) {
        const aborted =
          error instanceof Error &&
          (error.name === 'AbortError' || /abort/i.test(error.message));
        const status = aborted
          ? terminalExitStatus(
              snapshotRef.current.labels,
              snapshotRef.current.exitCodeReference,
              130,
              command,
            )
          : terminalProcessErrorStatus(
              snapshotRef.current.labels,
              command,
              errorMessage(error),
            );
        replaceTerminalEntry(id, {
          id,
          kind: aborted ? 'warning' : 'error',
          title: action.title,
          command,
          body: aborted
            ? [
                `$ ${command}`,
                snapshotRef.current.labels.terminalCancelledTitle ??
                  'Command cancelled',
              ].join('\n')
            : errorMessage(error),
          status,
        });
      } finally {
        runningActionControllersRef.current.delete(id);
      }
    },
    [clearDerivedCaches, replaceTerminalEntry],
  );

  const runAction = useCallback(
    async (action: any, context: any) => {
      if (action.confirm) {
        setSnapshot(current => ({
          ...current,
          pendingConfirmation: { action, context, input: '' },
        }));
        return;
      }
      await executeAction(action, context);
    },
    [executeAction],
  );

  const selectLocale = useCallback(
    async (locale: string) => {
      await persistState({ localizationCode: locale });
      await loadManifest(locale);
    },
    [loadManifest, persistState],
  );

  const selectIconSet = useCallback(
    async (iconSet: 'platform' | 'emoji') => {
      setSnapshot(current => ({ ...current, iconSet }));
      await persistState({ iconSet });
    },
    [persistState],
  );

  const selectColorTheme = useCallback(
    async (colorTheme: 'system' | 'light' | 'dark') => {
      setSnapshot(current => ({ ...current, colorTheme }));
      await persistState({ colorTheme });
    },
    [persistState],
  );

  const selectWebUIFont = useCallback(
    async (webUIFont: 'system' | 'sfPro') => {
      setSnapshot(current => ({ ...current, webUIFont }));
      await persistState({ webUIFont });
    },
    [persistState],
  );

  const setConfigFilePath = useCallback(
    async (control: any, path: string) => {
      const nextConfigFilePaths = {
        ...(snapshotRef.current.configFilePaths ?? {}),
        [control.id]: path,
      };
      setSnapshot(current => ({
        ...current,
        configFilePaths: nextConfigFilePaths,
      }));
      await persistState({ configFilePaths: nextConfigFilePaths });
    },
    [persistState],
  );

  const loadConfig = useCallback(
    async (control: any) => {
      try {
        const result = await api('/api/config/load', {
          method: 'POST',
          body: {
            control,
            path: (snapshotRef.current.configFilePaths as any)?.[control.id],
          },
        });
        const nextConfigValues = {
          ...(snapshotRef.current.configValues ?? {}),
        };
        const nextFieldValues = { ...(snapshotRef.current.fieldValues ?? {}) };
        for (const setting of control.settings ?? []) {
          const value = result.values?.[setting.key] ?? setting.value ?? '';
          nextConfigValues[configValueKey(control, setting)] = value;
          if (Object.hasOwn(nextFieldValues, setting.key)) {
            nextFieldValues[setting.key] = value;
          }
          if (Object.hasOwn(nextFieldValues, setting.id)) {
            nextFieldValues[setting.id] = value;
          }
        }
        const nextConfigFilePaths = {
          ...(snapshotRef.current.configFilePaths ?? {}),
          [control.id]: result.path,
        };
        setSnapshot(current => ({
          ...current,
          fieldValues: nextFieldValues,
          configValues: nextConfigValues,
          configFilePaths: nextConfigFilePaths,
        }));
        clearDerivedCaches();
        await persistState({
          fieldValues: nextFieldValues,
          configFilePaths: nextConfigFilePaths,
        });
        appendTerminalEntry({
          kind: 'config',
          title: control.label,
          body: formatConfigMessage(
            snapshotRef.current.labels.configLoadedFormat,
            result.path,
          ),
          command: 'config/load',
        });
      } catch (error) {
        appendTerminalEntry({
          kind: 'error',
          title: control.label,
          body: errorMessage(error),
          command: 'config/load',
        });
      }
    },
    [appendTerminalEntry, clearDerivedCaches, persistState],
  );

  const saveConfig = useCallback(
    async (control: any) => {
      try {
        const result = await api('/api/config/save', {
          method: 'POST',
          body: {
            control,
            path: (snapshotRef.current.configFilePaths as any)?.[control.id],
            values: Object.fromEntries(
              (control.settings ?? []).map((setting: any) => [
                setting.key,
                snapshotRef.current.configValues[
                  configValueKey(control, setting)
                ] ??
                  setting.value ??
                  '',
              ]),
            ),
          },
        });
        const nextConfigFilePaths = {
          ...(snapshotRef.current.configFilePaths ?? {}),
          [control.id]: result.path,
        };
        setSnapshot(current => ({
          ...current,
          configFilePaths: nextConfigFilePaths,
        }));
        await persistState({ configFilePaths: nextConfigFilePaths });
        appendTerminalEntry({
          kind: 'config',
          title: control.label,
          body: formatConfigMessage(
            snapshotRef.current.labels.configSavedFormat,
            result.path,
            result.keyCount,
          ),
          command: 'config/save',
        });
      } catch (error) {
        appendTerminalEntry({
          kind: 'error',
          title: control.label,
          body: errorMessage(error),
          command: 'config/save',
        });
      }
    },
    [appendTerminalEntry, persistState],
  );

  const choosePath = useCallback(
    async (
      spec: any,
      currentValue: string,
      onSelect: (path: string) => Promise<void>,
    ) => {
      try {
        const result = await api('/api/path/pick', {
          method: 'POST',
          body: {
            kind: pathPickerKind(spec),
            title: pathPickerTitle(snapshotRef.current.labels, spec),
            defaultPath: currentValue,
          },
        });
        if (!result.cancelled && result.path) {
          await onSelect(result.path);
        }
      } catch (error) {
        appendTerminalEntry({
          kind: 'error',
          title: pathPickerTitle(snapshotRef.current.labels, spec),
          body: errorMessage(error),
          command: 'path/pick',
        });
      }
    },
    [appendTerminalEntry],
  );

  const runSetup = useCallback(async () => {
    const setupID = appendTerminalEntry({
      kind: 'command',
      title: snapshotRef.current.labels.setupTitle ?? 'Setup',
      body: snapshotRef.current.labels.setupRunningTitle ?? 'Running setup...',
      command: 'bundle setup',
    });
    setSnapshot(current => ({
      ...current,
      setupRun: { status: 'running', results: [], currentStepID: null },
      activeTerminalID: setupID,
    }));
    try {
      const response = await fetch(`${apiBase()}/api/setup/stream`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ locale: snapshotRef.current.localizationCode }),
      });
      if (!response.ok) {
        throw new Error(response.statusText || `HTTP ${response.status}`);
      }
      let finalSetupRun: any = null;
      await readNDJSONEvents(response, event => {
        setSnapshot(current => {
          const next = applySetupEventToSnapshot(current, setupID, event);
          finalSetupRun = next.setupRun;
          return next;
        });
      });
      if (finalSetupRun?.status && finalSetupRun.status !== 'running') {
        await persistState({ setupRun: finalSetupRun });
      }
    } catch (error) {
      const failedRun = {
        status: 'failed',
        results: snapshotRef.current.setupRun?.results ?? [],
        error: errorMessage(error),
        completedAt: new Date().toISOString(),
      };
      setSnapshot(current => ({
        ...current,
        setupRun: failedRun,
        terminalEntries: current.terminalEntries.map(entry =>
          entry.id === setupID
            ? {
                ...entry,
                kind: 'error',
                body: [entry.body, errorMessage(error)]
                  .filter(Boolean)
                  .join('\n'),
              }
            : entry,
        ),
      }));
      await persistState({ setupRun: failedRun });
    }
  }, [appendTerminalEntry, persistState]);

  const openBundleWorkspace = useCallback(async () => {
    await executeAction(
      {
        id: 'open-bundle-workspace',
        title:
          snapshotRef.current.labels.openBundleWorkspaceTitle ??
          'Open Bundle Workspace',
        tooltip: snapshotRef.current.labels.openBundleWorkspaceTooltip,
        iconName: 'folder',
        command: {
          executable: '/usr/bin/open',
          arguments: ['{{bundleWorkspace}}'],
        },
      },
      {
        fieldValues: {},
        checkedOptions: {},
        configValues: {},
        rowValues: {},
        bundleRootPath: snapshotRef.current.bundleRootPath,
      },
    );
  }, [executeAction]);

  useEffect(() => {
    if (
      snapshot.status !== 'ready' ||
      snapshot.setupAutorunStarted ||
      snapshot.setupRun ||
      !(snapshot.manifest?.setup?.steps ?? []).length
    ) {
      return;
    }
    setSnapshot(current => ({ ...current, setupAutorunStarted: true }));
    runSetup().catch(error => {
      appendTerminalEntry({
        kind: 'error',
        title: snapshotRef.current.labels.setupTitle ?? 'Setup',
        body: errorMessage(error),
        command: 'bundle setup',
      });
    });
  }, [
    appendTerminalEntry,
    runSetup,
    snapshot.manifest,
    snapshot.setupAutorunStarted,
    snapshot.setupRun,
    snapshot.status,
  ]);

  const closeTerminal = useCallback((id: string) => {
    if (id === 'main') {
      return;
    }
    runningActionControllersRef.current.get(id)?.abort();
    runningActionControllersRef.current.delete(id);
    setSnapshot(current => {
      const remaining = current.terminalEntries.filter(
        entry => entry.id !== id,
      );
      return {
        ...current,
        terminalEntries: remaining,
        activeTerminalID: remaining[remaining.length - 1]?.id ?? 'main',
      };
    });
  }, []);

  const cancelAction = useCallback((id: string) => {
    const controller = runningActionControllersRef.current.get(id);
    if (!controller) {
      return;
    }
    controller.abort();
  }, []);

  const updateConfirmationInput = useCallback((input: string) => {
    setSnapshot(current => ({
      ...current,
      pendingConfirmation: current.pendingConfirmation
        ? { ...current.pendingConfirmation, input }
        : null,
    }));
  }, []);

  const cancelConfirmation = useCallback(() => {
    setSnapshot(current => ({ ...current, pendingConfirmation: null }));
  }, []);

  const confirmPendingAction = useCallback(async () => {
    const pending = snapshotRef.current.pendingConfirmation;
    if (!pending) {
      return;
    }
    setSnapshot(current => ({ ...current, pendingConfirmation: null }));
    await executeAction(
      { ...pending.action, confirm: undefined },
      pending.context,
    );
  }, [executeAction]);

  const retryDataSource = useCallback((key: string) => {
    setSnapshot(current => {
      const nextErrors = new Map(current.dataSourceErrors);
      nextErrors.delete(key);
      return { ...current, dataSourceErrors: nextErrors };
    });
  }, []);

  const derived = useMemo(() => {
    const current = snapshot;
    const terminalEntries =
      current.terminalEntries.length > 0
        ? current.terminalEntries
        : [createMainTerminal(current.labels)];
    return {
      ...current,
      isRTL:
        current.labels?.layoutDirection === 'rtl' ||
        current.labels?.layoutDirection === 'rightToLeft',
      terminalIsRTL:
        current.manifest?.terminalTextDirection === 'rtl' ||
        current.manifest?.terminalTextDirection === 'rightToLeft',
      terminalEntries,
      activeTerminalID: terminalEntries.some(
        entry => entry.id === current.activeTerminalID,
      )
        ? current.activeTerminalID
        : terminalEntries[0]?.id ?? 'main',
    };
  }, [snapshot]);

  return {
    ...derived,
    reload: () => loadManifest(snapshotRef.current.localizationCode),
    updateActivePage,
    setFieldValue,
    setCheckedValues,
    setConfigValue,
    ensureDataSource,
    ensureFileState,
    ensureActionPrecheck,
    runAction,
    closeTerminal,
    cancelAction,
    selectTerminal: (id: string) =>
      setSnapshot(current => ({ ...current, activeTerminalID: id })),
    selectLocale,
    selectIconSet,
    selectColorTheme,
    selectWebUIFont,
    setConfigFilePath,
    loadConfig,
    saveConfig,
    choosePath,
    retryDataSource,
    reportError,
    runSetup,
    openBundleWorkspace,
    toggleSidebar: () =>
      setSnapshot(current => ({
        ...current,
        isSidebarVisible: !current.isSidebarVisible,
      })),
    toggleTerminal: () =>
      setSnapshot(current => ({
        ...current,
        isTerminalVisible: !current.isTerminalVisible,
      })),
    updateConfirmationInput,
    cancelConfirmation,
    confirmPendingAction,
  };
}
