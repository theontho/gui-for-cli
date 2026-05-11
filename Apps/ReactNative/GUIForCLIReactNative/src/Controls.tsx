import React, {useEffect, useMemo} from 'react';
import {Pressable, Switch, Text, TextInput, View} from 'react-native';
import {
  actionPrecheckCacheKey,
  configDataSourceContext,
  fieldStateCacheKey,
  formatLabel,
  iconGlyph,
} from './model';
import {palette, styles} from './styles';
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
      void app.ensureDataSource(
        controlKey,
        control.dataSource,
        commandContextFromState(app),
      );
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
            void app.setFieldValue(renderedControl, value);
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
            void app.setFieldValue(renderedControl, next[0] ?? '');
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
            void app.setFieldValue(renderedControl, next ? 'true' : 'false');
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
            void app.setCheckedValues(renderedControl, next);
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
      void app.ensureDataSource(sourceKey, setting.dataSource, context);
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
            void app.setConfigValue(control, setting, next[0] ?? '');
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
            void app.setConfigValue(control, setting, next ? 'true' : 'false');
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
          void app.setConfigValue(control, setting, next);
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
    void app.ensureFileState(fileStateKey, context);
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
        void app.ensureActionPrecheck(action, resolvedContext);
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
                void app.runAction(action, resolvedContext);
              }}
              style={[
                styles.actionButton,
                {
                  backgroundColor: disabled ? theme.panel : theme.accentSoft,
                  borderColor: disabled ? theme.border : theme.accent,
                  opacity: disabled ? 0.6 : 1,
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
