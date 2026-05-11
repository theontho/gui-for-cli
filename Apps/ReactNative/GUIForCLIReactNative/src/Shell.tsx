import React from 'react';
import { Pressable, ScrollView, Text, View } from 'react-native';
import { Sidebar } from './ShellNavigation';
import {
  ConfirmationDialog,
  SectionCard,
  SetupStatusSection,
  StandardOptionsSection,
} from './ShellSections';
import { TerminalPane } from './ShellTerminal';
import { iconGlyph } from './model';
import { styles } from './styles';

export function Shell({ app, theme }: any) {
  const activePage =
    app.manifest?.pages?.find((page: any) => page.id === app.activePageID) ??
    app.manifest?.pages?.[0];

  return (
    <View style={styles.shell}>
      <View style={[styles.shellBody, app.isRTL ? styles.shellBodyRTL : null]}>
        {app.isSidebarVisible ? <Sidebar app={app} theme={theme} /> : null}
        <View style={styles.contentWrap}>
          <View
            style={[
              styles.shellToolbar,
              { backgroundColor: theme.panel, borderBottomColor: theme.border },
            ]}
          >
            <Pressable
              accessibilityRole="button"
              onPress={app.toggleSidebar}
              style={[styles.smallButton, { borderColor: theme.border }]}
            >
              <Text style={[styles.actionHint, { color: theme.accent }]}>
                {app.isSidebarVisible
                  ? app.labels.sidebarHideLabel ?? 'Hide Sidebar'
                  : app.labels.sidebarShowLabel ?? 'Show Sidebar'}
              </Text>
            </Pressable>
            <Pressable
              accessibilityRole="button"
              onPress={app.toggleTerminal}
              style={[styles.smallButton, { borderColor: theme.border }]}
            >
              <Text style={[styles.actionHint, { color: theme.accent }]}>
                {app.isTerminalVisible
                  ? app.labels.terminalHideLabel ?? 'Hide Terminal'
                  : app.labels.terminalShowLabel ?? 'Show Terminal'}
              </Text>
            </Pressable>
          </View>
          <ScrollView style={styles.pageScroll}>
            <View style={styles.pageContent}>
              <View style={styles.pageHeader}>
                <Text style={[styles.pageTitle, { color: theme.foreground }]}>
                  {iconGlyph(activePage?.iconName, activePage?.iconEmoji, '📄')}{' '}
                  {activePage?.title}
                </Text>
                {activePage?.summary ? (
                  <Text style={[styles.pageSummary, { color: theme.muted }]}>
                    {activePage.summary}
                  </Text>
                ) : null}
              </View>

              {activePage?.id === 'settings' ? (
                <>
                  <SetupStatusSection app={app} theme={theme} />
                  <StandardOptionsSection app={app} theme={theme} />
                </>
              ) : null}

              {(activePage?.sections ?? []).map((section: any) => (
                <SectionCard
                  app={app}
                  key={section.id}
                  section={section}
                  theme={theme}
                />
              ))}
            </View>
          </ScrollView>
        </View>
      </View>
      {app.isTerminalVisible ? <TerminalPane app={app} theme={theme} /> : null}
      <ConfirmationDialog app={app} theme={theme} />
    </View>
  );
}
