import React from 'react';
import { Image, Pressable, ScrollView, Text, View } from 'react-native';
import { apiBase } from './api';
import { iconGlyph, pageGroups } from './model';
import { styles } from './styles';
import { reportShellError } from './ShellSupport';

export function Sidebar({ app, theme }: any) {
  const bottomIDs = new Set(['library', 'settings']);
  const groups = pageGroups(app.manifest);
  const primaryGroups = groups
    .map(group => ({
      ...group,
      pages: group.pages.filter((page: any) => !bottomIDs.has(page.id)),
    }))
    .filter(group => group.pages.length > 0);
  const bottomGroups = groups
    .map(group => ({
      ...group,
      pages: group.pages.filter((page: any) => bottomIDs.has(page.id)),
    }))
    .filter(group => group.pages.length > 0);
  const iconPath = app.manifest?.iconPath
    ? `${apiBase()}/api/file?path=${encodeURIComponent(app.manifest.iconPath)}`
    : '';
  return (
    <ScrollView
      style={[
        styles.sidebar,
        app.isRTL ? styles.sidebarRTL : null,
        app.isRTL
          ? { backgroundColor: theme.panel, borderLeftColor: theme.border }
          : { backgroundColor: theme.panel, borderRightColor: theme.border },
      ]}
    >
      <View style={styles.sidebarHeader}>
        {iconPath ? (
          <Image source={{ uri: iconPath }} style={styles.bundleIconImage} />
        ) : (
          <Text style={styles.bundleIconEmoji}>
            {iconGlyph(app.manifest?.iconName, app.manifest?.iconEmoji, '🧰')}
          </Text>
        )}
        <View style={styles.headerTextWrap}>
          <Text style={[styles.sidebarTitle, { color: theme.foreground }]}>
            {app.manifest?.displayName ?? 'GUI for CLI'}
          </Text>
          {app.manifest?.summary ? (
            <Text style={[styles.sidebarSummary, { color: theme.muted }]}>
              {app.manifest.summary}
            </Text>
          ) : null}
        </View>
      </View>
      <NavigationGroups app={app} groups={primaryGroups} theme={theme} />
      {bottomGroups.length ? (
        <View style={[styles.navBottom, { borderTopColor: theme.border }]}>
          <NavigationGroups
            app={app}
            groups={bottomGroups}
            showTitles={false}
            theme={theme}
          />
        </View>
      ) : null}
    </ScrollView>
  );
}

export function NavigationGroups({
  app,
  groups,
  showTitles = true,
  theme,
}: any) {
  return (
    <>
      {groups.map((group: any) => (
        <View key={group.title ?? 'ungrouped'}>
          {showTitles && group.title ? (
            <Text style={[styles.sidebarGroupTitle, { color: theme.muted }]}>
              {group.title}
            </Text>
          ) : null}
          {group.pages.map((page: any) => {
            const active = page.id === app.activePageID;
            return (
              <Pressable
                accessibilityRole="button"
                accessibilityState={{ selected: active }}
                key={page.id}
                onPress={() => {
                  app
                    .updateActivePage(page.id)
                    .catch((error: unknown) =>
                      reportShellError(app, page.title, error),
                    );
                }}
                style={[
                  styles.sidebarButton,
                  {
                    backgroundColor: active ? theme.accentSoft : theme.panel,
                    borderColor: active ? theme.accent : theme.border,
                  },
                ]}
              >
                <Text
                  style={[
                    styles.sidebarButtonLabel,
                    { color: active ? theme.accent : theme.foreground },
                  ]}
                >
                  {iconGlyph(page.iconName, page.iconEmoji, '📄')} {page.title}
                </Text>
              </Pressable>
            );
          })}
        </View>
      ))}
    </>
  );
}
