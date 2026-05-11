import React, { useEffect, useMemo } from 'react';
import {
  ActivityIndicator,
  Pressable,
  Switch,
  Text,
  TextInput,
  View,
} from 'react-native';
import {
  actionPrecheckCacheKey,
  configDataSourceContext,
  fieldStateCacheKey,
  formatLabel,
  iconGlyph,
} from './model';
import { styles } from './styles';
import {
  applyDataSourcePayload,
  commandContextFromState,
  configValueKey,
  disabledReason,
  hydrateRows,
  isActionVisible,
  isPrecheckReady,
  missingPlaceholders,
  optionTitle,
  rowContext,
} from './webuiCore';

function HelpText({ text, theme }: any) {
  return text ? (
    <Text style={[styles.helpText, { color: theme.muted }]}>{text}</Text>
  ) : null;
}

function groupedOptions(options: any[]) {
  const groups: Array<{ title: string; options: any[] }> = [];
  for (const option of options) {
    const title = option.group ?? '';
    let group = groups.find(candidate => candidate.title === title);
    if (!group) {
      group = { title, options: [] };
      groups.push(group);
    }
    group.options.push(option);
  }
  return groups;
}

function ChoiceRow({ labels, options, selected, onSelect, theme }: any) {
  return (
    <View style={styles.choiceWrap}>
      {options.map((option: any) => {
        const active = selected.includes(option.id);
        return (
          <Pressable
            key={option.id}
            onPress={() => onSelect([option.id])}
            style={[
              styles.choiceChip,
              {
                backgroundColor: active ? theme.accentSoft : theme.panel,
                borderColor: active ? theme.accent : theme.border,
              },
            ]}
          >
            <Text
              style={[
                styles.choiceChipLabel,
                { color: active ? theme.accent : theme.foreground },
              ]}
            >
              {optionTitle(option, labels)}
            </Text>
          </Pressable>
        );
      })}
    </View>
  );
}

function CheckboxRow({ labels, options, selected, onToggle, theme }: any) {
  return (
    <View style={styles.optionGroups}>
      {groupedOptions(options).map(group => (
        <View key={group.title || 'default'} style={styles.optionGroup}>
          {group.title ? (
            <Text style={[styles.optionGroupTitle, { color: theme.muted }]}>
              {group.title}
            </Text>
          ) : null}
          <View style={styles.choiceWrap}>
            {group.options.map((option: any) => {
              const active = selected.includes(option.id);
              return (
                <Pressable
                  key={option.id}
                  onPress={() => onToggle(option.id)}
                  style={[
                    styles.choiceChip,
                    {
                      backgroundColor: active ? theme.accentSoft : theme.panel,
                      borderColor: active ? theme.accent : theme.border,
                    },
                  ]}
                >
                  <Text
                    style={[
                      styles.choiceChipLabel,
                      { color: active ? theme.accent : theme.foreground },
                    ]}
                  >
                    {active ? '[x] ' : '[ ] '}
                    {optionTitle(option, labels)}
                  </Text>
                </Pressable>
              );
            })}
          </View>
        </View>
      ))}
    </View>
  );
}

function ControlStatus({ app, error, loading, retryKey, theme }: any) {
  if (!loading && !error) {
    return null;
  }
  return (
    <View style={styles.statusStack}>
      {loading ? (
        <View style={styles.inlineStatus}>
          <ActivityIndicator color={theme.accent} size="small" />
          <Text style={[styles.actionHint, { color: theme.muted }]}>
            {app.labels.loadingTitle ?? 'Loading...'}
          </Text>
        </View>
      ) : null}
      {error ? (
        <View style={styles.inlineStatus}>
          <Text style={[styles.actionHint, { color: theme.danger }]}>
            ⚠ {error}
          </Text>
          <Pressable
            accessibilityRole="button"
            onPress={() => app.retryDataSource(retryKey)}
            style={[styles.smallButton, { borderColor: theme.border }]}
          >
            <Text style={[styles.actionHint, { color: theme.accent }]}>
              {app.labels.retryButtonTitle ?? 'Retry'}
            </Text>
          </Pressable>
        </View>
      ) : null}
    </View>
  );
}

function reportControlError(app: any, control: any, error: unknown) {
  app.reportError(
    error,
    control?.label ?? control?.title ?? control?.id ?? 'Control',
  );
}

