import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { api } from './api';
import { createInitialSnapshot, randomID } from './appState';
import { useAppConfigCallbacks } from './appConfigCallbacks';
import { useAppTerminalCallbacks } from './appTerminalCallbacks';
import {
  actionPrecheckCacheKey,
  createMainTerminal,
  errorMessage,
  normalizeColorTheme,
  normalizeIconSet,
  normalizeWebUIFont,
} from './model';

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

  const {
    choosePath,
    loadConfig,
    saveConfig,
    selectColorTheme,
    selectIconSet,
    selectLocale,
    selectWebUIFont,
    setCheckedValues,
    setConfigFilePath,
    setConfigValue,
    setFieldValue,
  } = useAppConfigCallbacks({
    appendTerminalEntry,
    clearDerivedCaches,
    loadManifest,
    persistState,
    setSnapshot,
    snapshotRef,
  });

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

  const {
    cancelAction,
    cancelConfirmation,
    closeTerminal,
    confirmPendingAction,
    openBundleWorkspace,
    runAction,
    runSetup,
    updateConfirmationInput,
  } = useAppTerminalCallbacks({
    appendTerminalEntry,
    clearDerivedCaches,
    persistState,
    replaceTerminalEntry,
    runningActionControllersRef,
    setSnapshot,
    snapshotRef,
  });

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
