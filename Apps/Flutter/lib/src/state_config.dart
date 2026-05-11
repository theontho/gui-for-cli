// ignore_for_file: invalid_use_of_protected_member

part of '../main.dart';

extension _BundleHomePageStateConfig on _BundleHomePageState {
  Future<void> _loadRuntimeStateAndData(BundleManifest manifest) async {
    _runtimeInitialized = true;
    final messages = <String>[];
    final loadedState = loadBundleState(bundleRoot, messages.add);
    final configPaths = initialConfigFilePaths(manifest, loadedState);
    try {
      messages.addAll(await bootstrapConfigFiles(
        manifest: manifest,
        bundleRoot: bundleRoot,
        configFilePaths: configPaths,
      ));
    } catch (error) {
      messages.add('[config:error] $error');
    }
    final initialConfig = await loadInitialConfigValues(
      manifest: manifest,
      bundleRoot: bundleRoot,
      configFilePaths: configPaths,
    );
    messages.addAll(initialConfig.messages);
    if (!mounted) {
      return;
    }
    setState(() {
      _bundleState = loadedState;
      _applyThemePreference(_bundleState.colorTheme);
      final persistedSidebarWidth = _bundleState.sidebarWidth;
      if (persistedSidebarWidth != null) {
        _sidebarWidth = persistedSidebarWidth.clamp(180, 420).toDouble();
      }
      _configFilePaths = configPaths;
      _configValues = initialConfig.values;
      _dataSourceErrors
        ..clear()
        ..addAll(_bundleState.dataSourceErrors);
      _fieldValues = initialFieldValuesFromStateAndConfig(
        manifest,
        _configValues,
        _bundleState,
      );
      _checkedOptions = initialCheckedOptionsFromStateAndConfig(
        manifest,
        _configValues,
        _bundleState,
      );
      final selectedPageID = _bundleState.selectedPageID;
      if (selectedPageID != null) {
        _selectedPage = manifest.pages.firstWhere(
          (page) => page.id == selectedPageID,
          orElse: () => _selectedPage ?? manifest.pages.first,
        );
      }
      for (final result in _bundleState.setupRun?.results ??
          const <FlutterSetupStepRunState>[]) {
        _setupStatuses[result.id] = result.status;
      }
    });
    if (_bundleState.localizationCode != null &&
        _bundleState.localizationCode != manifest.defaultLocalizationCode) {
      await _reloadLocalizedManifest(_bundleState.localizationCode!);
    }
    for (final message in messages) {
      _appendTerminal(message);
    }
    _startBundleHotReloadIfEnabled();
    await _refreshDataSources(_manifest ?? manifest, markContentReady: true);
  }

  void _selectPage(BundlePage page) {
    setState(() => _selectedPage = page);
    _bundleState.selectedPageID = page.id;
    _persistBundleState();
  }

  void _setSidebarWidth(double width) {
    setState(() => _sidebarWidth = width);
    _bundleState.sidebarWidth = width.roundToDouble();
    _persistBundleState();
  }

  Future<void> selectLocalizationCode(String code) async {
    _bundleState.localizationCode = code;
    _persistBundleState();
    await _reloadLocalizedManifest(code);
  }

  void selectIconSet(String iconSet) {
    setState(() => _bundleState.iconSet = iconSet);
    _persistBundleState();
  }

  void selectColorTheme(String colorTheme) {
    setState(() => _bundleState.colorTheme = colorTheme);
    _applyThemePreference(colorTheme);
    _persistBundleState();
  }

