part of '../main.dart';

extension _BundleHomePageStatePersistence on _BundleHomePageState {
  Future<void> _saveConfig(
    ControlSpec control, {
    bool reportSuccess = false,
  }) {
    final nextSave = _configSaveQueue.then((_) async {
      final path = _configFilePaths[control.id] ?? control.configFile?.path;
      if (path == null || path.trim().isEmpty) {
        _appendTerminal(
            '[config:error] Choose a settings file path before saving.');
        return;
      }
      try {
        await saveConfigFile(
          control: control,
          path: path,
          bundleRoot: bundleRoot,
          configValues: _configValues,
        );
        if (reportSuccess) {
          _appendTerminal(
              '[config] Saved ${control.settings.length} setting(s) to $path');
        }
      } catch (error) {
        _appendTerminal('[config:error] $error');
      }
    });
    _configSaveQueue = nextSave.catchError((_) {});
    return nextSave;
  }

  void _persistBundleState() {
    saveBundleState(bundleRoot, _bundleState).catchError((Object error) {
      _appendTerminal('[state:error] $error');
    });
  }
}
