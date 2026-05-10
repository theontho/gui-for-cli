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
    this.setup = const SetupSpec(steps: []),
  });

  final String id;
  final String displayName;
  final String summary;
  final String? iconName;
  final String? iconEmoji;
  final String? iconPath;
  final String defaultLocalizationCode;
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
  }) =>
      BundleManifest(
        id: id,
        displayName: displayName ?? this.displayName,
        summary: summary ?? this.summary,
        iconName: iconName,
        iconEmoji: iconEmoji,
        iconPath: iconPath,
        defaultLocalizationCode: defaultLocalizationCode,
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
        sections:
            listOfMaps(json['sections']).map(PageSection.fromJson).toList(),
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
    this.subtitle,
    this.iconName,
    this.iconEmoji,
  });

  final String id;
  final String? title;
  final String? subtitle;
  final String? iconName;
  final String? iconEmoji;
  final List<ControlSpec> controls;
  final List<ActionSpec> actions;

  factory PageSection.fromJson(Map<String, Object?> json) => PageSection(
        id: stringValue(json['id']),
        title: optionalString(json['title']),
        subtitle: optionalString(json['subtitle']),
        iconName: optionalString(json['iconName']),
        iconEmoji: optionalString(json['iconEmoji']),
        controls:
            listOfMaps(json['controls']).map(ControlSpec.fromJson).toList(),
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

  factory ControlSpec.fromJson(Map<String, Object?> json) => ControlSpec(
        id: stringValue(json['id']),
        label: stringValue(json['label']),
        kind: stringValue(json['kind']),
        value: optionalString(json['value']),
        placeholder: optionalString(json['placeholder']),
        tooltip: optionalString(json['tooltip']),
        options:
            listOfMaps(json['options']).map(ControlOption.fromJson).toList(),
        columns:
            listOfMaps(json['columns']).map(ListColumnSpec.fromJson).toList(),
        rows: listOfMaps(json['rows']).map(ListRowSpec.fromJson).toList(),
        items: listOfMaps(json['items']).map(ListItemSpec.fromJson).toList(),
        rowTemplate: json['rowTemplate'] is Map<String, Object?>
            ? ListRowSpec.fromJson(json['rowTemplate']! as Map<String, Object?>)
            : null,
        rowActions:
            listOfMaps(json['rowActions']).map(ActionSpec.fromJson).toList(),
        settings:
            listOfMaps(json['settings']).map(ConfigSettingSpec.fromJson).toList(),
      );
}

class ControlOption {
  ControlOption({
    required this.id,
    required this.title,
    this.selected = false,
    this.group,
  });

  final String id;
  final String title;
  final bool selected;
  final String? group;

  factory ControlOption.fromJson(Map<String, Object?> json) => ControlOption(
        id: stringValue(json['id']),
        title: stringValue(json['title']),
        selected: json['selected'] == true,
        group: optionalString(json['group']),
      );
}

class ListColumnSpec {
  ListColumnSpec({required this.id, required this.title});

  final String id;
  final String title;

  factory ListColumnSpec.fromJson(Map<String, Object?> json) =>
      ListColumnSpec(id: stringValue(json['id']), title: stringValue(json['title']));
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
  });

  final String id;
  final String kind;
  final String key;
  final String label;
  final String? value;
  final String? placeholder;
  final String? tooltip;
  final List<ControlOption> options;

  factory ConfigSettingSpec.fromJson(Map<String, Object?> json) =>
      ConfigSettingSpec(
        id: stringValue(json['id']),
        kind: stringValue(json['kind']),
        key: stringValue(json['key']),
        label: stringValue(json['label']),
        value: optionalString(json['value']),
        placeholder: optionalString(json['placeholder']),
        tooltip: optionalString(json['tooltip']),
        options:
            listOfMaps(json['options']).map(ControlOption.fromJson).toList(),
      );
}

class ActionSpec {
  ActionSpec({
    required this.id,
    required this.title,
    required this.command,
    this.tooltip,
    this.destructive = false,
  });

  final String id;
  final String title;
  final String? tooltip;
  final bool destructive;
  final CommandSpec command;

  factory ActionSpec.fromJson(Map<String, Object?> json) => ActionSpec(
        id: stringValue(json['id']),
        title: stringValue(json['title']),
        tooltip: optionalString(json['tooltip']),
        destructive: json['destructive'] == true,
        command: json['command'] is Map<String, Object?>
            ? CommandSpec.fromJson(json['command']! as Map<String, Object?>)
            : const CommandSpec(executable: '', arguments: []),
      );
}

class CommandSpec {
  const CommandSpec({required this.executable, required this.arguments});

  final String executable;
  final List<String> arguments;

  factory CommandSpec.fromJson(Map<String, Object?> json) => CommandSpec(
        executable: stringValue(json['executable']),
        arguments: listOfStrings(json['arguments']),
      );
}

class SetupSpec {
  const SetupSpec({required this.steps});

  final List<SetupStepSpec> steps;

  factory SetupSpec.fromJson(Map<String, Object?> json) =>
      SetupSpec(steps: listOfMaps(json['steps']).map(SetupStepSpec.fromJson).toList());
}

class SetupStepSpec {
  SetupStepSpec({
    required this.id,
    required this.label,
    required this.kind,
    this.value,
    this.optional = false,
  });

  final String id;
  final String label;
  final String kind;
  final String? value;
  final bool optional;

  factory SetupStepSpec.fromJson(Map<String, Object?> json) => SetupStepSpec(
        id: stringValue(json['id']),
        label: stringValue(json['label']),
        kind: stringValue(json['kind']),
        value: optionalString(json['value']),
        optional: json['optional'] == true,
      );
}

String stringValue(Object? value) => value == null ? '' : '$value';

String? optionalString(Object? value) {
  final text = value == null ? null : '$value';
  return text == null || text.isEmpty ? null : text;
}

List<Map<String, Object?>> listOfMaps(Object? value) {
  if (value is! List<Object?>) {
    return const [];
  }
  return [
    for (final item in value)
      if (item is Map<Object?, Object?>)
        item.map((key, value) => MapEntry('$key', value)),
  ];
}

List<String> listOfStrings(Object? value) => switch (value) {
      final List<Object?> items => items.map((item) => '$item').toList(),
      _ => const [],
    };

Map<String, String> mapOfStrings(Object? value) => switch (value) {
      final Map<Object?, Object?> map =>
        map.map((key, value) => MapEntry('$key', '$value')),
      _ => const {},
    };
