// ignore_for_file: invalid_use_of_protected_member

part of '../main.dart';

extension _BundleHomePageStateDataSources on _BundleHomePageState {
  ControlSpec _effectiveControl(ControlSpec control) {
    final payload = _dynamicControlData[control.id];
    if (payload == null) {
      return control;
    }
    return control.copyWith(
      options: payload.options,
      rows: payload.rows,
      rowActions: payload.rowActions,
    );
  }

  Future<void> _refreshDataSources(
    BundleManifest manifest, {
    bool force = false,
    bool markContentReady = false,
  }) async {
    if (_dataSourcesLoaded && !force) {
      if (markContentReady) {
        widget.startupBenchmark.markContentReady();
      }
      return;
    }
    _dataSourcesLoaded = true;
    final runner = DataSourceRunner(bundleRoot: bundleRoot);
    for (final page in manifest.pages) {
      for (final section in page.sections) {
        if (section.dataSource != null) {
          await _loadDataSource(
            runner: runner,
            key: section.id,
            dataSource: section.dataSource!,
            apply: (payload) {
              if (payload.values != null) {
                _dataValues = {..._dataValues, ...payload.values!};
              }
            },
          );
        }
        for (final control in section.controls) {
          if (control.dataSource != null) {
            await _loadDataSource(
              runner: runner,
              key: control.id,
              dataSource: control.dataSource!,
              apply: (payload) {
                _dynamicControlData[control.id] = payload;
                _selectDefaultOptionIfNeeded(control.id, payload.options);
              },
            );
          }
          for (final setting in control.settings) {
            if (setting.dataSource != null) {
              final settingKey = '${control.id}.${setting.id}';
              await _loadDataSource(
                runner: runner,
                key: settingKey,
                dataSource: setting.dataSource!,
                apply: (payload) {
                  if (payload.options != null) {
                    _dynamicSettingOptions[settingKey] = payload.options!;
                    _selectDefaultConfigOptionIfNeeded(
                      control,
                      setting,
                      payload.options!,
                    );
                  }
                },
              );
            }
          }
        }
      }
    }
    if (markContentReady) {
      widget.startupBenchmark.markContentReady();
    }
  }

  void _selectDefaultOptionIfNeeded(
    String controlID,
    List<ControlOption>? options,
  ) {
    if (options == null || options.isEmpty) {
      return;
    }
    final currentValue = _fieldValues[controlID]?.trim() ?? '';
    if (currentValue.isNotEmpty &&
        options.any((option) => option.id == currentValue)) {
      return;
    }
    final defaultOption = options.firstWhere((option) => option.selected,
        orElse: () => options.first);
    _fieldValues[controlID] = defaultOption.id;
  }

  void _selectDefaultConfigOptionIfNeeded(
    ControlSpec control,
    ConfigSettingSpec setting,
    List<ControlOption> options,
  ) {
    if (options.isEmpty) {
      return;
    }
    final key = configValueKey(control, setting);
    final currentValue = _configValues[key]?.trim() ?? '';
    if (currentValue.isNotEmpty &&
        options.any((option) => option.id == currentValue)) {
      return;
    }
    final defaultOption = options.firstWhere((option) => option.selected,
        orElse: () => options.first);
    _configValues[key] = defaultOption.id;
  }

  Future<void> _loadDataSource({
    required DataSourceRunner runner,
    required String key,
    required DataSourceSpec dataSource,
    required void Function(DataSourcePayload payload) apply,
  }) async {
    try {
      final payload = await runner.load(dataSource, renderContext());
      if (!mounted) {
        return;
      }
      setState(() {
        _dataSourceErrors.remove(key);
        apply(payload);
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(
          () => _dataSourceErrors[key] = 'Could not load data source: $error');
    }
  }
}
