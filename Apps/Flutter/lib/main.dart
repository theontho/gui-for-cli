import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/bundle_loader.dart';
import 'src/bundle_paths.dart';
import 'src/config_io.dart';
import 'src/data_source_runner.dart';
import 'src/models.dart';
import 'src/rendering.dart';
import 'src/terminal_model.dart';

part 'src/widgets.dart';
part 'src/startup_benchmark.dart';
part 'src/state_config.dart';
part 'src/action_runtime.dart';
part 'src/data_sources.dart';
part 'src/data_source_widgets.dart';
part 'src/setup_runtime.dart';
part 'src/sidebar.dart';
part 'src/settings_widgets.dart';
part 'src/text_direction.dart';
part 'src/terminal.dart';

final ValueNotifier<ThemeMode> _appThemeMode = ValueNotifier(ThemeMode.system);

void main(List<String> args) {
  final startupBenchmark = FlutterStartupBenchmark.fromArgs(args);
  runApp(GUIForCLIFlutterApp(startupBenchmark: startupBenchmark));
  WidgetsBinding.instance.addPostFrameCallback(
    (_) => startupBenchmark.markFirstFrame(),
  );
}

class GUIForCLIFlutterApp extends StatelessWidget {
  const GUIForCLIFlutterApp({super.key, required this.startupBenchmark});

  final FlutterStartupBenchmark startupBenchmark;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
        valueListenable: _appThemeMode,
        builder: (context, themeMode, _) => MaterialApp(
          title: 'GUI for CLI Flutter',
          themeMode: themeMode,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.indigo,
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
          ),
          home: BundleHomePage(startupBenchmark: startupBenchmark),
        ),
      );
}

class BundleHomePage extends StatefulWidget {
  const BundleHomePage({super.key, required this.startupBenchmark});

  final FlutterStartupBenchmark startupBenchmark;

  @override
  State<BundleHomePage> createState() => _BundleHomePageState();
}

class _BundleHomePageState extends State<BundleHomePage> {
  late final String repoRoot = resolveRepoRoot();
  late final String bundleRoot = resolveBundleRoot(repoRoot);
  late final Future<BundleManifest> _manifestFuture = BundleLoader(
    repoRoot: repoRoot,
    bundleRoot: bundleRoot,
  ).load();
  static const _pathPickerChannel = MethodChannel('gui_for_cli/path_picker');
  final _terminalTabs = <FlutterTerminalTab>[FlutterTerminalTab.main()];
  final _runningProcesses = <String, Process>{};
  final _runningCommandCounts = <String, int>{};
  final _cancelledTerminalTabIDs = <String>{};
  final _bundleWatchSubscriptions = <StreamSubscription<FileSystemEvent>>[];
  Timer? _hotReloadTimer;
  BundleManifest? _manifest;
  BundlePage? _selectedPage;
  String _selectedTerminalTabID = FlutterTerminalTab.mainTabID;
  Map<String, String> _fieldValues = {};
  Map<String, String> _configValues = {};
  Map<String, String> _configFilePaths = {};
  Map<String, Set<String>> _checkedOptions = {};
  Map<String, String> _dataValues = {};
  final _dynamicControlData = <String, DataSourcePayload>{};
  final _dynamicSettingOptions = <String, List<ControlOption>>{};
  final _dataSourceErrors = <String, String>{};
  final _loadingDataSources = <String>{};
  final _setupStatuses = <String, String>{};
  final _fieldVersions = <String, int>{};
  FlutterBundleState _bundleState = FlutterBundleState();
  double _sidebarWidth = 260;
  bool _dataSourcesLoaded = false;
  bool _runtimeInitialized = false;
  bool _setupRunning = false;