function actionPlaceholderLabel(app: any, placeholder: string) {
  const normalized = String(placeholder ?? '').replace(/^(config|row)\./, '');
  const fileStateSeparator = normalized.lastIndexOf('.');
  const key =
    fileStateSeparator > 0 &&
    ['fileSize', 'fileSizeGB', 'pathExtension'].includes(
      normalized.slice(fileStateSeparator + 1),
    )
      ? normalized.slice(0, fileStateSeparator)
      : normalized;
  for (const page of app.manifest?.pages ?? []) {
    for (const section of page.sections ?? []) {
      for (const control of section.controls ?? []) {
        if (control.id === key) {
          return control.label ?? placeholder;
        }
        for (const setting of control.settings ?? []) {
          if (
            setting.id === key ||
            setting.key === key ||
            `${control.id}.${setting.id}` === key ||
            `${control.id}.${setting.key}` === key
          ) {
            return setting.label ?? placeholder;
          }
        }
      }
    }
  }
  return placeholder;
}

function actionColors(action: any, disabled: boolean, theme: any) {
  if (disabled) {
    return {
      backgroundColor: theme.panel,
      borderColor: theme.border,
      color: theme.muted,
    };
  }
  if (action.role === 'destructive') {
    return {
      backgroundColor: theme.panel,
      borderColor: theme.danger,
      color: theme.danger,
    };
  }
  if (action.role === 'secondary') {
    return {
      backgroundColor: theme.panel,
      borderColor: theme.border,
      color: theme.foreground,
    };
  }
  return {
    backgroundColor: theme.accentSoft,
    borderColor: theme.accent,
    color: theme.accent,
  };
}

function helpTextFor(item: any) {
  return item?.tooltip ?? item?.help ?? item?.description ?? item?.subtitle;
}

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

