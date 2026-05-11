import React from 'react';
import { Pressable, Text, TextInput, View } from 'react-native';
import { resolveText } from './model';
import { reportShellError } from './ShellSupport';
import { styles } from './styles';

export function ConfirmationDialog({ app, theme }: any) {
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
  const title = resolveText(
    confirmation.title ?? pending.action.title,
    pending.context,
  );
  const prompt = resolveText(
    confirmation.prompt ?? `Type "${requiredText}" to confirm.`,
    pending.context,
  );
  const cancelTitle = confirmation.cancelButtonTitle ?? 'Cancel';
  const confirmTitle = confirmation.confirmButtonTitle ?? pending.action.title;

  return (
    <View
      accessibilityRole="alert"
      style={[styles.modalBackdrop, { backgroundColor: 'rgba(0,0,0,0.4)' }]}
    >
      <View
        style={[
          styles.confirmationCard,
          { backgroundColor: theme.panel, borderColor: theme.border },
        ]}
      >
        <Text style={[styles.sectionTitle, { color: theme.foreground }]}>
          {title}
        </Text>
        {confirmation.message ? (
          <Text style={[styles.sectionSubtitle, { color: theme.muted }]}>
            {resolveText(confirmation.message, pending.context)}
          </Text>
        ) : null}
        {requiredText ? (
          <View style={styles.fieldWrap}>
            <Text style={[styles.actionHint, { color: theme.muted }]}>
              {prompt}
            </Text>
            <TextInput
              accessibilityLabel={prompt}
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
            accessibilityLabel={cancelTitle}
            accessibilityRole="button"
            onPress={app.cancelConfirmation}
            style={[styles.actionButton, { borderColor: theme.border }]}
          >
            <Text
              style={[styles.actionButtonLabel, { color: theme.foreground }]}
            >
              {cancelTitle}
            </Text>
          </Pressable>
          <Pressable
            accessibilityLabel={confirmTitle}
            accessibilityRole="button"
            accessibilityState={{ disabled: !canConfirm }}
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
              {confirmTitle}
            </Text>
          </Pressable>
        </View>
      </View>
    </View>
  );
}
