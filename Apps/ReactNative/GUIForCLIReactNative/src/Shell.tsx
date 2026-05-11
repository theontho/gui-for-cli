import React, {useEffect} from 'react';
import {Pressable, ScrollView, Text, View} from 'react-native';
import {ActionList, ControlView} from './Controls';
import {fieldStateCacheKey, iconGlyph, pageGroups, terminalStatusLabel} from './model';
import {styles} from './styles';
import {commandContextFromState} from './webuiCore';

function SectionCard({app, section, theme}: any) {
  const sectionKey = `section:${section.id}`;

  useEffect(() => {
    if (section.dataSource) {
      app.ensureDataSource(
        sectionKey,
        section.dataSource,
        commandContextFromState(app),
      ).catch(() => undefined);
    }
  }, [app, section, sectionKey]);

  const sectionValues = app.dataSourcePayloads.get(sectionKey)?.values ?? {};
  const sectionContext = commandContextFromState(app, {}, sectionValues);
  const fileStateKey = fieldStateCacheKey(sectionContext);

  useEffect(() => {
    app.ensureFileState(fileStateKey, sectionContext).catch(() => undefined);
  }, [app, fileStateKey, sectionContext]);

  const resolvedSectionContext = {
    ...sectionContext,
    fileStateValues: app.fileStateValues.get(fileStateKey) ?? {},
  };

  return (
    <View
      style={[
        styles.card,
        {backgroundColor: theme.panel, borderColor: theme.border},
      ]}>
      {section.title ? (
        <Text style={[styles.sectionTitle, {color: theme.foreground}]}>
          {iconGlyph(section.iconName, section.iconEmoji, '▦')} {section.title}
        </Text>
      ) : null}
      {section.subtitle ? (
        <Text style={[styles.sectionSubtitle, {color: theme.muted}]}>
          {section.subtitle}
        </Text>
      ) : null}

      {(section.controls ?? []).map((control: any) => (
        <ControlView
          app={app}
          control={control}
          key={control.id}
          sectionContext={resolvedSectionContext}
          theme={theme}
        />
      ))}

      {(section.actions ?? []).length ? (
        <ActionList
          actions={section.actions}
          app={app}
          context={resolvedSectionContext}
          theme={theme}
        />
      ) : null}
    </View>
  );
}

function Sidebar({app, theme}: any) {
  return (
    <ScrollView
      style={[
        styles.sidebar,
        {backgroundColor: theme.panel, borderRightColor: theme.border},
      ]}>
      {pageGroups(app.manifest).map(group => (
        <View key={group.title ?? 'ungrouped'}>
          {group.title ? (
            <Text style={[styles.sidebarGroupTitle, {color: theme.muted}]}>
              {group.title}
            </Text>
          ) : null}
          {group.pages.map((page: any) => {
            const active = page.id === app.activePageID;
            return (
              <Pressable
                key={page.id}
                onPress={() => {
                  app.updateActivePage(page.id).catch(() => undefined);
                }}
                style={[
                  styles.sidebarButton,
                  {
                    backgroundColor: active ? theme.accentSoft : theme.panel,
                    borderColor: active ? theme.accent : theme.border,
                  },
                ]}>
                <Text
                  style={[
                    styles.sidebarButtonLabel,
                    {color: active ? theme.accent : theme.foreground},
                  ]}>
                  {iconGlyph(page.iconName, page.iconEmoji, '📄')} {page.title}
                </Text>
              </Pressable>
            );
          })}
        </View>
      ))}
    </ScrollView>
  );
}

function TerminalPane({app, theme}: any) {
  const activeEntry =
    app.terminalEntries.find((entry: any) => entry.id === app.activeTerminalID) ??
    app.terminalEntries[0];

  return (
    <View
      style={[
        styles.terminal,
        {backgroundColor: theme.panel, borderTopColor: theme.border},
      ]}>
      <ScrollView horizontal style={styles.terminalTabs}>
        {app.terminalEntries.map((entry: any) => {
          const active = entry.id === app.activeTerminalID;
          return (
            <Pressable
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
              ]}>
              <Text
                style={[
                  styles.terminalTabLabel,
                  {color: active ? theme.accent : theme.foreground},
                ]}>
                {entry.kind === 'command' ? '… ' : ''}
                {entry.title}
              </Text>
            </Pressable>
          );
        })}
      </ScrollView>
      <View
        style={[
          styles.terminalBody,
          {backgroundColor: theme.background, borderColor: theme.border},
        ]}>
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
            ]}>
            <Text
              style={[
                styles.badgeLabel,
                {
                  color:
                    activeEntry.status.severity === 'warning'
                      ? theme.warning
                      : theme.foreground,
                },
              ]}>
              {terminalStatusLabel(activeEntry)}
            </Text>
          </View>
        ) : null}
        <ScrollView>
          <Text style={[styles.terminalBodyText, {color: theme.foreground}]}>
            {activeEntry?.body ?? ''}
          </Text>
        </ScrollView>
      </View>
    </View>
  );
}

export function Shell({app, theme}: any) {
  const activePage =
    app.manifest?.pages?.find((page: any) => page.id === app.activePageID) ??
    app.manifest?.pages?.[0];

  return (
    <View style={styles.shell}>
      <View style={styles.shellBody}>
        <Sidebar app={app} theme={theme} />
        <View style={styles.contentWrap}>
          <ScrollView style={styles.pageScroll}>
            <View style={styles.pageContent}>
              <View style={styles.pageHeader}>
                <Text style={[styles.pageTitle, {color: theme.foreground}]}>
                  {iconGlyph(activePage?.iconName, activePage?.iconEmoji, '📄')}{' '}
                  {activePage?.title}
                </Text>
                {activePage?.summary ? (
                  <Text style={[styles.pageSummary, {color: theme.muted}]}>
                    {activePage.summary}
                  </Text>
                ) : null}
              </View>

              {activePage?.id === 'settings' && app.localizationOptions.length > 0 ? (
                <View
                  style={[
                    styles.card,
                    {backgroundColor: theme.panel, borderColor: theme.border},
                  ]}>
                  <Text style={[styles.sectionTitle, {color: theme.foreground}]}>
                    {app.labels.languageSectionTitle ?? 'Interface Language'}
                  </Text>
                  <View style={styles.choiceWrap}>
                    {app.localizationOptions.map((option: any) => {
                      const active = option.code === app.localizationCode;
                      return (
                        <Pressable
                          key={option.code}
                          onPress={() => {
                            app.selectLocale(option.code).catch(() => undefined);
                          }}
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
                            {option.displayName}
                          </Text>
                        </Pressable>
                      );
                    })}
                  </View>
                </View>
              ) : null}

              {(activePage?.sections ?? []).map((section: any) => (
                <SectionCard app={app} key={section.id} section={section} theme={theme} />
              ))}
            </View>
          </ScrollView>
        </View>
      </View>
      <TerminalPane app={app} theme={theme} />
    </View>
  );
}