  @override
  void dispose() {
    for (final subscription in _bundleWatchSubscriptions) {
      subscription.cancel();
    }
    _hotReloadTimer?.cancel();
    for (final process in _runningProcesses.values) {
      process.kill();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<BundleManifest>(
        future: _manifestFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Scaffold(
              appBar: AppBar(title: const Text('GUI for CLI Flutter')),
              body: Padding(
                padding: const EdgeInsets.all(24),
                child:
                    SelectableText('Could not load bundle:\n${snapshot.error}'),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          _initialize(snapshot.data!);
          return Scaffold(
            appBar: AppBar(title: Text(_manifest!.displayName)),
            body: Directionality(
              textDirection: _bundleTextDirection,
              child: Row(
                children: [
                  _Sidebar(
                    manifest: _manifest!,
                    bundleRoot: bundleRoot,
                    selectedPage: _selectedPage!,
                    iconSet: _bundleState.iconSet,
                    width: _sidebarWidth,
                    onSelected: _selectPage,
                    onWidthChanged: _setSidebarWidth,
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(
                          child:
                              _PageView(page: _selectedPage!, renderer: this),
                        ),
                        _TerminalPane(renderer: this),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );

  void _initialize(BundleManifest manifest) {
    if (_manifest != null) {
      return;
    }
    _manifest = manifest;
    _selectedPage = manifest.pages.firstWhere(
      (page) => page.id != 'settings',
      orElse: () => manifest.pages.first,
    );
    _fieldValues = initialFieldValues(manifest);
    _configValues = initialConfigValues(manifest);
    _configFilePaths = initialConfigFilePaths(manifest, _bundleState);
    _checkedOptions = initialCheckedOptions(manifest);
    _setupStatuses
      ..clear()
      ..addEntries(
        manifest.setup.steps.map((step) => MapEntry(step.id, 'pending')),
      );
    _terminalTabs[0].lines
      ..clear()
      ..add('Loaded ${manifest.displayName} from $bundleRoot');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_runtimeInitialized) {
        _loadRuntimeStateAndData(manifest);
      }
    });
  }

  RenderContext renderContext({Map<String, String> rowValues = const {}}) =>
      RenderContext(
        bundleRootPath: bundleRoot,
        homePath: Platform.environment['USERPROFILE'] ??
            Platform.environment['HOME'] ??
            Directory.current.path,
        fieldValues: _fieldValues,
        configValues: _configValuesForContext(),
        checkedOptions: _checkedOptions.map((key, value) {
          final items = value.toList()..sort();
          return MapEntry(key, items.join(','));
        }),
        dataValues: _dataValues,
        rowValues: rowValues,
      );

  Map<String, String> _configValuesForContext() {
    final values = <String, String>{..._configValues};
    final manifest = _manifest;
    if (manifest != null) {
      for (final control in configEditorControls(manifest)) {
        for (final setting in control.settings) {
          final value = configSettingValue(control, setting);
          values[setting.id] = value;
          values[setting.key] = value;
        }
      }
    }
    return {...values, ..._fieldValues};
  }

  Widget renderControl(ControlSpec control) {
    final effectiveControl = _effectiveControl(control);
    final tooltip = control.tooltip;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Semantics(
        container: true,
        label: effectiveControl.label,
        hint: tooltip,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              effectiveControl.label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (tooltip != null)
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 6),
                child: Text(
                  tooltip,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (_dataSourceErrors[control.id] != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _InlineDataSourceError(
                  message: _dataSourceErrors[control.id]!,
                  onRetry: retryDataSources,
                ),
              ),
            if (_loadingDataSources.contains(control.id))
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: _DataSourceLoadingLabel(),
              ),
            _controlBody(effectiveControl),
          ],
        ),
      ),
    );
  }

  Widget renderActions(List<ActionSpec> actions, RenderContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final action in actions.where(
            (action) => isActionVisible(action, context),
          ))
            _ActionButton(
              action: action,
              context: context,
              isRunning:
                  _isCommandRunning(displayCommand(action.command, context)),
              onRun: () => _requestRunAction(action, context),
            ),
        ],
      );

