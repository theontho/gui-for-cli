import React from 'react';
import { Pressable, ScrollView, Text, View } from 'react-native';
import { terminalStatusLabel } from './model';
import { styles } from './styles';

export function TerminalPane({ app, theme }: any) {
  const activeEntry =
    app.terminalEntries.find(
      (entry: any) => entry.id === app.activeTerminalID,
    ) ?? app.terminalEntries[0];

  return (
    <View
      style={[
        styles.terminal,
        { backgroundColor: theme.panel, borderTopColor: theme.border },
      ]}
    >
      <ScrollView horizontal style={styles.terminalTabs}>
        {app.terminalEntries.map((entry: any) => {
          const active = entry.id === app.activeTerminalID;
          return (
            <Pressable
              accessibilityLabel={entry.title}
              accessibilityRole="button"
              accessibilityState={{ selected: active }}
              key={entry.id}
              onLongPress={() => {
                app.closeTerminal(entry.id);
              }}
              onPress={() => {
                app.selectTerminal(entry.id);
              }}
              style={[
                styles.terminalTab,
                {
                  backgroundColor: active ? theme.accentSoft : theme.panel,
                  borderColor: active ? theme.accent : theme.border,
                },
              ]}
            >
              <Text
                style={[
                  styles.terminalTabLabel,
                  { color: active ? theme.accent : theme.foreground },
                ]}
              >
                {entry.kind === 'command' ? '… ' : ''}
                {entry.title}
              </Text>
              <View style={styles.terminalTabActions}>
                {entry.kind === 'command' ? (
                  <Pressable
                    accessibilityLabel={`${app.labels.cancelButtonTitle ?? 'Cancel'} ${entry.title}`}
                    accessibilityRole="button"
                    onPress={() => app.cancelAction(entry.id)}
                    style={[
                      styles.tabActionButton,
                      { borderColor: theme.border },
                    ]}
                  >
                    <Text
                      style={[styles.tabActionLabel, { color: theme.warning }]}
                    >
                      {app.labels.cancelButtonTitle ?? 'Cancel'}
                    </Text>
                  </Pressable>
                ) : null}
                {entry.id !== 'main' ? (
                  <Pressable
                    accessibilityLabel={`${app.labels.closeButtonTitle ?? 'Close'} ${entry.title}`}
                    accessibilityRole="button"
                    onPress={() => app.closeTerminal(entry.id)}
                    style={[
                      styles.tabActionButton,
                      { borderColor: theme.border },
                    ]}
                  >
                    <Text
                      style={[styles.tabActionLabel, { color: theme.muted }]}
                    >
                      ×
                    </Text>
                  </Pressable>
                ) : null}
              </View>
            </Pressable>
          );
        })}
      </ScrollView>
      <View
        style={[
          styles.terminalBody,
          { backgroundColor: theme.background, borderColor: theme.border },
        ]}
      >
        {activeEntry?.status ? (
          <View
            style={[
              styles.badge,
              {
                backgroundColor:
                  activeEntry.status.severity === 'warning'
                    ? theme.accentSoft
                    : theme.panel,
                borderColor:
                  activeEntry.status.severity === 'warning'
                    ? theme.warning
                    : theme.border,
              },
            ]}
          >
            <Text
              style={[
                styles.badgeLabel,
                {
                  color:
                    activeEntry.status.severity === 'warning'
                      ? theme.warning
                      : theme.foreground,
                },
              ]}
            >
              {terminalStatusLabel(activeEntry)}
            </Text>
          </View>
        ) : null}
        <ScrollView>
          <Text
            style={[
              styles.terminalBodyText,
              {
                color: theme.foreground,
                writingDirection: app.terminalIsRTL ? 'rtl' : 'ltr',
              },
            ]}
          >
            {activeEntry?.body ?? ''}
          </Text>
        </ScrollView>
      </View>
    </View>
  );
}
