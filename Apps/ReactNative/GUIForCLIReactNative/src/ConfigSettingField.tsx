import React, { useEffect } from 'react';
import { Pressable, Switch, Text, TextInput, View } from 'react-native';
import { configDataSourceContext } from './model';
import { styles } from './styles';
import { configValueKey } from './webuiCore';
import {
  ChoiceRow,
  ControlStatus,
  HelpText,
  helpTextFor,
  reportControlError,
} from './ControlSupport';

export function ConfigSettingField({ app, control, setting, theme }: any) {
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
