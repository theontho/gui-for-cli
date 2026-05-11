part 'models/action_models.dart';
part 'models/config_models.dart';
part 'models/data_source_models.dart';

class BundleManifest {
  BundleManifest({
    required this.id,
    required this.displayName,
    required this.summary,
    required this.pages,
    this.iconName,
    this.iconEmoji,
    this.iconPath,
    this.defaultLocalizationCode = 'en',
    this.terminalTextDirection = 'ltr',
    this.setup = const SetupSpec(steps: []),
  });

  final String id;
  final String displayName;
  final String summary;
  final String? iconName;
  final String? iconEmoji;
  final String? iconPath;
  final String defaultLocalizationCode;
  final String terminalTextDirection;
  final SetupSpec setup;
  final List<BundlePage> pages;

  factory BundleManifest.fromJson(Map<String, Object?> json) => BundleManifest(
    id: stringValue(json['id']),
    displayName: stringValue(json['displayName']),
    summary: stringValue(json['summary']),
    iconName: optionalString(json['iconName']),
    iconEmoji: optionalString(json['iconEmoji']),
    iconPath: optionalString(json['iconPath']),
    defaultLocalizationCode:
        optionalString(json['defaultLocalizationCode']) ?? 'en',
    terminalTextDirection: normalizedTextDirection(
      optionalString(json['terminalTextDirection']),
    ),
    setup: json['setup'] is Map<String, Object?>
        ? SetupSpec.fromJson(json['setup']! as Map<String, Object?>)
        : const SetupSpec(steps: []),
    pages: listOfMaps(json['pages']).map(BundlePage.fromJson).toList(),
  );

  BundleManifest copyWith({
    String? displayName,
    String? summary,
    SetupSpec? setup,
    List<BundlePage>? pages,
  }) => BundleManifest(
    id: id,
    displayName: displayName ?? this.displayName,
    summary: summary ?? this.summary,
    iconName: iconName,
    iconEmoji: iconEmoji,
    iconPath: iconPath,
    defaultLocalizationCode: defaultLocalizationCode,
    terminalTextDirection: terminalTextDirection,
    setup: setup ?? this.setup,
    pages: pages ?? this.pages,
  );
}

class BundlePage {
  BundlePage({
    required this.id,
    required this.title,
    required this.summary,
    required this.sections,
    this.iconName,
    this.iconEmoji,
    this.sidebarGroup,
  });

  final String id;
  final String title;
  final String summary;
  final String? iconName;
  final String? iconEmoji;
  final String? sidebarGroup;
  final List<PageSection> sections;

  factory BundlePage.fromJson(Map<String, Object?> json) => BundlePage(
    id: stringValue(json['id']),
    title: stringValue(json['title']),
    summary: stringValue(json['summary']),
    iconName: optionalString(json['iconName']),
    iconEmoji: optionalString(json['iconEmoji']),
    sidebarGroup: optionalString(json['sidebarGroup']),
    sections: listOfMaps(json['sections']).map(PageSection.fromJson).toList(),
  );

  BundlePage copyWith({List<PageSection>? sections}) => BundlePage(
    id: id,
    title: title,
    summary: summary,
    iconName: iconName,
    iconEmoji: iconEmoji,
    sidebarGroup: sidebarGroup,
    sections: sections ?? this.sections,
  );
}

class PageSection {
  PageSection({
    required this.id,
    required this.controls,
    required this.actions,
    this.title,
    this.summary,
    this.subtitle,
    this.iconName,
    this.iconEmoji,
    this.dataSource,
  });

  final String id;
  final String? title;
  final String? summary;
  final String? subtitle;
  final String? iconName;
  final String? iconEmoji;
  final DataSourceSpec? dataSource;
  final List<ControlSpec> controls;
  final List<ActionSpec> actions;

  factory PageSection.fromJson(Map<String, Object?> json) => PageSection(
    id: stringValue(json['id']),
    title: optionalString(json['title']),
    summary: optionalString(json['summary']),
    subtitle: optionalString(json['subtitle']),
    iconName: optionalString(json['iconName']),
    iconEmoji: optionalString(json['iconEmoji']),
    dataSource: json['dataSource'] is Map<String, Object?>
        ? DataSourceSpec.fromJson(json['dataSource']! as Map<String, Object?>)
        : null,
    controls: listOfMaps(json['controls']).map(ControlSpec.fromJson).toList(),
    actions: listOfMaps(json['actions']).map(ActionSpec.fromJson).toList(),
  );
}

