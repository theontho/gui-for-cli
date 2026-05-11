import React from 'react';
import {
  ActivityIndicator,
  Pressable,
  SafeAreaView,
  StatusBar,
  Text,
  useColorScheme,
  View,
} from 'react-native';
import { apiBase } from './src/api';
import { Shell } from './src/Shell';
import { palette, styles } from './src/styles';
import { useGuiForCLIApp } from './src/useGuiForCLIApp';

function App(): React.JSX.Element {
  const isDarkMode = useColorScheme() === 'dark';
  const theme = palette(isDarkMode);
  const app = useGuiForCLIApp();

  return (
    <SafeAreaView style={[styles.safeArea, {backgroundColor: theme.background}]}>
      <StatusBar barStyle={isDarkMode ? 'light-content' : 'dark-content'} />
      <View style={styles.app}>
        <View
          style={[
            styles.header,
            {
              backgroundColor: theme.panel,
              borderBottomColor: theme.border,
            },
          ]}>
          <View style={styles.headerTextWrap}>
            <Text style={[styles.headerTitle, {color: theme.foreground}]}>
              GUI for CLI React Native
            </Text>
            <Text style={[styles.headerSubtitle, {color: theme.muted}]}>
              Native Windows shell backed by the existing WebUI API at {apiBase()}
            </Text>
          </View>
          <Pressable
            accessibilityRole="button"
            onPress={app.reload}
            style={[
              styles.headerButton,
              {
                backgroundColor: theme.accentSoft,
                borderColor: theme.border,
              },
            ]}>
            <Text style={[styles.headerButtonLabel, {color: theme.accent}]}>
              Reload
            </Text>
          </Pressable>
        </View>

        {app.status === 'loading' ? (
          <View style={styles.centeredState}>
            <ActivityIndicator color={theme.accent} size="large" />
            <Text style={[styles.stateTitle, {color: theme.foreground}]}>
              Loading bundle from the WebUI server…
            </Text>
          </View>
        ) : null}

        {app.status === 'error' ? (
          <View
            style={[
              styles.centeredState,
              styles.stateCard,
              {
                backgroundColor: theme.panel,
                borderColor: theme.border,
              },
            ]}>
            <Text style={[styles.stateTitle, {color: theme.foreground}]}>
              Could not load the React Native surface
            </Text>
            <Text style={[styles.stateBody, {color: theme.muted}]}>
              {app.error}
            </Text>
            <Text style={[styles.stateBody, {color: theme.muted}]}>
              Start the existing WebUI backend with `make web` or point the app at
              a running server on localhost.
            </Text>
          </View>
        ) : null}

        {app.status === 'ready' ? <Shell app={app} theme={theme} /> : null}
      </View>
    </SafeAreaView>
  );
}

export default App;
