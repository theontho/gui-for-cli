import React, {useEffect, useMemo} from 'react';
import {Pressable, Switch, Text, TextInput, View} from 'react-native';
import {
  actionPrecheckCacheKey,
  configDataSourceContext,
  fieldStateCacheKey,
  formatLabel,
  iconGlyph,
} from './model';
import {styles} from './styles';
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

function ChoiceRow({options, selected, onSelect, theme}: any) {
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
            ]}>
            <Text
              style={[
                styles.choiceChipLabel,
                {color: active ? theme.accent : theme.foreground},
              ]}>
              {optionTitle(option)}
            </Text>
          </Pressable>
        );
      })}
    </View>
  );
}

function CheckboxRow({options, selected, onToggle, theme}: any) {
  return (
    <View style={styles.choiceWrap}>
      {options.map((option: any) => {
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
            ]}>
            <Text
              style={[
                styles.choiceChipLabel,
                {color: active ? theme.accent : theme.foreground},
              ]}>
              {active ? '[x] ' : '[ ] '}
              {optionTitle(option)}
            </Text>
          </Pressable>
        );
      })}
    </View>
  );
}

export function ControlView({app, control, sectionContext, theme}: any) {
  const controlKey = `control:${control.id}`;

  useEffect(() => {
    if (control.dataSource) {
      app.ensureDataSource(
        controlKey,
        control.dataSource,
        commandContextFromState(app),
      ).catch(() => undefined);
    }
  }, [app, control, controlKey]);

  const renderedControl = useMemo(() => {
    const payload = app.dataSourcePayloads.get(controlKey);
    return payload ? applyDataSourcePayload(control, payload) : control;
  }, [app.dataSourcePayloads, control, controlKey]);

  if (renderedControl.kind === 'text' || renderedControl.kind === 'path') {
    return (
      <View style={styles.fieldWrap}>
        <Text style={[styles.fieldLabel, {color: theme.foreground}]}>
          {renderedControl.label}
        </Text>
        <TextInput
          onChangeText={value => {
            app.setFieldValue(renderedControl, value).catch(() => undefined);
          }}
          placeholder={renderedControl.placeholder}
          placeholderTextColor={theme.muted}
          style={[
            styles.textInput,
            {
              color: theme.foreground,
              backgroundColor: theme.panel,
              borderColor: theme.border,
            },
          ]}
          value={app.fieldValues?.[renderedControl.id] ?? renderedControl.value ?? ''}
        />
      </View>
    );
  }

  if (renderedControl.kind === 'dropdown') {
    const selected =
      app.fieldValues?.[renderedControl.id] ?? renderedControl.value ?? '';
    return (
      <View style={styles.fieldWrap}>
        <Text style={[styles.fieldLabel, {color: theme.foreground}]}>
          {renderedControl.label}
        </Text>
        <ChoiceRow
          onSelect={(next: string[]) => {
            app
              .setFieldValue(renderedControl, next[0] ?? '')
              .catch(() => undefined);
          }}
          options={renderedControl.options ?? []}
          selected={selected ? [selected] : []}
          theme={theme}
        />
      </View>
    );
  }

  if (renderedControl.kind === 'toggle') {
    const value =
      String(
        app.fieldValues?.[renderedControl.id] ?? renderedControl.value ?? 'false',
      ) === 'true';
    return (
      <View style={styles.toggleRow}>
        <Text style={[styles.fieldLabel, {color: theme.foreground}]}>
          {renderedControl.label}
        </Text>
        <Switch
          onValueChange={next => {
            app
              .setFieldValue(renderedControl, next ? 'true' : 'false')
              .catch(() => undefined);
          }}
          value={value}
        />
      </View>
    );
  }

  if (renderedControl.kind === 'checkboxGroup') {
    const selected = app.checkedOptions?.[renderedControl.id] ?? [];
    return (
      <View style={styles.fieldWrap}>
        <Text style={[styles.fieldLabel, {color: theme.foreground}]}>
          {renderedControl.label}
        </Text>
        <CheckboxRow
          onToggle={(id: string) => {
            const next = selected.includes(id)
              ? selected.filter((candidate: string) => candidate !== id)
              : [...selected, id];
            app.setCheckedValues(renderedControl, next).catch(() => undefined);
          }}
          options={renderedControl.options ?? []}
          selected={selected}
          theme={theme}
        />
      </View>
    );
  }

  if (renderedControl.kind === 'configEditor') {
    return (
      <View style={styles.fieldWrap}>
        <Text style={[styles.fieldLabel, {color: theme.foreground}]}>
          {renderedControl.label}
        </Text>
        {(renderedControl.settings ?? []).map((setting: any) => (
          <ConfigSettingField
            app={app}
            control={renderedControl}
            key={`${renderedControl.id}.${setting.id}`}
            setting={setting}
            theme={theme}
          />
        ))}
      </View>
    );
  }

  if (renderedControl.kind === 'libraryList') {
    const rows = hydrateRows(renderedControl);
    return (
      <View style={styles.fieldWrap}>
        <Text style={[styles.fieldLabel, {color: theme.foreground}]}>
          {renderedControl.label}
        </Text>
        {rows.length === 0 ? (
          <Text style={[styles.emptyText, {color: theme.muted}]}>
            {app.labels.libraryEmptyTitle ?? 'No library items are defined.'}
          </Text>
        ) : (
          rows.map((row: any) => (
            <View
              key={row.id}
              style={[
                styles.libraryRow,
                {backgroundColor: theme.panel, borderColor: theme.border},
              ]}>
              <Text style={[styles.libraryRowTitle, {color: theme.foreground}]}>
                {row.title ?? row.id}
              </Text>
              {(renderedControl.columns ?? []).map((column: any) => (
                <View key={column.id} style={styles.infoPair}>
                  <Text style={[styles.infoKey, {color: theme.muted}]}>
                    {column.title}
                  </Text>
                  <Text style={[styles.infoValue, {color: theme.foreground}]}>
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
      </View>
    );
  }

  return (
    <Text style={[styles.emptyText, {color: theme.muted}]}>
      Unsupported control kind: {renderedControl.kind}
    </Text>
  );
}

function ConfigSettingField({app, control, setting, theme}: any) {
  const key = `${control.id}.${setting.id}`;
  const sourceKey = `setting:${key}`;
  const context = configDataSourceContext(app, control);

  useEffect(() => {
    if (setting.dataSource) {
      app.ensureDataSource(sourceKey, setting.dataSource, context).catch(
        () => undefined,
      );
    }
  }, [app, context, setting, sourceKey]);

  const options =
    app.dataSourcePayloads.get(sourceKey)?.options ?? setting.options ?? [];
  const value = app.configValues?.[configValueKey(control, setting)] ?? setting.value ?? '';

  if (setting.kind === 'dropdown') {
    return (
      <View style={styles.fieldWrap}>
        <Text style={[styles.fieldLabel, {color: theme.foreground}]}>
          {setting.label}
        </Text>
        <ChoiceRow
          onSelect={(next: string[]) => {
            app
              .setConfigValue(control, setting, next[0] ?? '')
              .catch(() => undefined);
          }}
          options={options}
          selected={value ? [value] : []}
          theme={theme}
        />
      </View>
    );
  }

  if (setting.kind === 'toggle') {
    return (
      <View style={styles.toggleRow}>
        <Text style={[styles.fieldLabel, {color: theme.foreground}]}>
          {setting.label}
        </Text>
        <Switch
          onValueChange={next => {
            app
              .setConfigValue(control, setting, next ? 'true' : 'false')
              .catch(() => undefined);
          }}
          value={String(value) === 'true'}
        />
      </View>
    );
  }

  return (
    <View style={styles.fieldWrap}>
      <Text style={[styles.fieldLabel, {color: theme.foreground}]}>
        {setting.label}
      </Text>
      <TextInput
        onChangeText={next => {
          app.setConfigValue(control, setting, next).catch(() => undefined);
        }}
        placeholder={setting.placeholder}
        placeholderTextColor={theme.muted}
        style={[
          styles.textInput,
          {
            color: theme.foreground,
            backgroundColor: theme.panel,
            borderColor: theme.border,
          },
        ]}
        value={value}
      />
    </View>
  );
}

export function ActionList({app, actions, context, compact, theme}: any) {
  const fileStateKey = fieldStateCacheKey(context);

  useEffect(() => {
    app.ensureFileState(fileStateKey, context).catch(() => undefined);
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
      if (action.precheck && isPrecheckReady(action.precheck, resolvedContext)) {
        app.ensureActionPrecheck(action, resolvedContext).catch(() => undefined);
      }
    });
  }, [actions, app, resolvedContext]);

  return (
    <View style={styles.actionRow}>
      {actions
        .filter((action: any) => isActionVisible(action, resolvedContext))
        .map((action: any) => {
          const missing = missingPlaceholders(action.command, resolvedContext);
          const unavailable = disabledReason(
            action,
            resolvedContext,
            app.labels.actionUnavailableTitle,
          );
          const precheckKey = actionPrecheckCacheKey(action, resolvedContext);
          const precheck = app.actionPrechecks.get(precheckKey);
          const disabled = missing.length > 0 || Boolean(unavailable);
          return (
            <Pressable
              accessibilityHint={
                precheck?.message ??
                unavailable ??
                (missing.length > 0
                  ? formatLabel(app.labels.actionMissingInputsFormat, {
                      inputs: missing.join(', '),
                    })
                  : undefined)
              }
              accessibilityRole="button"
              disabled={disabled}
              key={action.id}
              onPress={() => {
                app.runAction(action, resolvedContext).catch(() => undefined);
              }}
              style={[
                styles.actionButton,
                disabled ? styles.actionButtonDisabled : null,
                {
                  backgroundColor: disabled ? theme.panel : theme.accentSoft,
                  borderColor: disabled ? theme.border : theme.accent,
                },
              ]}>
              <Text
                style={[
                  styles.actionButtonLabel,
                  {color: disabled ? theme.muted : theme.accent},
                ]}>
                {compact ? iconGlyph(action.iconName, action.iconEmoji, '') : ''}
                {compact ? ' ' : ''}
                {action.title}
              </Text>
              {precheck?.message ? (
                <Text style={[styles.actionHint, {color: theme.warning}]}>
                  {precheck.message}
                </Text>
              ) : null}
            </Pressable>
          );
        })}
    </View>
  );
}