class ControlSpec {
  ControlSpec({
    required this.id,
    required this.label,
    required this.kind,
    this.value,
    this.placeholder,
    this.tooltip,
    this.options = const [],
    this.columns = const [],
    this.rows = const [],
    this.items = const [],
    this.rowTemplate,
    this.rowActions = const [],
    this.settings = const [],
    this.configFile,
    this.dataSource,
  });

  final String id;
  final String label;
  final String kind;
  final String? value;
  final String? placeholder;
  final String? tooltip;
  final List<ControlOption> options;
  final List<ListColumnSpec> columns;
  final List<ListRowSpec> rows;
  final List<ListItemSpec> items;
  final ListRowSpec? rowTemplate;
  final List<ActionSpec> rowActions;
  final List<ConfigSettingSpec> settings;
  final ConfigFileSpec? configFile;
  final DataSourceSpec? dataSource;

  factory ControlSpec.fromJson(Map<String, Object?> json) => ControlSpec(
    id: stringValue(json['id']),
    label: stringValue(json['label']),
    kind: stringValue(json['kind']),
    value: optionalString(json['value']),
    placeholder: optionalString(json['placeholder']),
    tooltip: optionalString(json['tooltip']),
    options: listOfMaps(json['options']).map(ControlOption.fromJson).toList(),
    columns: listOfMaps(json['columns']).map(ListColumnSpec.fromJson).toList(),
    rows: listOfMaps(json['rows']).map(ListRowSpec.fromJson).toList(),
    items: listOfMaps(json['items']).map(ListItemSpec.fromJson).toList(),
    rowTemplate: json['rowTemplate'] is Map<String, Object?>
        ? ListRowSpec.fromJson(json['rowTemplate']! as Map<String, Object?>)
        : null,
    rowActions: listOfMaps(
      json['rowActions'],
    ).map(ActionSpec.fromJson).toList(),
    settings: listOfMaps(
      json['settings'],
    ).map(ConfigSettingSpec.fromJson).toList(),
    configFile: json['configFile'] is Map<String, Object?>
        ? ConfigFileSpec.fromJson(json['configFile']! as Map<String, Object?>)
        : null,
    dataSource: json['dataSource'] is Map<String, Object?>
        ? DataSourceSpec.fromJson(json['dataSource']! as Map<String, Object?>)
        : null,
  );

  ControlSpec copyWith({
    List<ControlOption>? options,
    List<ListRowSpec>? rows,
    List<ActionSpec>? rowActions,
  }) => ControlSpec(
    id: id,
    label: label,
    kind: kind,
    value: value,
    placeholder: placeholder,
    tooltip: tooltip,
    options: options ?? this.options,
    columns: columns,
    rows: rows ?? this.rows,
    items: rows == null ? items : const [],
    rowTemplate: rowTemplate,
    rowActions: rowActions ?? this.rowActions,
    settings: settings,
    configFile: configFile,
    dataSource: dataSource,
  );
}

class ControlOption {
  ControlOption({
    required this.id,
    required this.title,
    this.selected = false,
    this.status,
    this.group,
  });

  final String id;
  final String title;
  final bool selected;
  final String? status;
  final String? group;

  factory ControlOption.fromJson(Map<String, Object?> json) => ControlOption(
    id: stringValue(json['id']),
    title: stringValue(json['title']),
    selected: json['selected'] == true,
    status: optionalString(json['status']),
    group: optionalString(json['group']),
  );
}

class ListColumnSpec {
  ListColumnSpec({required this.id, required this.title});

  final String id;
  final String title;

  factory ListColumnSpec.fromJson(Map<String, Object?> json) => ListColumnSpec(
    id: stringValue(json['id']),
    title: stringValue(json['title']),
  );
}

class ListItemSpec {
  ListItemSpec(this.values);

  final Map<String, String> values;

  factory ListItemSpec.fromJson(Map<String, Object?> json) {
    final nested = json['values'];
    final source = nested is Map<String, Object?> ? nested : json;
    return ListItemSpec(source.map((key, value) => MapEntry(key, '$value')));
  }
}

