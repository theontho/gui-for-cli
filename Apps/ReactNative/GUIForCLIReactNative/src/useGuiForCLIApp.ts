import {useCallback, useEffect, useMemo, useRef, useState} from 'react';
import {Alert} from 'react-native';
import {api} from './api';
import {
  actionPrecheckCacheKey,
  configSettingBindings,
  createMainTerminal,
  errorMessage,
  terminalExitStatus,
  terminalProcessErrorStatus,
} from './model';
import {
  commandContextFromState,
  configValueKey,
  displayCommand,
} from './webuiCore';

function createInitialSnapshot() {
  return {
    status: 'loading',
    error: '',
    manifest: null,
    labels: {},
    localizationCode: '',
    localizationOptions: [],
    bundleRootPath: '',
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
    terminalEntries: [] as any[],
    activeTerminalID: 'main',
  };
}

function randomID(prefix: string): string {
  return `${prefix}-${Date.now().toString(36)}-${Math.random()
    .toString(36)
    .slice(2, 8)}`;
}

export function useGuiForCLIApp() {
  const [snapshot, setSnapshot] = useState(createInitialSnapshot);
  const snapshotRef = useRef(snapshot);

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
    await api('/api/state/save', {method: 'POST', body: {state}});
  }, []);

  const loadManifest = useCallback(async (locale?: string) => {
    setSnapshot(current => ({...current, status: 'loading', error: ''}));
    try {
      const body = await api(
        locale ? `/api/manifest?locale=${encodeURIComponent(locale)}` : '/api/manifest',
      );
      const exitCodeReference = new Map<number, any>(
        (body.manifest?.exitCodeReference ?? []).map((entry: any) => [
          entry.code,
          entry,
        ]),
      );
      const activePageID =
        body.bundleState?.selectedPageID ?? body.manifest?.pages?.[0]?.id ?? '';
      setSnapshot(current => ({
        ...current,
        status: 'ready',
        error: '',
        manifest: body.manifest,
        labels: body.labels ?? {},
        localizationCode: body.localizationCode ?? '',
        localizationOptions: body.localizationOptions ?? [],
        bundleRootPath: body.bundleRootPath ?? '',
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
    void loadManifest();
  }, [loadManifest]);

  const updateActivePage = useCallback(
    async (pageID: string) => {
      setSnapshot(current => ({...current, activePageID: pageID}));
      await persistState({selectedPageID: pageID});
    },
    [persistState],
  );

  const setFieldValue = useCallback(
    async (control: any, value: string) => {
      const manifest = snapshotRef.current.manifest;
      const nextFieldValues = {
        ...(snapshotRef.current.fieldValues ?? {}),
        [control.id]: value,
      };
      const nextConfigValues = {...(snapshotRef.current.configValues ?? {})};
      for (const binding of configSettingBindings(manifest, control.id)) {
        nextConfigValues[configValueKey(binding.control, binding.setting)] = value;
        await api('/api/config/save', {
          method: 'POST',
          body: {
            control: binding.control,
            path: snapshotRef.current.configFilePaths?.[binding.control.id],
            values: Object.fromEntries(
              (binding.control.settings ?? []).map((setting: any) => [
                setting.key,
                setting.id === binding.setting.id
                  ? value
                  : nextConfigValues[configValueKey(binding.control, setting)] ??
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
    async (_control: any, selectedIDs: string[], controlID?: string) => {
      const targetID = controlID ?? _control.id;
      const nextCheckedOptions = {
        ...(snapshotRef.current.checkedOptions ?? {}),
        [targetID]: selectedIDs,
      };
      setSnapshot(current => ({...current, checkedOptions: nextCheckedOptions}));
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
      const nextConfigValues = {
        ...(snapshotRef.current.configValues ?? {}),
        [key]: value,
      };
      const nextFieldValues = {...(snapshotRef.current.fieldValues ?? {})};
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
          path: snapshotRef.current.configFilePaths?.[control.id],
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

  const ensureDataSource = useCallback(async (key: string, dataSource: any, context: any) => {
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
        body: {dataSource, context},
      });
      setSnapshot(state => {
        const nextPayloads = new Map(state.dataSourcePayloads);
        const nextLoading = new Set(state.loadingDataSources);
        const nextErrors = new Map(state.dataSourceErrors);
        nextPayloads.set(key, payload);
        nextLoading.delete(key);
        nextErrors.delete(key);
        return {
          ...state,
          dataSourcePayloads: nextPayloads,
          dataSourceErrors: nextErrors,
          loadingDataSources: nextLoading,
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
  }, []);

  const ensureFileState = useCallback(async (key: string, context: any) => {
    const current = snapshotRef.current;
    if (current.fileStateValues.has(key) || current.loadingFileStates.has(key)) {
      return;
    }
    setSnapshot(state => ({
      ...state,
      loadingFileStates: new Set([...state.loadingFileStates, key]),
    }));
    try {
      const result = await api('/api/file-state', {
        method: 'POST',
        body: {context},
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
    } catch (_error) {
      setSnapshot(state => {
        const nextLoading = new Set(state.loadingFileStates);
        nextLoading.delete(key);
        return {...state, loadingFileStates: nextLoading};
      });
    }
  }, []);

  const ensureActionPrecheck = useCallback(async (action: any, context: any) => {
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
        body: {precheck: action.precheck, context, labels: snapshotRef.current.labels},
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
  }, []);

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
      setSnapshot(state => ({
        ...state,
        terminalEntries: [...state.terminalEntries, runningEntry].slice(-40),
        activeTerminalID: id,
      }));
      try {
        const result = await api('/api/run', {
          method: 'POST',
          body: {action, context},
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
          body: [`$ ${result.command}`, result.stdout, result.stderr, `exit ${result.exitCode}`]
            .filter(Boolean)
            .join('\n'),
          status,
        });
        clearDerivedCaches();
      } catch (error) {
        replaceTerminalEntry(id, {
          id,
          kind: 'error',
          title: action.title,
          command,
          body: errorMessage(error),
          status: terminalProcessErrorStatus(
            snapshotRef.current.labels,
            command,
            errorMessage(error),
          ),
        });
      }
    },
    [clearDerivedCaches, replaceTerminalEntry],
  );

  const runAction = useCallback(
    async (action: any, context: any) => {
      if (action.confirm) {
        Alert.alert(
          action.confirm.title,
          action.confirm.message,
          [
            {
              text: action.confirm.cancelButtonTitle ?? 'Cancel',
              style: 'cancel',
            },
            {
              text: action.confirm.confirmButtonTitle ?? 'Continue',
              style: action.role === 'destructive' ? 'destructive' : 'default',
              onPress: () => {
                void executeAction(action, context);
              },
            },
          ],
          {cancelable: true},
        );
        return;
      }
      await executeAction(action, context);
    },
    [executeAction],
  );

  const selectLocale = useCallback(
    async (locale: string) => {
      await persistState({localizationCode: locale});
      await loadManifest(locale);
    },
    [loadManifest, persistState],
  );

  const closeTerminal = useCallback((id: string) => {
    if (id === 'main') {
      return;
    }
    setSnapshot(current => {
      const remaining = current.terminalEntries.filter(entry => entry.id !== id);
      return {
        ...current,
        terminalEntries: remaining,
        activeTerminalID: remaining[remaining.length - 1]?.id ?? 'main',
      };
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
      terminalEntries,
      activeTerminalID:
        terminalEntries.some(entry => entry.id === current.activeTerminalID)
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
    selectTerminal: (id: string) =>
      setSnapshot(current => ({...current, activeTerminalID: id})),
    selectLocale,
  };
}
