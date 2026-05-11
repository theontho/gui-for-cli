import React, { useEffect } from 'react';
import { Pressable, Text, View } from 'react-native';
import { ActionList } from './ActionList';
import { ControlView } from './Controls';
import { fieldStateCacheKey, iconGlyph } from './model';
import { reportShellError } from './ShellSupport';
import { styles } from './styles';
import { commandContextFromState } from './webuiCore';

export function SectionCard({ app, section, theme }: any) {
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
          accessibilityLabel={app.labels.retryButtonTitle ?? 'Retry'}
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
