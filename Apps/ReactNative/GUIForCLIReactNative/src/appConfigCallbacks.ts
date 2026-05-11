import { useCallback } from 'react';
import { api } from './api';
import { formatConfigMessage } from './appState';
import {
  configSettingBindings,
  errorMessage,
  pathPickerKind,
  pathPickerTitle,
} from './model';
import { configValueKey } from './webuiCore';

export function useAppConfigCallbacks({
  appendTerminalEntry,
  clearDerivedCaches,
  loadManifest,
  persistState,
  setSnapshot,
  snapshotRef,
}: any) {
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
      setSnapshot((current: any) => ({
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
    [clearDerivedCaches, persistState, setSnapshot, snapshotRef],
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
      setSnapshot((current: any) => ({
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
    [clearDerivedCaches, persistState, setSnapshot, snapshotRef],
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
      setSnapshot((current: any) => ({
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
    [clearDerivedCaches, persistState, setSnapshot, snapshotRef],
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
      setSnapshot((current: any) => ({ ...current, iconSet }));
      await persistState({ iconSet });
    },
    [persistState, setSnapshot],
  );

  const selectColorTheme = useCallback(
    async (colorTheme: 'system' | 'light' | 'dark') => {
      setSnapshot((current: any) => ({ ...current, colorTheme }));
      await persistState({ colorTheme });
    },
    [persistState, setSnapshot],
  );

  const selectWebUIFont = useCallback(
    async (webUIFont: 'system' | 'sfPro') => {
      setSnapshot((current: any) => ({ ...current, webUIFont }));
      await persistState({ webUIFont });
    },
    [persistState, setSnapshot],
  );

  const setConfigFilePath = useCallback(
    async (control: any, path: string) => {
      const nextConfigFilePaths = {
        ...(snapshotRef.current.configFilePaths ?? {}),
        [control.id]: path,
      };
      setSnapshot((current: any) => ({
        ...current,
        configFilePaths: nextConfigFilePaths,
      }));
      await persistState({ configFilePaths: nextConfigFilePaths });
    },
    [persistState, setSnapshot, snapshotRef],
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
        setSnapshot((current: any) => ({
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
    [
      appendTerminalEntry,
      clearDerivedCaches,
      persistState,
      setSnapshot,
      snapshotRef,
    ],
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
        setSnapshot((current: any) => ({
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
    [appendTerminalEntry, persistState, setSnapshot, snapshotRef],
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
    [appendTerminalEntry, snapshotRef],
  );

  return {
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
  };
}
