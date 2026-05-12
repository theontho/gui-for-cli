import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'bundle_paths.dart';
import 'models.dart';
import 'rendering.dart';

class DataSourceRunner {
  const DataSourceRunner({required this.bundleRoot});

  static const timeout = Duration(seconds: 15);

  final String bundleRoot;

  Future<DataSourcePayload> load(
      DataSourceSpec dataSource, RenderContext context) async {
    final executable = _resolve(dataSource.path, context, mustExist: true);
    final arguments = dataSource.arguments
        .map((argument) => interpolate(argument, context))
        .toList();
    final workingDirectory = dataSource.workingDirectory == null
        ? bundleRoot
        : _resolve(dataSource.workingDirectory!, context, mustExist: false);
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

    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      runInShell: false,
    );
    final stdout = process.stdout.transform(systemEncoding.decoder).join();
    final stderr = process.stderr.transform(systemEncoding.decoder).join();
    final int exitCode;
    try {
      exitCode = await process.exitCode.timeout(timeout);
    } on TimeoutException {
      process.kill();
      await Future.wait<String>([
        stdout.catchError((_) => ''),
        stderr.catchError((_) => ''),
      ]).timeout(
        const Duration(seconds: 2),
        onTimeout: () => const ['', ''],
      );
      throw TimeoutException(
        'Data source ${dataSource.path} timed out after ${timeout.inSeconds}s',
        timeout,
      );
    }
    final output = await stdout;
    final errorOutput = await stderr;
    if (exitCode != 0) {
      throw ProcessException(
        executable,
        arguments,
        errorOutput.trim().isEmpty ? 'data source failed' : errorOutput.trim(),
        exitCode,
      );
    }
    final decoded = jsonDecode(output);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Data source did not emit a JSON object');
    }
    return DataSourcePayload.fromJson(decoded);
  }

  String _resolve(
    String value,
    RenderContext context, {
    required bool mustExist,
  }) {
    final interpolated = interpolate(value, context);
    return resolveBundledPath(interpolated, bundleRoot, mustExist: mustExist);
  }
}

String _environmentKey(String value) => value
    .split('')
    .map((character) => RegExp(r'[A-Za-z0-9]').hasMatch(character)
        ? character.toUpperCase()
        : '_')
    .join();
