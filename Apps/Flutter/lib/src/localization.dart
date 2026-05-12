import 'models.dart';

Map<String, String> parseTomlStrings(String text) {
  final values = <String, String>{};
  final lines = text.split(RegExp(r'\r?\n'));
  var index = 0;
  while (index < lines.length) {
    final rawLine = lines[index];
    final line = rawLine.trim();
    index += 1;
    if (line.isEmpty || line.startsWith('#')) {
      continue;
    }
    final equals = _findUnescapedEquals(line);
    if (equals < 0) {
      throw FormatException('Invalid localization TOML: $rawLine');
    }
    final key = _unquoteKey(line.substring(0, equals).trim());
    var rawValue = line.substring(equals + 1).trimLeft();
    if (rawValue.startsWith('"""')) {
      rawValue = rawValue.substring(3);
      final collected = <String>[];
      final sameLineEnd = rawValue.indexOf('"""');
      if (sameLineEnd >= 0) {
        collected.add(rawValue.substring(0, sameLineEnd));
      } else {
        collected.add(rawValue);
        var foundEnd = false;
        while (index < lines.length) {
          final nextLine = lines[index];
          index += 1;
          final end = nextLine.indexOf('"""');
          if (end >= 0) {
            collected.add(nextLine.substring(0, end));
            foundEnd = true;
            break;
          }
          collected.add(nextLine);
        }
        if (!foundEnd) {
          throw FormatException(
              'Unterminated multiline localization string: $key');
        }
      }
      if (collected.isNotEmpty && collected.first.isEmpty) {
        collected.removeAt(0);
      }
      if (collected.isNotEmpty && collected.last.isEmpty) {
        collected.removeLast();
      }
      values[key] = collected.join('\n');
      continue;
    }
    if (!rawValue.startsWith('"')) {
      throw FormatException('Invalid localization TOML: $rawLine');
    }
    final closing = _findClosingQuote(rawValue);
    if (closing < 0) {
      throw FormatException('Invalid localization TOML: $rawLine');
    }
    values[key] = _unescapeTomlString(rawValue.substring(1, closing));
  }
  return values;
}

BundleManifest localizeManifest(
  BundleManifest manifest,
  Map<String, String> table,
) =>
    manifest.copyWith(
      displayName: localized(manifest.displayName, table),
      summary: localized(manifest.summary, table),
      setup: SetupSpec(
        steps: manifest.setup.steps
            .map((step) => SetupStepSpec(
                  id: step.id,
                  label: localized(step.label, table),
                  kind: step.kind,
                  value: step.value,
                  workingDirectory: step.workingDirectory,
                  arguments: step.arguments,
                  environment: step.environment,
                  optional: step.optional,
                ))
            .toList(),
      ),
      pages: manifest.pages.map((page) => _localizePage(page, table)).toList(),
    );

String localized(String value, Map<String, String> table) =>
    table[value] ?? value;

String? localizedOptional(String? value, Map<String, String> table) =>
    value == null ? null : localized(value, table);

BundlePage _localizePage(BundlePage page, Map<String, String> table) =>
    BundlePage(
      id: page.id,
      title: localized(page.title, table),
      summary: localized(page.summary, table),
      iconName: page.iconName,
      iconEmoji: page.iconEmoji,
      sidebarGroup: localizedOptional(page.sidebarGroup, table),
      sections: page.sections
          .map((section) => _localizeSection(section, table))
          .toList(),
    );

PageSection _localizeSection(PageSection section, Map<String, String> table) =>
    PageSection(
      id: section.id,
      title: localizedOptional(section.title, table),
      summary: localizedOptional(section.summary, table),
      subtitle: localizedOptional(section.subtitle, table),
      iconName: section.iconName,
      iconEmoji: section.iconEmoji,
      dataSource: section.dataSource,
      controls: section.controls
          .map((control) => _localizeControl(control, table))
          .toList(),
      actions: section.actions
          .map((action) => _localizeAction(action, table))
          .toList(),
    );

