import React, { useEffect } from 'react';
import {
  Image,
  Pressable,
  ScrollView,
  Text,
  TextInput,
  View,
} from 'react-native';
import { apiBase } from './api';
import { ActionList, ControlView } from './Controls';
import {
  fieldStateCacheKey,
  iconGlyph,
  pageGroups,
  resolveText,
  setupStatusSummary,
  setupStepStatusLabel,
  terminalStatusLabel,
} from './model';
import { styles } from './styles';
import { commandContextFromState } from './webuiCore';

function reportShellError(app: any, title: string, error: unknown) {
  app.reportError(error, title);
}

function SectionCard({ app, section, theme }: any) {
  const sectionKey = `section:${section.id}`;

  useEffect(() => {
    if (section.dataSource) {
      app
        .ensureDataSource(
          sectionKey,
          section.dataSource,
          commandContextFromState(app),
        )
        .catch((error: unknown) => reportShellError(app, section.title, error));
    }
  }, [app, section, sectionKey]);

  const sectionValues = app.dataSourcePayloads.get(sectionKey)?.values ?? {};
  const sectionContext = commandContextFromState(app, {}, sectionValues);
  const fileStateKey = fieldStateCacheKey(sectionContext);

  useEffect(() => {
    app
      .ensureFileState(fileStateKey, sectionContext)
      .catch((error: unknown) =>
        reportShellError(
          app,
          app.labels.fileStateWarningTitle ?? 'File state',
          error,
        ),
      );
  }, [app, fileStateKey, sectionContext]);

  const resolvedSectionContext = {
    ...sectionContext,
    fileStateValues: app.fileStateValues.get(fileStateKey) ?? {},
  };

  return (
    <View
      style={[
        styles.card,
        { backgroundColor: theme.panel, borderColor: theme.border },
      ]}
    >
      {section.title ? (
        <Text style={[styles.sectionTitle, { color: theme.foreground }]}>
          {iconGlyph(section.iconName, section.iconEmoji, '▦')} {section.title}
        </Text>
      ) : null}
      {section.subtitle ? (
        <Text style={[styles.sectionSubtitle, { color: theme.muted }]}>
          {section.subtitle}
        </Text>
      ) : null}
      {app.loadingDataSources.has(sectionKey) ? (
        <Text style={[styles.actionHint, { color: theme.muted }]}>
          {app.labels.loadingTitle ?? 'Loading...'}
        </Text>
      ) : null}
      {app.dataSourceErrors.get(sectionKey) ? (
        <Pressable
          accessibilityRole="button"
          onPress={() => app.retryDataSource(sectionKey)}
          style={[styles.smallButton, { borderColor: theme.border }]}
        >
          <Text style={[styles.actionHint, { color: theme.danger }]}>
            ⚠ {app.dataSourceErrors.get(sectionKey)}
          </Text>
        </Pressable>
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

function Sidebar({ app, theme }: any) {
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

function NavigationGroups({ app, groups, showTitles = true, theme }: any) {
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

function TerminalPane({ app, theme }: any) {
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

function SetupStatusSection({ app, theme }: any) {
  const steps = app.manifest?.setup?.steps ?? [];
  const setupRun = app.setupRun ?? {};
  const resultsByID = new Map(
    (setupRun.results ?? []).map((result: any) => [result.id, result]),
  );
  const isRunning = setupRun.status === 'running';
  const runButtonTitle =
    setupRun.status === 'ok'
      ? app.labels.setupRerunButtonTitle ?? 'Rerun Setup'
      : app.labels.setupRunButtonTitle ?? 'Run Setup';
  return (
    <View
      style={[
        styles.card,
        { backgroundColor: theme.panel, borderColor: theme.border },
      ]}
    >
      <View style={styles.setupHeader}>
        <View style={styles.headerTextWrap}>
          <Text style={[styles.sectionTitle, { color: theme.foreground }]}>
            {app.labels.setupTitle ?? 'Setup'}
          </Text>
          <Text style={[styles.sectionSubtitle, { color: theme.muted }]}>
            {setupStatusSummary(app.labels, setupRun, steps.length > 0)}
          </Text>
        </View>
        <Pressable
          accessibilityRole="button"
          onPress={() =>
            app
              .openBundleWorkspace()
              .catch((error: unknown) =>
                reportShellError(
                  app,
                  app.labels.openBundleWorkspaceTitle ??
                    'Open Bundle Workspace',
                  error,
                ),
              )
          }
          style={[styles.smallButton, { borderColor: theme.border }]}
        >
          <Text style={[styles.actionHint, { color: theme.accent }]}>
            {app.labels.openBundleWorkspaceTitle ?? 'Open Bundle Workspace'}
          </Text>
        </Pressable>
        {steps.length ? (
          <Pressable
            accessibilityRole="button"
            disabled={isRunning}
            onPress={() =>
              app
                .runSetup()
                .catch((error: unknown) =>
                  reportShellError(
                    app,
                    app.labels.setupTitle ?? 'Setup',
                    error,
                  ),
                )
            }
            style={[
              styles.actionButton,
              isRunning ? styles.actionButtonDisabled : null,
              {
                backgroundColor: isRunning ? theme.panel : theme.accentSoft,
                borderColor: theme.accent,
              },
            ]}
          >
            <Text
              style={[
                styles.actionButtonLabel,
                { color: isRunning ? theme.muted : theme.accent },
              ]}
            >
              {isRunning
                ? app.labels.setupRunningTitle ?? 'Running setup...'
                : runButtonTitle}
            </Text>
          </Pressable>
        ) : null}
      </View>
      {steps.map((step: any) => {
        const status =
          setupRun.currentStepID === step.id
            ? 'running'
            : (resultsByID.get(step.id) as any)?.status ?? 'pending';
        return (
          <View
            key={step.id}
            style={[
              styles.setupStep,
              { backgroundColor: theme.background, borderColor: theme.border },
            ]}
          >
            <Text style={[styles.infoValue, { color: theme.foreground }]}>
              {status === 'ok'
                ? '✓'
                : status === 'failed'
                ? '×'
                : status === 'warning'
                ? '!'
                : status === 'running'
                ? '…'
                : '○'}{' '}
              {step.label}
            </Text>
            <Text style={[styles.infoKey, { color: theme.muted }]}>
              {step.kind} · {setupStepStatusLabel(app.labels, status)}
            </Text>
          </View>
        );
      })}
    </View>
  );
}

function StandardOptionsSection({ app, theme }: any) {
  const currentLocale =
    app.localizationOptions.find(
      (option: any) => option.code === app.localizationCode,
    )?.displayName ?? app.localizationCode;
  return (
    <View
      style={[
        styles.card,
        { backgroundColor: theme.panel, borderColor: theme.border },
      ]}
    >
      <Text style={[styles.sectionTitle, { color: theme.foreground }]}>
        {app.labels.standardOptionsSectionTitle ?? 'Standard Options'}
      </Text>
      {app.localizationOptions.length > 1 ? (
        <View style={styles.fieldWrap}>
          <Text style={[styles.fieldLabel, { color: theme.foreground }]}>
            {app.labels.languagePickerLabel ?? 'Language'}
          </Text>
          <Text style={[styles.actionHint, { color: theme.muted }]}>
            {currentLocale}
          </Text>
          <View style={styles.choiceWrap}>
            {app.localizationOptions.map((option: any) => {
              const active = option.code === app.localizationCode;
              return (
                <Pressable
                  key={option.code}
                  onPress={() =>
                    app
                      .selectLocale(option.code)
                      .catch((error: unknown) =>
                        reportShellError(app, option.displayName, error),
                      )
                  }
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
                    {option.displayName}
                  </Text>
                </Pressable>
              );
            })}
          </View>
        </View>
      ) : null}
      <PreferenceChips
        label={app.labels.iconSetPickerLabel ?? 'Icon Set'}
        onSelect={app.selectIconSet}
        onError={(error: unknown) =>
          reportShellError(
            app,
            app.labels.iconSetPickerLabel ?? 'Icon Set',
            error,
          )
        }
        options={[
          {
            id: 'platform',
            title:
              app.labels.iconSetBootstrapIconsLabel ??
              app.labels.iconSetSwiftSymbolsLabel ??
              'Platform',
          },
          { id: 'emoji', title: app.labels.iconSetEmojiLabel ?? 'Emoji' },
        ]}
        selected={app.iconSet}
        theme={theme}
      />
      <PreferenceChips
        label={app.labels.colorThemePickerLabel ?? 'Color Theme'}
        onSelect={app.selectColorTheme}
        onError={(error: unknown) =>
          reportShellError(
            app,
            app.labels.colorThemePickerLabel ?? 'Color Theme',
            error,
          )
        }
        options={[
          { id: 'system', title: app.labels.colorThemeSystemLabel ?? 'System' },
          { id: 'light', title: app.labels.colorThemeLightLabel ?? 'Light' },
          { id: 'dark', title: app.labels.colorThemeDarkLabel ?? 'Dark' },
        ]}
        selected={app.colorTheme}
        theme={theme}
      />
      <PreferenceChips
        label={app.labels.webUIFontPickerLabel ?? 'Web Font'}
        onSelect={app.selectWebUIFont}
        onError={(error: unknown) =>
          reportShellError(
            app,
            app.labels.webUIFontPickerLabel ?? 'Web Font',
            error,
          )
        }
        options={[
          { id: 'system', title: app.labels.webUIFontSystemLabel ?? 'System' },
          { id: 'sfPro', title: app.labels.webUIFontSFProLabel ?? 'SF Pro' },
        ]}
        selected={app.webUIFont}
        theme={theme}
      />
    </View>
  );
}

function PreferenceChips({
  label,
  onError,
  onSelect,
  options,
  selected,
  theme,
}: any) {
  return (
    <View style={styles.fieldWrap}>
      <Text style={[styles.fieldLabel, { color: theme.foreground }]}>
        {label}
      </Text>
      <View style={styles.choiceWrap}>
        {options.map((option: any) => {
          const active = option.id === selected;
          return (
            <Pressable
              key={option.id}
              onPress={() => onSelect(option.id).catch(onError)}
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
                {option.title}
              </Text>
            </Pressable>
          );
        })}
      </View>
    </View>
  );
}

function ConfirmationDialog({ app, theme }: any) {
  const pending = app.pendingConfirmation;
  if (!pending) {
    return null;
  }
  const confirmation = pending.action.confirm ?? {};
  const requiredText = resolveText(
    confirmation.requiredText ?? '',
    pending.context,
  );
  const canConfirm = !requiredText || pending.input === requiredText;
  return (
    <View
      style={[styles.modalBackdrop, { backgroundColor: 'rgba(0,0,0,0.4)' }]}
    >
      <View
        style={[
          styles.confirmationCard,
          { backgroundColor: theme.panel, borderColor: theme.border },
        ]}
      >
        <Text style={[styles.sectionTitle, { color: theme.foreground }]}>
          {resolveText(
            confirmation.title ?? pending.action.title,
            pending.context,
          )}
        </Text>
        {confirmation.message ? (
          <Text style={[styles.sectionSubtitle, { color: theme.muted }]}>
            {resolveText(confirmation.message, pending.context)}
          </Text>
        ) : null}
        {requiredText ? (
          <View style={styles.fieldWrap}>
            <Text style={[styles.actionHint, { color: theme.muted }]}>
              {resolveText(
                confirmation.prompt ?? `Type "${requiredText}" to confirm.`,
                pending.context,
              )}
            </Text>
            <TextInput
              onChangeText={app.updateConfirmationInput}
              placeholder={requiredText}
              placeholderTextColor={theme.muted}
              style={[
                styles.textInput,
                {
                  color: theme.foreground,
                  backgroundColor: theme.background,
                  borderColor: theme.border,
                },
              ]}
              value={pending.input}
            />
          </View>
        ) : null}
        <View style={styles.actionRow}>
          <Pressable
            accessibilityRole="button"
            onPress={app.cancelConfirmation}
            style={[styles.actionButton, { borderColor: theme.border }]}
          >
            <Text
              style={[styles.actionButtonLabel, { color: theme.foreground }]}
            >
              {confirmation.cancelButtonTitle ?? 'Cancel'}
            </Text>
          </Pressable>
          <Pressable
            accessibilityRole="button"
            disabled={!canConfirm}
            onPress={() =>
              app
                .confirmPendingAction()
                .catch((error: unknown) =>
                  reportShellError(app, pending.action.title, error),
                )
            }
            style={[
              styles.actionButton,
              !canConfirm ? styles.actionButtonDisabled : null,
              {
                backgroundColor: canConfirm ? theme.accentSoft : theme.panel,
                borderColor: canConfirm ? theme.accent : theme.border,
              },
            ]}
          >
            <Text
              style={[
                styles.actionButtonLabel,
                { color: canConfirm ? theme.accent : theme.muted },
              ]}
            >
              {confirmation.confirmButtonTitle ?? pending.action.title}
            </Text>
          </Pressable>
        </View>
      </View>
    </View>
  );
}

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
