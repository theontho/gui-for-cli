import React from 'react';
import { ActivityIndicator, Pressable, Text, View } from 'react-native';
import { styles } from './styles';
import { optionTitle } from './webuiCore';

export function HelpText({ text, theme }: any) {
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

export function ChoiceRow({ labels, options, selected, onSelect, theme }: any) {
  return (
    <View style={styles.choiceWrap}>
      {options.map((option: any) => {
        const active = selected.includes(option.id);
        return (
          <Pressable
            accessibilityLabel={optionTitle(option, labels)}
            accessibilityRole="button"
            accessibilityState={{ selected: active }}
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

export function CheckboxRow({
  labels,
  options,
  selected,
  onToggle,
  theme,
}: any) {
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
                  accessibilityLabel={optionTitle(option, labels)}
                  accessibilityRole="checkbox"
                  accessibilityState={{ checked: active }}
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

export function ControlStatus({ app, error, loading, retryKey, theme }: any) {
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
            accessibilityLabel={app.labels.retryButtonTitle ?? 'Retry'}
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

export function reportControlError(app: any, control: any, error: unknown) {
  app.reportError(
    error,
    control?.label ?? control?.title ?? control?.id ?? 'Control',
  );
}

export function actionPlaceholderLabel(app: any, placeholder: string) {
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

export function actionColors(action: any, disabled: boolean, theme: any) {
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

export function helpTextFor(item: any) {
  return item?.tooltip ?? item?.help ?? item?.description ?? item?.subtitle;
}
