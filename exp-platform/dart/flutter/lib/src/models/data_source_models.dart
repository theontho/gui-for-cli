part of '../models.dart';

class DataSourceSpec {
  const DataSourceSpec({
    required this.path,
    this.arguments = const [],
    this.workingDirectory,
    this.environment = const {},
  });

  final String path;
  final List<String> arguments;
  final String? workingDirectory;
  final Map<String, String> environment;

  factory DataSourceSpec.fromJson(Map<String, Object?> json) => DataSourceSpec(
        path: stringValue(json['path']),
        arguments: listOfStrings(json['arguments']),
        workingDirectory: optionalString(json['workingDirectory']),
        environment: mapOfStrings(json['environment']),
      );
}

class DataSourcePayload {
  const DataSourcePayload({
    this.options,
    this.rows,
    this.rowActions,
    this.values,
  });

  final List<ControlOption>? options;
  final List<ListRowSpec>? rows;
  final List<ActionSpec>? rowActions;
  final Map<String, String>? values;

  factory DataSourcePayload.fromJson(Map<String, Object?> json) =>
      DataSourcePayload(
        options: json['options'] == null
            ? null
            : listOfMaps(json['options']).map(ControlOption.fromJson).toList(),
        rows: json['rows'] != null
            ? listOfMaps(json['rows']).map(ListRowSpec.fromJson).toList()
            : json['items'] != null
                ? listOfMaps(json['items']).map(ListRowSpec.fromJson).toList()
                : null,
        rowActions: json['rowActions'] != null
            ? listOfMaps(json['rowActions']).map(ActionSpec.fromJson).toList()
            : json['actions'] != null
                ? listOfMaps(json['actions']).map(ActionSpec.fromJson).toList()
                : null,
        values: mapOfStrings(json['values']),
      );
}