  void _applyThemePreference(String colorTheme) {
    _appThemeMode.value = switch (colorTheme) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> _reloadLocalizedManifest(String code) async {
    try {
      final localized = await BundleLoader(
        repoRoot: repoRoot,
        bundleRoot: bundleRoot,
      ).load(locale: code);
      if (!mounted) {
        return;
      }
      setState(() {
        _manifest = localized;
        final selectedID = _selectedPage?.id;
        if (selectedID != null) {
          _selectedPage = localized.pages.firstWhere(
            (page) => page.id == selectedID,
            orElse: () => localized.pages.first,
          );
        }
      });
      _appendTerminal('[bundle] Loaded localization: $code');
    } catch (error) {
      _appendTerminal(
          '[bundle:error] Could not load localization $code: $error');
    }
  }

  String configSettingValue(ControlSpec control, ConfigSettingSpec setting) {
    final fieldKey = boundFieldKey(_fieldValues, setting);
    if (fieldKey != null) {
      return _fieldValues[fieldKey] ?? '';
    }
    return _configValues[configValueKey(control, setting)] ??
        setting.value ??
        '';
  }

  void _fieldValueChanged(
    ControlSpec control,
    String value, {
    bool updateField = true,
  }) {
    setState(() {
      if (updateField) {
        _fieldValues[control.id] = value;
      }
    });
    final manifest = _manifest;
    if (manifest == null) {
      return;
    }
    final bindings = configSettingBindings(manifest, control.id);
    if (bindings.isEmpty) {
      _bundleState.fieldValues[control.id] = value;
      _persistBundleState();
      return;
    }
    _bundleState.fieldValues.remove(control.id);
    _persistBundleState();
    for (final binding in bindings) {
      _configValues[configValueKey(binding.control, binding.setting)] = value;
      _saveConfig(binding.control, reportSuccess: false);
    }
  }

  void _checkedOptionsChanged(ControlSpec control, Set<String> selected) {
    setState(() => _checkedOptions[control.id] = selected);
    final manifest = _manifest;
    if (manifest == null) {
      return;
    }
    final bindings = configSettingBindings(manifest, control.id);
    final value = (selected.toList()..sort()).join(',');
    if (bindings.isEmpty) {
      _bundleState.checkedOptions[control.id] = selected.toList()..sort();
      _persistBundleState();
      return;
    }
    _bundleState.checkedOptions.remove(control.id);
    _persistBundleState();
    for (final binding in bindings) {
      _configValues[configValueKey(binding.control, binding.setting)] = value;
      _saveConfig(binding.control, reportSuccess: false);
    }
  }

  void _configSettingChanged(
    String controlID,
    ConfigSettingSpec setting,
    String value,
  ) {
    final control = _controlByID(controlID);
    if (control == null) {
      return;
    }
    setState(() {
      _configValues[configValueKey(control, setting)] = value;
      final fieldKey = boundFieldKey(_fieldValues, setting);
      if (fieldKey != null) {
        _fieldValues[fieldKey] = value;
        _bundleState.fieldValues.remove(fieldKey);
      }
    });
    _persistBundleState();
    _saveConfig(control, reportSuccess: false);
  }

  void _configFilePathChanged(ControlSpec control, String value) {
    setState(() => _configFilePaths[control.id] = value);
    _bundleState.configFilePaths[control.id] = value;
    _persistBundleState();
  }

  Future<void> _loadConfig(ControlSpec control) async {
    final path = _configFilePaths[control.id] ?? control.configFile?.path;
    if (path == null || path.trim().isEmpty) {
      _appendTerminal(
          '[config:error] Choose a settings file path before loading.');
      return;
    }
    try {
      final values = await loadConfigFile(
        control: control,
        path: path,
        bundleRoot: bundleRoot,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        for (final setting in control.settings) {
          final value = values[setting.key] ?? setting.value ?? '';
          _configValues[configValueKey(control, setting)] = value;
          final fieldKey = boundFieldKey(_fieldValues, setting);
          if (fieldKey != null) {
            _fieldValues[fieldKey] = value;
            _fieldVersions[fieldKey] = (_fieldVersions[fieldKey] ?? 0) + 1;
          }
          final settingKey = configValueKey(control, setting);
          _fieldVersions[settingKey] = (_fieldVersions[settingKey] ?? 0) + 1;
        }
      });
      _appendTerminal('[config] Loaded settings from $path');
      final manifest = _manifest;
      if (manifest != null) {
        await _refreshDataSources(manifest, force: true);
      }
    } catch (error) {
      _appendTerminal('[config:error] $error');
    }
  }

  Future<void> retryDataSources() async {
    final manifest = _manifest;
    if (manifest == null) {
      _appendTerminal('[data:error] Bundle is not loaded yet.');
      return;
    }
    await _refreshDataSources(manifest, force: true);
  }

  Future<void> _saveConfig(
    ControlSpec control, {
    bool reportSuccess = false,
  }) async {
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
  }

  void _persistBundleState() {
    saveBundleState(bundleRoot, _bundleState).catchError((Object error) {
      _appendTerminal('[state:error] $error');
    });
  }

  ControlSpec? _controlByID(String controlID) {
    final manifest = _manifest;
    if (manifest == null) {
      return null;
    }
    for (final control in allControls(manifest)) {
      if (control.id == controlID) {
        return control;
      }
    }
    return null;
  }

  Future<void> _choosePath(ControlSpec control) async {
    try {
      final selectedPath =
          await _BundleHomePageState._pathPickerChannel.invokeMethod<String>(
        'pickPath',
        {'kind': _prefersDirectoryPicker(control) ? 'directory' : 'file'},
      );
      if (!mounted || selectedPath == null) {
        return;
      }
      setState(() {
        _fieldValues[control.id] = selectedPath;
        _fieldVersions[control.id] = (_fieldVersions[control.id] ?? 0) + 1;
      });
      _fieldValueChanged(control, selectedPath, updateField: false);
    } catch (error) {
      _appendTerminal('Could not choose path: $error');
    }
  }

