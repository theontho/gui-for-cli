import 'dart:convert';
import 'dart:io';

import 'models.dart';
import 'rendering.dart';

class DataSourceRunner {
  const DataSourceRunner({required this.bundleRoot});

  final String bundleRoot;

  Future<DataSourcePayload> load(
      DataSourceSpec dataSource, RenderContext context) async {
    final executable = _resolve(dataSource.path, context);
    final arguments = dataSource.arguments
        .map((argument) => interpolate(argument, context))
        .toList();
    final workingDirectory = dataSource.workingDirectory == null
        ? bundleRoot
        : _resolve(dataSource.workingDirectory!, context);
    final environment = {
      ...Platform.environment,
      'GUI_FOR_CLI_BUNDLE_ROOT': bundleRoot,
      'GUI_FOR_CLI_BUNDLE_WORKSPACE': bundleRoot,
      'GUI_FOR_CLI_DATA_SOURCE': '1',
      for (final entry in context.fieldValues.entries)
        'GUI_FOR_CLI_FIELD_${_environmentKey(entry.key)}': entry.value,
      for (final entry in context.configValues.entries)
        'GUI_FOR_CLI_CONFIG_${_environmentKey(entry.key)}': entry.value,
      for (final entry in dataSource.environment.entries)
        entry.key: interpolate(entry.value, context),
    };

    final result = await Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      runInShell: false,
    );
    if (result.exitCode != 0) {
      throw ProcessException(
        executable,
        arguments,
        result.stderr.toString().trim().isEmpty
            ? 'data source failed'
            : result.stderr.toString().trim(),
        result.exitCode,
      );
    }
    final decoded = jsonDecode(result.stdout.toString());
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Data source did not emit a JSON object');
    }
    return DataSourcePayload.fromJson(decoded);
  }

  String _resolve(String value, RenderContext context) {
    final interpolated = interpolate(value, context);
    if (interpolated.startsWith('/')) {
      return interpolated;
    }
    return _join(bundleRoot, interpolated);
  }
}

String _environmentKey(String value) => value
    .split('')
    .map((character) => RegExp(r'[A-Za-z0-9]').hasMatch(character)
        ? character.toUpperCase()
        : '_')
    .join();

String _join(String first, String second) =>
    first.endsWith(Platform.pathSeparator)
        ? '$first$second'
        : '$first${Platform.pathSeparator}$second';
