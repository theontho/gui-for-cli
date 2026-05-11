import React, { useEffect, useMemo } from 'react';
import { Pressable, Text, View } from 'react-native';
import {
  actionPrecheckCacheKey,
  fieldStateCacheKey,
  formatLabel,
  iconGlyph,
} from './model';
import { styles } from './styles';
import {
  disabledReason,
  isActionVisible,
  isPrecheckReady,
  missingPlaceholders,
} from './webuiCore';
import {
  HelpText,
  actionColors,
  actionPlaceholderLabel,
  helpTextFor,
  reportControlError,
} from './ControlSupport';

export function ActionList({ app, actions, context, compact, theme }: any) {
  const fileStateKey = fieldStateCacheKey(context);

  useEffect(() => {
    app.ensureFileState(fileStateKey, context).catch((error: unknown) => {
      app.reportError(error, app.labels.fileStateWarningTitle ?? 'File state');
    });
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
      if (
        action.precheck &&
        isPrecheckReady(action.precheck, resolvedContext)
      ) {
        app
          .ensureActionPrecheck(action, resolvedContext)
          .catch((error: unknown) => reportControlError(app, action, error));
      }
    });
  }, [actions, app, resolvedContext]);

  return (
    <View style={styles.actionRow}>
      {actions
        .filter((action: any) => isActionVisible(action, resolvedContext))
        .map((action: any) => {
          const missing = missingPlaceholders(action.command, resolvedContext);
          const missingLabels = missing.map((placeholder: string) =>
            actionPlaceholderLabel(app, placeholder),
          );
          const unavailable = disabledReason(
            action,
            resolvedContext,
            app.labels.actionUnavailableTitle,
          );
          const precheckKey = actionPrecheckCacheKey(action, resolvedContext);
          const precheck = app.actionPrechecks.get(precheckKey);
          const precheckError = app.actionPrecheckErrors.get(precheckKey);
          const loadingPrecheck = app.loadingActionPrechecks.has(precheckKey);
          const precheckWarning =
            precheck?.severity === 'warning' ? precheck.message : undefined;
          const disabled =
            missing.length > 0 ||
            Boolean(unavailable) ||
            Boolean(precheckWarning) ||
            loadingPrecheck;
          const colors = actionColors(action, disabled, theme);
          const icon = iconGlyph(action.iconName, action.iconEmoji, '');
          const title = action.iconOnly && icon ? '' : action.title;
          return (
            <Pressable
              accessibilityLabel={action.title}
              accessibilityHint={
                precheck?.message ??
                precheckError ??
                unavailable ??
                (missing.length > 0
                  ? formatLabel(app.labels.actionMissingInputsFormat, {
                      inputs: missingLabels.join(', '),
                    })
                  : undefined)
              }
              accessibilityRole="button"
              disabled={disabled}
              key={action.id}
              onPress={() => {
                app
                  .runAction(action, resolvedContext)
                  .catch((error: unknown) =>
                    reportControlError(app, action, error),
                  );
              }}
              style={[
                styles.actionButton,
                compact || action.iconOnly ? styles.actionButtonCompact : null,
                disabled ? styles.actionButtonDisabled : null,
                {
                  backgroundColor: colors.backgroundColor,
                  borderColor: colors.borderColor,
                },
              ]}
            >
              <Text style={[styles.actionButtonLabel, { color: colors.color }]}>
                {compact || action.iconOnly ? icon : ''}
                {compact && !action.iconOnly && icon ? ' ' : ''}
                {title}
              </Text>
              <HelpText text={helpTextFor(action)} theme={theme} />
              {loadingPrecheck ? (
                <Text style={[styles.actionHint, { color: theme.muted }]}>
                  {app.labels.refreshingTitle ?? 'Refreshing...'}
                </Text>
              ) : null}
              {precheckError ? (
                <Text style={[styles.actionHint, { color: theme.danger }]}>
                  {precheckError}
                </Text>
              ) : null}
              {precheck?.message ? (
                <Text style={[styles.actionHint, { color: theme.warning }]}>
                  {precheck.message}
                </Text>
              ) : null}
            </Pressable>
          );
        })}
    </View>
  );
}
