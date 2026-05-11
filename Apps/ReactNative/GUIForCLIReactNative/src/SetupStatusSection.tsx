import React from 'react';
import { Pressable, Text, View } from 'react-native';
import { setupStatusSummary, setupStepStatusLabel } from './model';
import { reportShellError } from './ShellSupport';
import { styles } from './styles';

export function SetupStatusSection({ app, theme }: any) {
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
          accessibilityLabel={
            app.labels.openBundleWorkspaceTitle ?? 'Open Bundle Workspace'
          }
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
            accessibilityLabel={
              isRunning
                ? app.labels.setupRunningTitle ?? 'Running setup...'
                : runButtonTitle
            }
            accessibilityRole="button"
            accessibilityState={{ disabled: isRunning }}
            disabled={isRunning}
            onPress={() =>
              app
                .runSetup()
                .catch((error: unknown) =>
                  reportShellError(app, app.labels.setupTitle ?? 'Setup', error),
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
