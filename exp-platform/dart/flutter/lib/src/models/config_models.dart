part of '../models.dart';

class ConfigFileSpec {
  const ConfigFileSpec({
    required this.path,
    this.format = 'toml',
    this.bootstrap,
  });

  final String path;
  final String format;
  final ConfigBootstrapSpec? bootstrap;

  factory ConfigFileSpec.fromJson(Map<String, Object?> json) => ConfigFileSpec(
        path: stringValue(json['path']),
        format: optionalString(json['format']) ?? 'toml',
        bootstrap: json['bootstrap'] == null
            ? null
            : ConfigBootstrapSpec.fromJson(json['bootstrap']),
      );
}

class ConfigBootstrapSpec {
  const ConfigBootstrapSpec({this.mode = 'createIfMissing', this.script});

  final String mode;
  final ConfigBootstrapScriptSpec? script;

  factory ConfigBootstrapSpec.fromJson(Object? json) {
    if (json is bool) {
      return ConfigBootstrapSpec(mode: json ? 'createIfMissing' : 'none');
    }
    if (json is String) {
      return ConfigBootstrapSpec(mode: json);
    }
    if (json is Map) {
      final map = json.map((key, value) => MapEntry('$key', value));
      return ConfigBootstrapSpec(
        mode: optionalString(map['mode']) ?? 'createIfMissing',
        script: map['script'] is Map
            ? ConfigBootstrapScriptSpec.fromJson((map['script']! as Map)
                .map((key, value) => MapEntry('$key', value)))
            : null,
      );
    }
    return const ConfigBootstrapSpec();
  }
}

class ConfigBootstrapScriptSpec {
  const ConfigBootstrapScriptSpec({
    required this.path,
    this.arguments = const [],
    this.environment = const {},
    this.workingDirectory,
  });

  final String path;
  final List<String> arguments;
  final Map<String, String> environment;
  final String? workingDirectory;

  factory ConfigBootstrapScriptSpec.fromJson(Map<String, Object?> json) =>
      ConfigBootstrapScriptSpec(
        path: stringValue(json['path']),
        arguments: listOfStrings(json['arguments']),
        environment: mapOfStrings(json['environment']),
        workingDirectory: optionalString(json['workingDirectory']),
      );
}