class ListRowSpec {
  ListRowSpec({
    this.id,
    this.title,
    this.values = const {},
    this.status,
    this.tooltip,
    this.tags = const [],
  });

  final String? id;
  final String? title;
  final Map<String, String> values;
  final String? status;
  final String? tooltip;
  final List<TagSpec> tags;

  factory ListRowSpec.fromJson(Map<String, Object?> json) => ListRowSpec(
    id: optionalString(json['id']),
    title: optionalString(json['title']),
    values: mapOfStrings(json['values']),
    status: optionalString(json['status']),
    tooltip: optionalString(json['tooltip']),
    tags: listOfMaps(json['tags']).map(TagSpec.fromJson).toList(),
  );
}

class TagSpec {
  TagSpec({required this.id, required this.title, this.style});

  final String id;
  final String title;
  final String? style;

  factory TagSpec.fromJson(Map<String, Object?> json) => TagSpec(
    id: stringValue(json['id']),
    title: stringValue(json['title']),
    style: optionalString(json['style']),
  );
}

class ConfigSettingSpec {
  ConfigSettingSpec({
    required this.id,
    required this.kind,
    required this.key,
    required this.label,
    this.value,
    this.placeholder,
    this.tooltip,
    this.options = const [],
    this.dataSource,
  });

  final String id;
  final String kind;
  final String key;
  final String label;
  final String? value;
  final String? placeholder;
  final String? tooltip;
  final List<ControlOption> options;
  final DataSourceSpec? dataSource;

  factory ConfigSettingSpec.fromJson(
    Map<String, Object?> json,
  ) => ConfigSettingSpec(
    id: stringValue(json['id']),
    kind: stringValue(json['kind']),
    key: stringValue(json['key']),
    label: stringValue(json['label']),
    value: optionalString(json['value']),
    placeholder: optionalString(json['placeholder']),
    tooltip: optionalString(json['tooltip']),
    options: listOfMaps(json['options']).map(ControlOption.fromJson).toList(),
    dataSource: json['dataSource'] is Map<String, Object?>
        ? DataSourceSpec.fromJson(json['dataSource']! as Map<String, Object?>)
        : null,
  );

  ConfigSettingSpec copyWith({List<ControlOption>? options}) =>
      ConfigSettingSpec(
        id: id,
        kind: kind,
        key: key,
        label: label,
        value: value,
        placeholder: placeholder,
        tooltip: tooltip,
        options: options ?? this.options,
        dataSource: dataSource,
      );
}

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
    this.arguments = const [],
    this.environment = const {},
    this.optional = false,
  });

  final String id;
  final String label;
  final String kind;
  final String? value;
  final List<String> arguments;
  final Map<String, String> environment;
  final bool optional;

  factory SetupStepSpec.fromJson(Map<String, Object?> json) => SetupStepSpec(
    id: stringValue(json['id']),
    label: stringValue(json['label']),
    kind: stringValue(json['kind']),
    value: optionalString(json['value']),
    arguments: listOfStrings(json['arguments']),
    environment: mapOfStrings(json['environment']),
    optional: json['optional'] == true,
  );
}

String stringValue(Object? value) => value == null ? '' : '$value';

String? optionalString(Object? value) {
  final text = value == null ? null : '$value';
  return text == null || text.isEmpty ? null : text;
}

List<Map<String, Object?>> listOfMaps(Object? value) {
  if (value is! List) {
    return const [];
  }
  return [
    for (final item in value)
      if (item is Map) item.map((key, value) => MapEntry('$key', value)),
  ];
}

List<String> listOfStrings(Object? value) =>
    value is List ? value.map((item) => '$item').toList() : const [];

List<List<String>> listOfStringLists(Object? value) => value is List
    ? [
        for (final item in value)
          if (item is List) item.map((entry) => '$entry').toList(),
      ]
    : const [];

Map<String, String> mapOfStrings(Object? value) => value is Map
    ? value.map((key, value) => MapEntry('$key', '$value'))
    : const {};

String normalizedTextDirection(String? value) =>
    value?.toLowerCase() == 'rtl' ? 'rtl' : 'ltr';
