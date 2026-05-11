part of '../config_io.dart';

class FlutterBundleState {
  FlutterBundleState({
    this.localizationCode,
    Map<String, String>? configFilePaths,
    Map<String, String>? fieldValues,
    Map<String, List<String>>? checkedOptions,
    Map<String, String>? dataSourceErrors,
    this.selectedPageID,
    this.setupRun,
    this.iconSet = 'platform',
    this.colorTheme = 'system',
    this.sidebarWidth,
  })  : configFilePaths = configFilePaths ?? {},
        fieldValues = fieldValues ?? {},
        checkedOptions = checkedOptions ?? {},
        dataSourceErrors = dataSourceErrors ?? {};

  String? localizationCode;
  final Map<String, String> configFilePaths;
  final Map<String, String> fieldValues;
  final Map<String, List<String>> checkedOptions;
  final Map<String, String> dataSourceErrors;
  String? selectedPageID;
  FlutterSetupRunState? setupRun;
  String iconSet;
  String colorTheme;
  double? sidebarWidth;

  factory FlutterBundleState.fromJson(Map<String, Object?> json) =>
      FlutterBundleState(
        localizationCode: optionalString(json['localizationCode']),
        configFilePaths: mapOfStrings(json['configFilePaths']),
        fieldValues: mapOfStrings(json['fieldValues']),
        checkedOptions: _mapOfStringLists(json['checkedOptions']),
        dataSourceErrors: mapOfStrings(json['dataSourceErrors']),
        selectedPageID: optionalString(json['selectedPageID']),
        setupRun: json['setupRun'] is Map<String, Object?>
            ? FlutterSetupRunState.fromJson(
                json['setupRun']! as Map<String, Object?>)
            : null,
        iconSet: _allowedString(
          optionalString(json['iconSet']),
          const {'platform', 'emoji'},
          'platform',
        ),
        colorTheme: _allowedString(
          optionalString(json['colorTheme']),
          const {'system', 'light', 'dark'},
          'system',
        ),
        sidebarWidth: json['sidebarWidth'] is num
            ? (json['sidebarWidth']! as num).toDouble()
            : null,
      );

  Map<String, Object?> toJson() => {
        'localizationCode': localizationCode,
        'configFilePaths': configFilePaths,
        'fieldValues': fieldValues,
        'checkedOptions': checkedOptions,
        'dataSourceErrors': dataSourceErrors,
        'selectedPageID': selectedPageID,
        'setupRun': setupRun?.toJson(),
        'iconSet': iconSet,
        'colorTheme': colorTheme,
        if (sidebarWidth != null) 'sidebarWidth': sidebarWidth,
        'webUIFont': 'system',
      };
}

class FlutterSetupRunState {
  const FlutterSetupRunState({
    required this.status,
    this.completedAt,
    this.error,
    this.results = const [],
  });

  final String status;
  final String? completedAt;
  final String? error;
  final List<FlutterSetupStepRunState> results;

  factory FlutterSetupRunState.fromJson(Map<String, Object?> json) =>
      FlutterSetupRunState(
        status: optionalString(json['status']) ?? 'unknown',
        completedAt: optionalString(json['completedAt']),
        error: optionalString(json['error']),
        results: listOfMaps(json['results'])
            .map(FlutterSetupStepRunState.fromJson)
            .toList(),
      );

  Map<String, Object?> toJson() => {
        'status': status,
        if (completedAt != null) 'completedAt': completedAt,
        if (error != null) 'error': error,
        'results': results.map((result) => result.toJson()).toList(),
      };
}

class FlutterSetupStepRunState {
  const FlutterSetupStepRunState({
    required this.id,
    required this.status,
    this.exitCode,
    this.message,
  });

  final String id;
  final String status;
  final int? exitCode;
  final String? message;

  factory FlutterSetupStepRunState.fromJson(Map<String, Object?> json) =>
      FlutterSetupStepRunState(
        id: stringValue(json['id']),
        status: optionalString(json['status']) ?? 'unknown',
        exitCode:
            json['exitCode'] is num ? (json['exitCode']! as num).toInt() : null,
        message: optionalString(json['message']),
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'status': status,
        if (exitCode != null) 'exitCode': exitCode,
        if (message != null) 'message': message,
      };
}

String _allowedString(String? value, Set<String> allowed, String fallback) =>
    value != null && allowed.contains(value) ? value : fallback;
