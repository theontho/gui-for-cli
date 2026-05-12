import 'dart:convert';
import 'dart:io';

import 'bundle_paths.dart';
import 'models.dart';
import 'rendering.dart';

part 'config_io/bootstrap.dart';
part 'config_io/localization_options.dart';
part 'config_io/state.dart';
part 'config_io/toml.dart';

class InitialConfigValues {
  const InitialConfigValues({required this.values, required this.messages});

  final Map<String, String> values;
  final List<String> messages;
}

List<ControlSpec> configEditorControls(BundleManifest manifest) =>
    allControls(manifest)
        .where((control) => control.kind == 'configEditor')
        .toList();

String configValueKey(ControlSpec control, ConfigSettingSpec setting) =>
    '${control.id}.${setting.id}';

Map<String, String> initialConfigFilePaths(
  BundleManifest manifest,
  FlutterBundleState state,
) {
  final paths = <String, String>{};
  for (final control in configEditorControls(manifest)) {
    final configFile = control.configFile;
    if (configFile == null) {
      continue;
    }
    paths[control.id] = state.configFilePaths[control.id] ?? configFile.path;
  }
  return paths;
}

Future<List<String>> bootstrapConfigFiles({
  required BundleManifest manifest,
  required String bundleRoot,
  required Map<String, String> configFilePaths,
}) async {
  final messages = <String>[];
  for (final control in configEditorControls(manifest)) {
    final configFile = control.configFile;
    final bootstrap = configFile?.bootstrap;
    if (configFile == null || bootstrap == null || bootstrap.mode == 'none') {
      continue;
    }
    if (configFile.format != 'toml') {
      messages.add(
          '[config:error] Unsupported config format: ${configFile.format}');
      continue;
    }
    final defaultURL = resolveConfigFilePath(
        configFilePaths[control.id] ?? configFile.path, bundleRoot);
    final document = await _bootstrapDocument(
      control: control,
      bundleRoot: bundleRoot,
      defaultPath: defaultURL.toFilePath(),
      script: bootstrap.script,
    );
    final file = File(document.path);
    final exists = await file.exists();
    final defaultValues = parseFlatToml(document.contents);
    switch (bootstrap.mode) {
      case 'createIfMissing':
        if (!exists) {
          await file.parent.create(recursive: true);
          await file.writeAsString(document.contents);
          messages.add(
              '[config] Created ${defaultValues.length} setting(s) at ${file.path}');
        }
        break;
      case 'mergeMissing':
        final existing = exists
            ? parseFlatToml(await file.readAsString())
            : <String, String>{};
        final missing = Map.fromEntries(
          defaultValues.entries
              .where((entry) => !existing.containsKey(entry.key)),
        );
        if (missing.isNotEmpty) {
          await file.parent.create(recursive: true);
          await file
              .writeAsString(serializeFlatToml({...existing, ...missing}));
          messages.add(
              '[config] Added ${missing.length} missing setting(s) to ${file.path}');
        }
        break;
      default:
        messages.add(
            '[config:error] Unsupported bootstrap mode: ${bootstrap.mode}');
    }
  }
  return messages;
}

Future<InitialConfigValues> loadInitialConfigValues({
  required BundleManifest manifest,
  required String bundleRoot,
  required Map<String, String> configFilePaths,
}) async {
  final values = initialConfigValues(manifest);
  final messages = <String>[];
  for (final control in configEditorControls(manifest)) {
    final configFile = control.configFile;
    final rawPath = configFilePaths[control.id];
    if (configFile == null || rawPath == null) {
      continue;
    }
    final file = File(resolveConfigFilePath(rawPath, bundleRoot).toFilePath());
    if (!await file.exists()) {
      continue;
    }
    try {
      final fileValues = parseFlatToml(await file.readAsString());
      for (final setting in control.settings) {
        final value = fileValues[setting.key];
        if (value != null) {
          values[configValueKey(control, setting)] = value;
        }
      }
      messages.add('[config] Loaded settings from ${file.path}');
    } on Object catch (error) {
      messages.add('[config:error] Could not load ${file.path}: $error');
    }
  }
  return InitialConfigValues(values: values, messages: messages);
}

Map<String, String> initialFieldValuesFromStateAndConfig(
  BundleManifest manifest,
  Map<String, String> configValues,
  FlutterBundleState state,
) {
  final values = initialFieldValues(manifest);
  for (final control in allControls(manifest)) {
    if (!_persistsFieldValue(control.kind)) {
      continue;
    }
    if (configSettingBindings(manifest, control.id).isEmpty &&
        state.fieldValues[control.id] != null) {
      values[control.id] = state.fieldValues[control.id]!;
    }
  }
  for (final control in configEditorControls(manifest)) {
    for (final setting in control.settings) {
      final value =
          configValues[configValueKey(control, setting)] ?? setting.value ?? '';
      if (values.containsKey(setting.key)) {
        values[setting.key] = value;
      }
      if (values.containsKey(setting.id)) {
        values[setting.id] = value;
      }
    }
  }
  return values;
}