ControlSpec _localizeControl(ControlSpec control, Map<String, String> table) =>
    ControlSpec(
      id: control.id,
      label: localized(control.label, table),
      kind: control.kind,
      value: control.value,
      placeholder: localizedOptional(control.placeholder, table),
      tooltip: localizedOptional(control.tooltip, table),
      options: control.options
          .map((option) => ControlOption(
                id: option.id,
                title: localized(option.title, table),
                selected: option.selected,
                status: option.status,
                group: localizedOptional(option.group, table),
              ))
          .toList(),
      columns: control.columns
          .map((column) => ListColumnSpec(
              id: column.id, title: localized(column.title, table)))
          .toList(),
      rows: control.rows.map((row) => _localizeRow(row, table)).toList(),
      items: control.items
          .map((item) => ListItemSpec(item.values
              .map((key, value) => MapEntry(key, localized(value, table)))))
          .toList(),
      rowTemplate: control.rowTemplate == null
          ? null
          : _localizeRow(control.rowTemplate!, table),
      rowActions: control.rowActions
          .map((action) => _localizeAction(action, table))
          .toList(),
      settings: control.settings
          .map((setting) => _localizeSetting(setting, table))
          .toList(),
      configFile: control.configFile,
      dataSource: control.dataSource,
    );

ListRowSpec _localizeRow(ListRowSpec row, Map<String, String> table) =>
    ListRowSpec(
      id: row.id,
      title: localizedOptional(row.title, table),
      values: row.values,
      status: localizedOptional(row.status, table),
      tooltip: localizedOptional(row.tooltip, table),
      tags: row.tags
          .map((tag) => TagSpec(
              id: tag.id, title: localized(tag.title, table), style: tag.style))
          .toList(),
    );

ActionSpec _localizeAction(ActionSpec action, Map<String, String> table) =>
    ActionSpec(
      id: action.id,
      title: localized(action.title, table),
      tooltip: localizedOptional(action.tooltip, table),
      iconName: action.iconName,
      iconEmoji: action.iconEmoji,
      iconOnly: action.iconOnly,
      role: action.role,
      destructive: action.destructive,
      visibleWhen: action.visibleWhen,
      disabledWhen: action.disabledWhen,
      disabledTooltip: localizedOptional(action.disabledTooltip, table),
      precheck: action.precheck == null
          ? null
          : ActionPrecheckSpec(
              diskSpaceGB: action.precheck!.diskSpaceGB,
              diskSpacePath: action.precheck!.diskSpacePath,
              warningMessage:
                  localizedOptional(action.precheck!.warningMessage, table),
            ),
      confirm: action.confirm == null
          ? null
          : ActionConfirmationSpec(
              title: localized(action.confirm!.title, table),
              message: localizedOptional(action.confirm!.message, table),
              confirmButtonTitle:
                  localized(action.confirm!.confirmButtonTitle, table),
              cancelButtonTitle:
                  localized(action.confirm!.cancelButtonTitle, table),
              requiredText: action.confirm!.requiredText,
              prompt: localizedOptional(action.confirm!.prompt, table),
            ),
      command: action.command,
    );

ConfigSettingSpec _localizeSetting(
        ConfigSettingSpec setting, Map<String, String> table) =>
    ConfigSettingSpec(
      id: setting.id,
      kind: setting.kind,
      key: setting.key,
      label: localized(setting.label, table),
      value: setting.value,
      placeholder: localizedOptional(setting.placeholder, table),
      tooltip: localizedOptional(setting.tooltip, table),
      options: setting.options
          .map((option) => ControlOption(
                id: option.id,
                title: localized(option.title, table),
                selected: option.selected,
                status: option.status,
                group: localizedOptional(option.group, table),
              ))
          .toList(),
      dataSource: setting.dataSource,
    );

int _findUnescapedEquals(String line) {
  var quoted = false;
  var escaped = false;
  for (var index = 0; index < line.length; index += 1) {
    final character = line[index];
    if (escaped) {
      escaped = false;
    } else if (character == '\\') {
      escaped = true;
    } else if (character == '"') {
      quoted = !quoted;
    } else if (character == '=' && !quoted) {
      return index;
    }
  }
  return -1;
}

int _findClosingQuote(String value) {
  var escaped = false;
  for (var index = 1; index < value.length; index += 1) {
    final character = value[index];
    if (escaped) {
      escaped = false;
    } else if (character == '\\') {
      escaped = true;
    } else if (character == '"') {
      return index;
    }
  }
  return -1;
}

String _unquoteKey(String key) => key.startsWith('"') && key.endsWith('"')
    ? _unescapeTomlString(key.substring(1, key.length - 1))
    : key;

String _unescapeTomlString(String value) => value
    .replaceAll(r'\"', '"')
    .replaceAll(r'\n', '\n')
    .replaceAll(r'\r', '\r')
    .replaceAll(r'\t', '\t')
    .replaceAll(r'\\', '\\');