  Future<void> _chooseConfigFilePath(ControlSpec control) async {
    try {
      final selectedPath =
          await _BundleHomePageState._pathPickerChannel.invokeMethod<String>(
        'pickPath',
        {'kind': 'file'},
      );
      if (!mounted || selectedPath == null) {
        return;
      }
      setState(() {
        _configFilePaths[control.id] = selectedPath;
        final key = 'config-file:${control.id}';
        _fieldVersions[key] = (_fieldVersions[key] ?? 0) + 1;
      });
      _configFilePathChanged(control, selectedPath);
      await _loadConfig(control);
    } catch (error) {
      _appendTerminal('Could not choose settings file: $error');
    }
  }

  Future<void> _chooseConfigSettingPath(
    String controlID,
    ConfigSettingSpec setting,
  ) async {
    try {
      final selectedPath =
          await _BundleHomePageState._pathPickerChannel.invokeMethod<String>(
        'pickPath',
        {
          'kind': _prefersDirectoryPickerFor(
                  setting.id, setting.label, setting.placeholder)
              ? 'directory'
              : 'file'
        },
      );
      if (!mounted || selectedPath == null) {
        return;
      }
      final settingKey = '$controlID.${setting.id}';
      setState(() {
        _configValues[settingKey] = selectedPath;
        _fieldVersions[settingKey] = (_fieldVersions[settingKey] ?? 0) + 1;
      });
      _configSettingChanged(controlID, setting, selectedPath);
    } catch (error) {
      _appendTerminal('Could not choose path: $error');
    }
  }

  IconData _pathPickerIcon(ControlSpec control) =>
      _prefersDirectoryPicker(control) ? Icons.folder_open : Icons.file_open;

  bool _prefersDirectoryPicker(ControlSpec control) {
    return _prefersDirectoryPickerFor(
      control.id,
      control.label,
      control.placeholder,
    );
  }

  bool _prefersDirectoryPickerFor(
    String rawID,
    String rawLabel,
    String? rawPlaceholder,
  ) {
    final id = rawID.toLowerCase();
    final label = rawLabel.toLowerCase();
    final placeholder = rawPlaceholder?.toLowerCase() ?? '';
    return id.endsWith('_dir') ||
        id.endsWith('_folder') ||
        id.endsWith('_library') ||
        id == 'ref_path' ||
        label.contains('directory') ||
        label.contains('folder') ||
        label.contains('library') ||
        placeholder.contains('directory') ||
        placeholder.contains('folder');
  }

  Future<void> openBundleWorkspace() async {
    try {
      await _BundleHomePageState._pathPickerChannel.invokeMethod<void>(
        'openPath',
        {'path': bundleRoot},
      );
      _appendTerminal('[bundle] Opened workspace: $bundleRoot');
    } catch (error) {
      if (Platform.isMacOS) {
        try {
          final result = await Process.run('open', [bundleRoot]);
          if (result.exitCode == 0) {
            _appendTerminal('[bundle] Opened workspace: $bundleRoot');
            return;
          }
          _appendTerminal(
              '[bundle:error] open exited ${result.exitCode}: ${result.stderr}');
        } catch (fallbackError) {
          _appendTerminal('[bundle:error] $fallbackError');
        }
        return;
      }
      _appendTerminal('[bundle] Workspace path: $bundleRoot');
    }
  }

  void _startBundleHotReloadIfEnabled() {
    const enabled =
        bool.fromEnvironment('GFC_FLUTTER_HOT_RELOAD', defaultValue: false);
    if (!enabled || _bundleWatchSubscriptions.isNotEmpty) {
      return;
    }
    final entities = [
      File(_joinPath(bundleRoot, 'manifest.json')),
      Directory(_joinPath(bundleRoot, 'pages')),
      Directory(_joinPath(bundleRoot, 'strings')),
    ];
    for (final entity in entities) {
      if (!entity.existsSync()) {
        continue;
      }
      _bundleWatchSubscriptions.add(entity.watch().listen((event) {
        if (!_isReloadableBundlePath(event.path)) {
          return;
        }
        _hotReloadTimer?.cancel();
        _hotReloadTimer = Timer(const Duration(milliseconds: 250), () async {
          final code = _bundleState.localizationCode ??
              _manifest?.defaultLocalizationCode ??
              'en';
          await _reloadLocalizedManifest(code);
          final manifest = _manifest;
          if (manifest != null) {
            await _refreshDataSources(manifest, force: true);
          }
        });
      }));
    }
    _appendTerminal(
        '[bundle] Hot reload enabled for manifest, pages, strings.');
  }

  bool _isReloadableBundlePath(String path) =>
      path.endsWith('.json') || path.endsWith('.toml');
}

String _joinPath(String first, String second) =>
    first.endsWith(Platform.pathSeparator)
        ? '$first$second'
        : '$first${Platform.pathSeparator}$second';