  Widget _controlBody(ControlSpec control) => switch (control.kind) {
        'text' || 'path' => TextFormField(
            key: ValueKey('${control.id}:${_fieldVersions[control.id] ?? 0}'),
            initialValue: _fieldValues[control.id] ?? control.value ?? '',
            decoration: InputDecoration(
              hintText: control.placeholder,
              border: const OutlineInputBorder(),
              suffixIcon: control.kind == 'path'
                  ? IconButton(
                      tooltip: 'Choose path',
                      icon: Icon(_pathPickerIcon(control)),
                      onPressed: () => _choosePath(control),
                    )
                  : null,
            ),
            onChanged: (value) => _fieldValueChanged(control, value),
          ),
        'dropdown' => DropdownButtonFormField<String>(
            initialValue: _dropdownValue(control),
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: [
              for (final option in control.options)
                DropdownMenuItem(
                    value: option.id, child: Text(_optionTitle(option))),
            ],
            onChanged: (value) => _fieldValueChanged(control, value ?? ''),
          ),
        'toggle' => SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(control.label),
            value: (_fieldValues[control.id] ?? control.value ?? '') == 'true',
            onChanged: (value) => _fieldValueChanged(control, '$value'),
          ),
        'checkboxGroup' => _CheckboxGroup(
            control: control,
            selected: _checkedOptions[control.id] ?? <String>{},
            onChanged: (selected) => _checkedOptionsChanged(control, selected),
          ),
        'infoGrid' => Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in control.options)
                Chip(label: Text(_optionTitle(option))),
            ],
          ),
        'libraryList' => _LibraryList(control: control, renderer: this),
        'configEditor' => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (control.configFile != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _configFilePathBody(control),
                ),
              for (final setting in control.settings)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _configSettingBody(control.id, setting),
                ),
            ],
          ),
        _ => Text('Unsupported control kind: ${control.kind}'),
      };

  String? _dropdownValue(ControlSpec control) {
    final selectedOptions = control.options
        .where((option) => option.selected)
        .map((option) => option.id);
    final value = _fieldValues[control.id] ??
        control.value ??
        (selectedOptions.isEmpty ? null : selectedOptions.first);
    return control.options.any((option) => option.id == value) ? value : null;
  }

  Widget _configSettingBody(String controlID, ConfigSettingSpec setting) {
    final settingKey = '$controlID.${setting.id}';
    final settingOptions =
        _dynamicSettingOptions[settingKey] ?? setting.options;
    final value = _configValues[settingKey] ?? setting.value ?? '';
    return switch (setting.kind) {
      'dropdown' => DropdownButtonFormField<String>(
          initialValue:
              settingOptions.any((option) => option.id == value) ? value : null,
          decoration: InputDecoration(
            labelText: setting.label,
            hintText: setting.placeholder,
            border: const OutlineInputBorder(),
          ),
          items: [
            for (final option in settingOptions)
              DropdownMenuItem(
                value: option.id,
                child: Text(_optionTitle(option)),
              ),
          ],
          onChanged: (selected) =>
              _configSettingChanged(controlID, setting, selected ?? ''),
        ),
      'toggle' => SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(setting.label),
          subtitle: setting.tooltip == null ? null : Text(setting.tooltip!),
          value: value == 'true',
          onChanged: (selected) =>
              _configSettingChanged(controlID, setting, '$selected'),
        ),
      'path' || 'text' => TextFormField(
          key: ValueKey('$settingKey:${_fieldVersions[settingKey] ?? 0}'),
          initialValue: value,
          decoration: InputDecoration(
            labelText: setting.label,
            hintText: setting.placeholder,
            helperText: setting.tooltip,
            border: const OutlineInputBorder(),
            suffixIcon: setting.kind == 'path'
                ? IconButton(
                    tooltip: 'Choose path',
                    icon: const Icon(Icons.folder_open),
                    onPressed: () =>
                        _chooseConfigSettingPath(controlID, setting),
                  )
                : null,
          ),
          onChanged: (changed) =>
              _configSettingChanged(controlID, setting, changed),
        ),
      _ => Text('Unsupported setting kind: ${setting.kind}'),
    };
  }

  Widget _configFilePathBody(ControlSpec control) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextFormField(
              key: ValueKey(
                'config-file:${control.id}:${_fieldVersions["config-file:${control.id}"] ?? 0}',
              ),
              initialValue: _configFilePaths[control.id] ??
                  control.configFile?.path ??
                  '',
              decoration: const InputDecoration(
                labelText: 'Settings file',
                hintText: 'config/settings.toml',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => _configFilePathChanged(control, value),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Choose settings file',
            icon: const Icon(Icons.file_open),
            onPressed: () => _chooseConfigFilePath(control),
          ),
          TextButton.icon(
            onPressed: () => _loadConfig(control),
            icon: const Icon(Icons.refresh),
            label: const Text('Load'),
          ),
        ],
      );
}
