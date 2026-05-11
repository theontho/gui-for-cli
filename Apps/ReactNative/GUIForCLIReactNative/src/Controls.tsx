import React, { useEffect, useMemo } from 'react';
import { Pressable, Switch, Text, TextInput, View } from 'react-native';
import { ActionList } from './ActionList';
import { ConfigSettingField } from './ConfigSettingField';
import {
  CheckboxRow,
  ChoiceRow,
  ControlStatus,
  HelpText,
  helpTextFor,
  reportControlError,
} from './ControlSupport';
import { styles } from './styles';
import {
  applyDataSourcePayload,
  commandContextFromState,
  hydrateRows,
  optionTitle,
  rowContext,
} from './webuiCore';

export { ActionList } from './ActionList';

export function ControlView({ app, control, sectionContext, theme }: any) {
  const controlKey = `control:${control.id}`;

  useEffect(() => {
    if (control.dataSource) {
      app
        .ensureDataSource(
          controlKey,
          control.dataSource,
          commandContextFromState(app),
        )
        .catch((error: unknown) => reportControlError(app, control, error));
    }
  }, [app, control, controlKey]);

  const renderedControl = useMemo(() => {
    const payload = app.dataSourcePayloads.get(controlKey);
    return payload ? applyDataSourcePayload(control, payload) : control;
  }, [app.dataSourcePayloads, control, controlKey]);
  const loading = app.loadingDataSources.has(controlKey);
  const error = app.dataSourceErrors.get(controlKey);

  if (renderedControl.kind === 'text' || renderedControl.kind === 'path') {
    const value =
      app.fieldValues?.[renderedControl.id] ?? renderedControl.value ?? '';
    return (
      <View style={styles.fieldWrap}>
        <Text style={[styles.fieldLabel, { color: theme.foreground }]}>
          {renderedControl.label}
        </Text>
        <HelpText text={helpTextFor(renderedControl)} theme={theme} />
        <View style={styles.inputButtonRow}>
          <TextInput
            onChangeText={next => {
              app
                .setFieldValue(renderedControl, next)
                .catch((error: unknown) =>
                  reportControlError(app, renderedControl, error),
                );
            }}
            placeholder={renderedControl.placeholder}
            placeholderTextColor={theme.muted}
            style={[
              styles.textInput,
              renderedControl.kind === 'path' ? styles.flexInput : null,
              {
                color: theme.foreground,
                backgroundColor: theme.panel,
                borderColor: theme.border,
              },
            ]}
            value={value}
          />
          {renderedControl.kind === 'path' ? (
            <Pressable
              accessibilityRole="button"
              onPress={() => {
                app
                  .choosePath(renderedControl, value, (path: string) =>
                    app.setFieldValue(renderedControl, path),
                  )
                  .catch((error: unknown) =>
                    reportControlError(app, renderedControl, error),
                  );
              }}
              style={[styles.smallButton, { borderColor: theme.border }]}
            >
              <Text style={[styles.actionHint, { color: theme.accent }]}>
                {app.labels.chooseButtonTitle ?? 'Choose'}
              </Text>
            </Pressable>
          ) : null}
        </View>
        <ControlStatus
          app={app}
          error={error}
          loading={loading}
          retryKey={controlKey}
          theme={theme}
        />
      </View>
    );
  }

  if (renderedControl.kind === 'dropdown') {
    const selected =
      app.fieldValues?.[renderedControl.id] ?? renderedControl.value ?? '';
    return (
      <View style={styles.fieldWrap}>
        <Text style={[styles.fieldLabel, { color: theme.foreground }]}>
          {renderedControl.label}
        </Text>
        <HelpText text={helpTextFor(renderedControl)} theme={theme} />
        <ChoiceRow
          labels={app.labels}
          onSelect={(next: string[]) => {
            app
              .setFieldValue(renderedControl, next[0] ?? '')
              .catch((error: unknown) =>
                reportControlError(app, renderedControl, error),
              );
          }}
          options={renderedControl.options ?? []}
          selected={selected ? [selected] : []}
          theme={theme}
        />
        <ControlStatus
          app={app}
          error={error}
          loading={loading}
          retryKey={controlKey}
          theme={theme}
        />
      </View>
    );
  }

  if (renderedControl.kind === 'toggle') {
    const value =
      String(
        app.fieldValues?.[renderedControl.id] ??
          renderedControl.value ??
          'false',
      ) === 'true';
    return (
      <View style={styles.fieldWrap}>
        <View style={styles.toggleRow}>
          <Text style={[styles.fieldLabel, { color: theme.foreground }]}>
            {renderedControl.label}
          </Text>
          <Switch
            onValueChange={next => {
              app
                .setFieldValue(renderedControl, next ? 'true' : 'false')
                .catch((error: unknown) =>
                  reportControlError(app, renderedControl, error),
                );
            }}
            value={value}
          />
        </View>
        <HelpText text={helpTextFor(renderedControl)} theme={theme} />
        <ControlStatus
          app={app}
          error={error}
          loading={loading}
          retryKey={controlKey}
          theme={theme}
        />
      </View>
    );
  }

  if (renderedControl.kind === 'checkboxGroup') {
    const selected = app.checkedOptions?.[renderedControl.id] ?? [];
    return (
      <View style={styles.fieldWrap}>
        <Text style={[styles.fieldLabel, { color: theme.foreground }]}>
          {renderedControl.label}
        </Text>
        <HelpText text={helpTextFor(renderedControl)} theme={theme} />
        <CheckboxRow
          labels={app.labels}
          onToggle={(id: string) => {
            const next = selected.includes(id)
              ? selected.filter((candidate: string) => candidate !== id)
              : [...selected, id];
            app
              .setCheckedValues(renderedControl, next)
              .catch((error: unknown) =>
                reportControlError(app, renderedControl, error),
              );
          }}
          options={renderedControl.options ?? []}
          selected={selected}
          theme={theme}
        />
        <ControlStatus
          app={app}
          error={error}
          loading={loading}
          retryKey={controlKey}
          theme={theme}
        />
      </View>
    );
  }

  if (renderedControl.kind === 'infoGrid') {
    return (
      <View style={styles.fieldWrap}>
        <Text style={[styles.fieldLabel, { color: theme.foreground }]}>
          {renderedControl.label}
        </Text>
        <HelpText text={helpTextFor(renderedControl)} theme={theme} />
        <View style={styles.infoGrid}>
          {(renderedControl.options ?? []).map((option: any) => (
            <View
              key={option.id}
              style={[
                styles.infoGridCell,
                {
                  backgroundColor: theme.background,
                  borderColor: theme.border,
                },
              ]}
            >
              <Text style={[styles.infoValue, { color: theme.foreground }]}>
                {optionTitle(option, app.labels)}
              </Text>
            </View>
          ))}
        </View>
        <ControlStatus
          app={app}
          error={error}
          loading={loading}
          retryKey={controlKey}
          theme={theme}
        />
      </View>
    );
  }

  if (renderedControl.kind === 'configEditor') {
    return (
      <View style={styles.fieldWrap}>
        <Text style={[styles.fieldLabel, { color: theme.foreground }]}>
          {renderedControl.label}
        </Text>
        <HelpText text={helpTextFor(renderedControl)} theme={theme} />
        {renderedControl.configFile ? (
          <View style={styles.fieldWrap}>
            <Text style={[styles.actionHint, { color: theme.muted }]}>
              {app.labels.settingsFileLabel ?? 'Settings file'}
            </Text>
            <View style={styles.inputButtonRow}>
              <TextInput
                onChangeText={(next: string) => {
                  app
                    .setConfigFilePath(renderedControl, next)
                    .catch((error: unknown) =>
                      reportControlError(app, renderedControl, error),
                    );
                }}
                placeholder={renderedControl.configFile.path}
                placeholderTextColor={theme.muted}
                style={[
                  styles.textInput,
                  styles.flexInput,
                  {
                    color: theme.foreground,
                    backgroundColor: theme.panel,
                    borderColor: theme.border,
                  },
                ]}
                value={
                  app.configFilePaths?.[renderedControl.id] ??
                  renderedControl.configFile.path
                }
              />
              <Pressable
                accessibilityRole="button"
                onPress={() => {
                  const current =
                    app.configFilePaths?.[renderedControl.id] ??
                    renderedControl.configFile.path;
                  app
                    .choosePath(
                      {
                        ...renderedControl.configFile,
                        kind: 'path',
                        label: app.labels.settingsFileLabel ?? 'Settings file',
                        pathType: 'file',
                      },
                      current,
                      (path: string) =>
                        app.setConfigFilePath(renderedControl, path),
                    )
                    .catch((error: unknown) =>
                      reportControlError(app, renderedControl, error),
                    );
                }}
                style={[styles.smallButton, { borderColor: theme.border }]}
              >
                <Text style={[styles.actionHint, { color: theme.accent }]}>
                  {app.labels.chooseButtonTitle ?? 'Choose'}
                </Text>
              </Pressable>
              <Pressable
                accessibilityRole="button"
                onPress={() => {
                  app
                    .loadConfig(renderedControl)
                    .catch((error: unknown) =>
                      reportControlError(app, renderedControl, error),
                    );
                }}
                style={[styles.smallButton, { borderColor: theme.border }]}
              >
                <Text style={[styles.actionHint, { color: theme.accent }]}>
                  {app.labels.loadButtonTitle ?? 'Load'}
                </Text>
              </Pressable>
              <Pressable
                accessibilityRole="button"
                onPress={() => {
                  app
                    .saveConfig(renderedControl)
                    .catch((error: unknown) =>
                      reportControlError(app, renderedControl, error),
                    );
                }}
                style={[styles.smallButton, { borderColor: theme.border }]}
              >
                <Text style={[styles.actionHint, { color: theme.accent }]}>
                  {app.labels.saveButtonTitle ?? 'Save'}
                </Text>
              </Pressable>
            </View>
          </View>
        ) : null}
        {(renderedControl.settings ?? []).map((setting: any) => (
          <ConfigSettingField
            app={app}
            control={renderedControl}
            key={`${renderedControl.id}.${setting.id}`}
            setting={setting}
            theme={theme}
          />
        ))}
        <ControlStatus
          app={app}
          error={error}
          loading={loading}
          retryKey={controlKey}
          theme={theme}
        />
      </View>
    );
  }

  if (renderedControl.kind === 'libraryList') {
    const rows = hydrateRows(renderedControl);
    return (
      <View style={styles.fieldWrap}>
        <Text style={[styles.fieldLabel, { color: theme.foreground }]}>
          {renderedControl.label}
        </Text>
        <HelpText text={helpTextFor(renderedControl)} theme={theme} />
        {loading && !app.dataSourcePayloads.has(controlKey) ? (
          <ControlStatus
            app={app}
            error={error}
            loading={loading}
            retryKey={controlKey}
            theme={theme}
          />
        ) : rows.length === 0 ? (
          <Text style={[styles.emptyText, { color: theme.muted }]}>
            {app.labels.libraryEmptyTitle ?? 'No library items are defined.'}
          </Text>
        ) : (
          rows.map((row: any) => (
            <View
              key={row.id}
              style={[
                styles.libraryRow,
                { backgroundColor: theme.panel, borderColor: theme.border },
              ]}
            >
              <Text
                style={[styles.libraryRowTitle, { color: theme.foreground }]}
              >
                {row.title ?? row.id}
              </Text>
              <View style={styles.pillRow}>
                {row.status ? (
                  <Text
                    style={[
                      styles.pill,
                      {
                        color: theme.foreground,
                        backgroundColor: theme.accentSoft,
                        borderColor: theme.border,
                      },
                    ]}
                  >
                    {app.labels.libraryStatusLabels?.[
                      String(row.status).toLowerCase()
                    ] ?? row.status}
                  </Text>
                ) : null}
                {(row.tags ?? []).map((tag: any) => (
                  <Text
                    key={`${tag.id ?? ''}-${tag.title}`}
                    style={[
                      styles.pill,
                      {
                        color: theme.foreground,
                        backgroundColor: theme.background,
                        borderColor: theme.border,
                      },
                    ]}
                  >
                    {app.labels.libraryTagLabels?.[tag.id] ??
                      app.labels.libraryTagLabels?.[
                        String(tag.title).toLowerCase()
                      ] ??
                      tag.title}
                  </Text>
                ))}
              </View>
              {(renderedControl.columns ?? []).map((column: any) => (
                <View key={column.id} style={styles.infoPair}>
                  <Text style={[styles.infoKey, { color: theme.muted }]}>
                    {column.title}
                  </Text>
                  <Text style={[styles.infoValue, { color: theme.foreground }]}>
                    {row.values?.[column.id] ?? '—'}
                  </Text>
                </View>
              ))}
              {(renderedControl.rowActions ?? []).length ? (
                <ActionList
                  actions={renderedControl.rowActions}
                  app={app}
                  compact
                  context={rowContext(sectionContext, row)}
                  theme={theme}
                />
              ) : null}
            </View>
          ))
        )}
        <ControlStatus
          app={app}
          error={!loading ? error : undefined}
          loading={false}
          retryKey={controlKey}
          theme={theme}
        />
      </View>
    );
  }

  return (
    <Text style={[styles.emptyText, { color: theme.muted }]}>
      Unsupported control kind: {renderedControl.kind}
    </Text>
  );
}
