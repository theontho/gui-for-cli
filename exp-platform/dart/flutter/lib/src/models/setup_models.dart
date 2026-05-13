part of '../models.dart';

class CommandSpec {
  const CommandSpec({
    required this.executable,
    required this.arguments,
    this.optionalArguments = const [],
  });

  final String executable;
  final List<String> arguments;
  final List<List<String>> optionalArguments;

  factory CommandSpec.fromJson(Map<String, Object?> json) => CommandSpec(
        executable: stringValue(json['executable']),
        arguments: listOfStrings(json['arguments']),
        optionalArguments: listOfStringLists(json['optionalArguments']),
      );
}

class SetupSpec {
  const SetupSpec({required this.steps});

  final List<SetupStepSpec> steps;

  factory SetupSpec.fromJson(Map<String, Object?> json) => SetupSpec(
        steps: listOfMaps(json['steps']).map(SetupStepSpec.fromJson).toList(),
      );
}

class SetupStepSpec {
  SetupStepSpec({
    required this.id,
    required this.label,
    required this.kind,
    this.value,
    this.workingDirectory,
    this.arguments = const [],
    this.environment = const {},
    this.optional = false,
  });

  final String id;
  final String label;
  final String kind;
  final String? value;
  final String? workingDirectory;
  final List<String> arguments;
  final Map<String, String> environment;
  final bool optional;

  factory SetupStepSpec.fromJson(Map<String, Object?> json) => SetupStepSpec(
        id: stringValue(json['id']),
        label: stringValue(json['label']),
        kind: stringValue(json['kind']),
        value: optionalString(json['value']),
        workingDirectory: optionalString(json['workingDirectory']),
        arguments: listOfStrings(json['arguments']),
        environment: mapOfStrings(json['environment']),
        optional: json['optional'] == true,
      );
}