function ConfigSettingField({ app, control, setting, theme }: any) {
  const key = `${control.id}.${setting.id}`;
  const sourceKey = `setting:${key}`;
  const context = configDataSourceContext(app, control);

  useEffect(() => {
    if (setting.dataSource) {
      app
        .ensureDataSource(sourceKey, setting.dataSource, context)
        .catch((error: unknown) => reportControlError(app, setting, error));
    }
  }, [app, context, setting, sourceKey]);

  const options =
    app.dataSourcePayloads.get(sourceKey)?.options ?? setting.options ?? [];
  const value =
    app.configValues?.[configValueKey(control, setting)] ?? setting.value ?? '';
  const loading = app.loadingDataSources.has(sourceKey);
  const error = app.dataSourceErrors.get(sourceKey);

  if (setting.kind === 'dropdown') {
    return (
      <View style={styles.fieldWrap}>
        <Text style={[styles.fieldLabel, { color: theme.foreground }]}>
          {setting.label}
        </Text>
        <HelpText text={helpTextFor(setting)} theme={theme} />
        <ChoiceRow
          labels={app.labels}
          onSelect={(next: string[]) => {
            app
              .setConfigValue(control, setting, next[0] ?? '')
              .catch((error: unknown) =>
                reportControlError(app, setting, error),
              );
          }}
          options={options}
          selected={value ? [value] : []}
          theme={theme}
        />
        <ControlStatus
          app={app}
          error={error}
          loading={loading}
          retryKey={sourceKey}
          theme={theme}
        />
      </View>
    );
  }

  if (setting.kind === 'toggle') {
    return (
      <View style={styles.fieldWrap}>
        <View style={styles.toggleRow}>
          <Text style={[styles.fieldLabel, { color: theme.foreground }]}>
            {setting.label}
          </Text>
          <Switch
            onValueChange={next => {
              app
                .setConfigValue(control, setting, next ? 'true' : 'false')
                .catch((error: unknown) =>
                  reportControlError(app, setting, error),
                );
            }}
            value={String(value) === 'true'}
          />
        </View>
        <HelpText text={helpTextFor(setting)} theme={theme} />
        <ControlStatus
          app={app}
          error={error}
          loading={loading}
          retryKey={sourceKey}
          theme={theme}
        />
      </View>
    );
  }

  return (
    <View style={styles.fieldWrap}>
      <Text style={[styles.fieldLabel, { color: theme.foreground }]}>
        {setting.label}
      </Text>
      <HelpText text={helpTextFor(setting)} theme={theme} />
      <View style={styles.inputButtonRow}>
        <TextInput
          onChangeText={next => {
            app
              .setConfigValue(control, setting, next)
              .catch((error: unknown) =>
                reportControlError(app, setting, error),
              );
          }}
          placeholder={setting.placeholder}
          placeholderTextColor={theme.muted}
          style={[
            styles.textInput,
            setting.kind === 'path' ? styles.flexInput : null,
            {
              color: theme.foreground,
              backgroundColor: theme.panel,
              borderColor: theme.border,
            },
          ]}
          value={value}
        />
        {setting.kind === 'path' ? (
          <Pressable
            accessibilityRole="button"
            onPress={() => {
              app
                .choosePath(setting, value, (path: string) =>
                  app.setConfigValue(control, setting, path),
                )
                .catch((error: unknown) =>
                  reportControlError(app, setting, error),
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
        retryKey={sourceKey}
        theme={theme}
      />
    </View>
  );
}

export function ActionList({ app, actions, context, compact, theme }: any) {
  const fileStateKey = fieldStateCacheKey(context);

  useEffect(() => {
    app.ensureFileState(fileStateKey, context).catch((error: unknown) => {
      app.reportError(error, app.labels.fileStateWarningTitle ?? 'File state');
    });
  }, [app, context, fileStateKey]);

  const resolvedContext = useMemo(
    () => ({
      ...context,
      fileStateValues: app.fileStateValues.get(fileStateKey) ?? {},
    }),
    [app.fileStateValues, context, fileStateKey],
  );

  useEffect(() => {
    actions.forEach((action: any) => {
      if (
        action.precheck &&
        isPrecheckReady(action.precheck, resolvedContext)
      ) {
        app
          .ensureActionPrecheck(action, resolvedContext)
          .catch((error: unknown) => reportControlError(app, action, error));
      }
    });
  }, [actions, app, resolvedContext]);

  return (
    <View style={styles.actionRow}>
      {actions
        .filter((action: any) => isActionVisible(action, resolvedContext))
        .map((action: any) => {
          const missing = missingPlaceholders(action.command, resolvedContext);
          const missingLabels = missing.map((placeholder: string) =>
            actionPlaceholderLabel(app, placeholder),
          );
          const unavailable = disabledReason(
            action,
            resolvedContext,
            app.labels.actionUnavailableTitle,
          );
          const precheckKey = actionPrecheckCacheKey(action, resolvedContext);
          const precheck = app.actionPrechecks.get(precheckKey);
          const precheckError = app.actionPrecheckErrors.get(precheckKey);
          const loadingPrecheck = app.loadingActionPrechecks.has(precheckKey);
          const precheckWarning =
            precheck?.severity === 'warning' ? precheck.message : undefined;
          const disabled =
            missing.length > 0 ||
            Boolean(unavailable) ||
            Boolean(precheckWarning) ||
            loadingPrecheck;
          const colors = actionColors(action, disabled, theme);
          const icon = iconGlyph(action.iconName, action.iconEmoji, '');
          const title = action.iconOnly && icon ? '' : action.title;
          return (
            <Pressable
              accessibilityLabel={action.title}
              accessibilityHint={
                precheck?.message ??
                precheckError ??
                unavailable ??
                (missing.length > 0
                  ? formatLabel(app.labels.actionMissingInputsFormat, {
                      inputs: missingLabels.join(', '),
                    })
                  : undefined)
              }
              accessibilityRole="button"
              disabled={disabled}
              key={action.id}
              onPress={() => {
                app
                  .runAction(action, resolvedContext)
                  .catch((error: unknown) =>
                    reportControlError(app, action, error),
                  );
              }}
              style={[
                styles.actionButton,
                compact || action.iconOnly ? styles.actionButtonCompact : null,
                disabled ? styles.actionButtonDisabled : null,
                {
                  backgroundColor: colors.backgroundColor,
                  borderColor: colors.borderColor,
                },
              ]}
            >
              <Text style={[styles.actionButtonLabel, { color: colors.color }]}>
                {compact || action.iconOnly ? icon : ''}
                {compact && !action.iconOnly && icon ? ' ' : ''}
                {title}
              </Text>
              <HelpText text={helpTextFor(action)} theme={theme} />
              {loadingPrecheck ? (
                <Text style={[styles.actionHint, { color: theme.muted }]}>
                  {app.labels.refreshingTitle ?? 'Refreshing...'}
                </Text>
              ) : null}
              {precheckError ? (
                <Text style={[styles.actionHint, { color: theme.danger }]}>
                  {precheckError}
                </Text>
              ) : null}
              {precheck?.message ? (
                <Text style={[styles.actionHint, { color: theme.warning }]}>
                  {precheck.message}
                </Text>
              ) : null}
            </Pressable>
          );
        })}
    </View>
  );
}