Map<String, Set<String>> initialCheckedOptionsFromStateAndConfig(
  BundleManifest manifest,
  Map<String, String> configValues,
  FlutterBundleState state,
) {
  final values = initialCheckedOptions(manifest);
  for (final control in allControls(manifest)
      .where((control) => control.kind == 'checkboxGroup')) {
    final bindings = configSettingBindings(manifest, control.id);
    if (bindings.isNotEmpty) {
      final binding = bindings.first;
      values[control.id] =
          (configValues[configValueKey(binding.control, binding.setting)] ??
                  binding.setting.value ??
                  '')
              .split(',')
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toSet();
    } else if (state.checkedOptions[control.id] != null) {
      values[control.id] = state.checkedOptions[control.id]!.toSet();
    }
  }
  return values;
}

List<ConfigSettingBinding> configSettingBindings(
  BundleManifest manifest,
  String fieldID,
) =>
    [
      for (final control in configEditorControls(manifest))
        for (final setting in control.settings)
          if (setting.id == fieldID || setting.key == fieldID)
            ConfigSettingBinding(control: control, setting: setting),
    ];

String? boundFieldKey(
  Map<String, String> fieldValues,
  ConfigSettingSpec setting,
) {
  if (fieldValues.containsKey(setting.key)) {
    return setting.key;
  }
  if (fieldValues.containsKey(setting.id)) {
    return setting.id;
  }
  return null;
}

Future<Map<String, String>> loadConfigFile({
  required ControlSpec control,
  required String path,
  required String bundleRoot,
}) async {
  final file = File(resolveConfigFilePath(path, bundleRoot).toFilePath());
  if (!await file.exists()) {
    throw FileSystemException('Settings file does not exist', file.path);
  }
  final values = parseFlatToml(await file.readAsString());
  return {
    for (final setting in control.settings)
      setting.key: values[setting.key] ?? setting.value ?? '',
  };
}

Future<void> saveConfigFile({
  required ControlSpec control,
  required String path,
  required String bundleRoot,
  required Map<String, String> configValues,
}) async {
  final file = File(resolveConfigFilePath(path, bundleRoot).toFilePath());
  final existing = await file.exists()
      ? parseFlatToml(await file.readAsString())
      : <String, String>{};
  for (final setting in control.settings) {
    existing[setting.key] =
        configValues[configValueKey(control, setting)] ?? setting.value ?? '';
  }
  await file.parent.create(recursive: true);
  await file.writeAsString(serializeFlatToml(existing));
}

FlutterBundleState loadBundleState(
    String bundleRoot, void Function(String) log) {
  final file = File(_join(bundleRoot, 'state.json'));
  if (!file.existsSync()) {
    return FlutterBundleState();
  }
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is Map<String, Object?>) {
      return FlutterBundleState.fromJson(decoded);
    }
    log('[state:error] Bundle state was not a JSON object: ${file.path}');
  } on Object catch (error) {
    log('[state:error] Could not load ${file.path}: $error');
  }
  return FlutterBundleState();
}

Future<void> saveBundleState(
    String bundleRoot, FlutterBundleState state) async {
  final file = File(_join(bundleRoot, 'state.json'));
  await file.parent.create(recursive: true);
  const encoder = JsonEncoder.withIndent('  ');
  await file.writeAsString('${encoder.convert(state.toJson())}\n');
}

Uri resolveConfigFilePath(String path, String bundleRoot) {
  final expanded = expandConfigPath(path, bundleRoot);
  if (isAbsoluteFilePath(expanded)) {
    return Uri.file(expanded);
  }
  return Uri.file(_join(bundleRoot, expanded));
}

String expandConfigPath(
  String path,
  String bundleRoot, {
  String? configPath,
}) {
  final home = Platform.environment['USERPROFILE'] ??
      Platform.environment['HOME'] ??
      Directory.current.path;
  final configHome =
      Platform.environment['XDG_CONFIG_HOME'] ?? _join(home, '.config');
  final applicationSupport = Platform.isMacOS
      ? _join(_join(home, 'Library'), 'Application Support')
      : configHome;
  final configDir = configPath == null ? '' : File(configPath).parent.path;
  return path
      .replaceAll('{{bundleRoot}}', bundleRoot)
      .replaceAll('{{bundleWorkspace}}', bundleRoot)
      .replaceAll('{{home}}', home)
      .replaceAll('{{configHome}}', configHome)
      .replaceAll('{{userConfig}}', configHome)
      .replaceAll('{{applicationSupport}}', applicationSupport)
      .replaceAll('{{appConfig}}', applicationSupport)
      .replaceAll('{{configPath}}', configPath ?? '')
      .replaceAll('{{configDir}}', configDir)
      .replaceFirst(RegExp(r'^~/'), '$home/');
}

bool _persistsFieldValue(String kind) =>
    kind == 'text' || kind == 'path' || kind == 'dropdown' || kind == 'toggle';

Map<String, List<String>> _mapOfStringLists(Object? value) => value is Map
    ? value.map(
        (key, value) => MapEntry(
          '$key',
          value is List ? value.map((item) => '$item').toList() : <String>[],
        ),
      )
    : {};

String _join(String first, String second) =>
    first.endsWith(Platform.pathSeparator)
        ? '$first$second'
        : '$first${Platform.pathSeparator}$second';

class ConfigSettingBinding {
  const ConfigSettingBinding({required this.control, required this.setting});

  final ControlSpec control;
  final ConfigSettingSpec setting;
}
