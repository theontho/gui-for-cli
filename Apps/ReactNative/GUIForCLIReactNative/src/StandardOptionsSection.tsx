import React from 'react';
import { Pressable, Text, View } from 'react-native';
import { reportShellError } from './ShellSupport';
import { styles } from './styles';

export function StandardOptionsSection({ app, theme }: any) {
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
                  accessibilityLabel={option.displayName}
                  accessibilityRole="button"
                  accessibilityState={{ selected: active }}
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
              accessibilityLabel={`${label}: ${option.title}`}
              accessibilityRole="button"
              accessibilityState={{ selected: active }}
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
