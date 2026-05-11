part of '../config_io.dart';

Future<_BootstrapDocument> _bootstrapDocument({
  required ControlSpec control,
  required String bundleRoot,
  required String defaultPath,
  required ConfigBootstrapScriptSpec? script,
}) async {
  if (script == null) {
    return _BootstrapDocument(
      path: defaultPath,
      contents: serializeFlatToml({
        for (final setting in control.settings)
          setting.key: setting.value ?? '',
      }),
    );
  }

  final scriptPath = _resolveSafeBundledPath(script.path, bundleRoot);
  final workingDirectory = script.workingDirectory == null
      ? bundleRoot
      : _resolveSafeBundledPath(script.workingDirectory!, bundleRoot,
          mustExist: false);
  final result = await Process.run(
    '/bin/sh',
    [
      scriptPath,
      ...script.arguments.map((argument) =>
          expandConfigPath(argument, bundleRoot, configPath: defaultPath)),
    ],
    workingDirectory: workingDirectory,
    environment: {
      ...Platform.environment,
      'GUI_FOR_CLI_BUNDLE_ROOT': bundleRoot,
      'GUI_FOR_CLI_BUNDLE_WORKSPACE': bundleRoot,
      'GUI_FOR_CLI_CONFIG_PATH': defaultPath,
      'GUI_FOR_CLI_CONFIG_DIR': File(defaultPath).parent.path,
      'GUI_FOR_CLI_CONFIG_CONTROL_ID': control.id,
      'GUI_FOR_CLI_CONFIG_CONTROL_LABEL': control.label,
      'GUI_FOR_CLI_DRY_RUN': '0',
      for (final entry in script.environment.entries)
        entry.key:
            expandConfigPath(entry.value, bundleRoot, configPath: defaultPath),
    },
  );
  if (result.exitCode != 0) {
    throw ProcessException(
      scriptPath,
      script.arguments,
      [result.stdout, result.stderr]
          .where((item) => '$item'.isNotEmpty)
          .join('\n'),
      result.exitCode,
    );
  }
  final decoded = jsonDecode(result.stdout.toString().trim());
  if (decoded is! Map<String, Object?>) {
    throw FormatException(
        'Bootstrap script did not emit a JSON object: $scriptPath');
  }
  final payloadPath = optionalString(decoded['path']);
  return _BootstrapDocument(
    path: payloadPath == null
        ? defaultPath
        : resolveConfigFilePath(payloadPath, bundleRoot).toFilePath(),
    contents: _bootstrapContents(decoded, bundleRoot),
  );
}

String _bootstrapContents(Map<String, Object?> payload, String bundleRoot) {
  final contents = optionalString(payload['contents']);
  if (contents != null) {
    return contents;
  }
  final contentsPath = optionalString(payload['contentsPath']);
  if (contentsPath != null) {
    return File(resolveConfigFilePath(contentsPath, bundleRoot).toFilePath())
        .readAsStringSync();
  }
  final values = mapOfStrings(payload['values']);
  return values.isEmpty ? '' : serializeFlatToml(values);
}

String _resolveSafeBundledPath(String path, String bundleRoot,
    {bool mustExist = true}) {
  if (path.startsWith(Platform.pathSeparator) ||
      path.split('/').contains('..')) {
    throw FormatException('Unsafe bundled path: $path');
  }
  final resolved = path.isEmpty ? bundleRoot : _join(bundleRoot, path);
  if (mustExist &&
      !File(resolved).existsSync() &&
      !Directory(resolved).existsSync()) {
    throw FileSystemException('Missing bundled path', resolved);
  }
  return resolved;
}

class _BootstrapDocument {
  const _BootstrapDocument({required this.path, required this.contents});

  final String path;
  final String contents;
}
