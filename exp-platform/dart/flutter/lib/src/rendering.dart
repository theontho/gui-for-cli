import 'dart:io';

import 'bundle_paths.dart';
import 'models.dart';

part 'rendering/action_conditions.dart';

final _placeholderPattern = RegExp(r'\{\{([^}]+)\}\}');

List<ControlSpec> allControls(BundleManifest manifest) => manifest.pages
    .expand((page) => page.sections)
    .expand((section) => section.controls)
    .toList();

Map<String, String> initialFieldValues(BundleManifest manifest) {
  final values = <String, String>{};
  for (final control in allControls(manifest)) {
    if (_persistsFieldValue(control.kind)) {
      values[control.id] = control.value ?? values[control.id] ?? '';
    }
  }
  return values;
}

Map<String, Set<String>> initialCheckedOptions(BundleManifest manifest) {
  final values = <String, Set<String>>{};
  for (final control in allControls(manifest)) {
    if (control.kind == 'checkboxGroup') {
      values[control.id] = control.options
          .where((option) => option.selected)
          .map((option) => option.id)
          .toSet();
    }
  }
  return values;
}

Map<String, String> initialConfigValues(BundleManifest manifest) {
  final values = <String, String>{};
  for (final control in allControls(manifest)
      .where((control) => control.kind == 'configEditor')) {
    for (final setting in control.settings) {
      values['${control.id}.${setting.id}'] = setting.value ?? '';
    }
  }
  return values;
}

String displayCommand(
  CommandSpec command,
  RenderContext context,
) {
  final executable = interpolate(command.executable, context);
  final arguments = commandArguments(command, context);
  return [executable, ...arguments].map(shellQuote).join(' ');
}

List<String> commandArguments(CommandSpec command, RenderContext context) => [
      ...command.arguments.map((argument) => interpolate(argument, context)),
      for (final group in command.optionalArguments)
        if (!group.any((argument) => placeholdersIn([argument]).any(
            (placeholder) =>
                (contextValue(context, placeholder) ?? '').trim().isEmpty)))
          ...group.map((argument) => interpolate(argument, context)),
    ];

List<String> missingPlaceholders(CommandSpec command, RenderContext context) =>
    placeholdersIn([command.executable, ...command.arguments])
        .where((placeholder) =>
            (contextValue(context, placeholder) ?? '').trim().isEmpty)
        .toList();

List<ListRowSpec> hydrateRows(ControlSpec control) {
  if (control.items.isEmpty) {
    return control.rows;
  }
  final template = control.rowTemplate ??
      ListRowSpec(
        id: '{{id}}',
        title: '{{name}}',
        values: {
          for (final column in control.columns) column.id: '{{${column.id}}}'
        },
        status: '{{status}}',
      );
  return [
    for (var index = 0; index < control.items.length; index += 1)
      _hydrateRow(template, control.items[index].values, index),
  ];
}

RenderContext rowContext(RenderContext baseContext, ListRowSpec row) {
  final values = <String, String>{
    ...row.values,
    if (row.id != null) 'id': row.id!,
    'title': row.title ?? row.id ?? '',
    if (row.status != null) 'status': row.status!,
  };
  return baseContext.copyWith(rowValues: values);
}

String shellQuote(String value) =>
    RegExp(r'^[A-Za-z0-9_./\\:-]+$').hasMatch(value)
        ? value
        : "'${value.replaceAll("'", "'\\''")}'";

String interpolate(String value, RenderContext context) =>
    value.replaceAllMapped(_placeholderPattern, (match) {
      final placeholder = match.group(1)!.trim();
      return contextValue(context, placeholder) ?? '';
    });

String? contextValue(RenderContext context, String placeholder) {
  if (placeholder == 'bundleRoot' || placeholder == 'bundleWorkspace') {
    return context.bundleRootPath;
  }
  if (placeholder == 'home') {
    return context.homePath;
  }
  if (placeholder.startsWith('row.')) {
    return context.rowValues[placeholder.substring(4)];
  }
  if (placeholder.startsWith('config.')) {
    return context.configValues[placeholder.substring(7)];
  }
  final computed = _computedFileStateValue(context, placeholder);
  if (computed != null) {
    return computed;
  }
  if (context.dataValues.containsKey(placeholder)) {
    return context.dataValues[placeholder];
  }
  return context.rowValues[placeholder] ??
      context.checkedOptions[placeholder] ??
      context.fieldValues[placeholder] ??
      context.configValues[placeholder];
}

String resolveUserPath(String path, String bundleRoot) {
  final home = Platform.environment['USERPROFILE'] ??
      Platform.environment['HOME'] ??
      Directory.current.path;
  var expanded = path.startsWith('~/') ? '$home/${path.substring(2)}' : path;
  expanded = expanded
      .replaceAll('{{bundleRoot}}', bundleRoot)
      .replaceAll('{{bundleWorkspace}}', bundleRoot)
      .replaceAll('{{home}}', home);
  if (isAbsoluteFilePath(expanded)) {
    return expanded;
  }
  return _join(bundleRoot, expanded);
}

String _join(String first, String second) =>
    first.endsWith(Platform.pathSeparator)
        ? '$first$second'
        : '$first${Platform.pathSeparator}$second';

double? evaluateNumeric(String expression) =>
    _NumericParser(expression).parse();

List<String> placeholdersIn(Iterable<String> values) {
  final placeholders = <String>[];
  for (final value in values) {
    for (final match in _placeholderPattern.allMatches(value)) {
      final placeholder = match.group(1)!.trim();
      if (!placeholders.contains(placeholder)) {
        placeholders.add(placeholder);
      }
    }
  }
  return placeholders;
}

bool _persistsFieldValue(String kind) =>
    kind == 'text' || kind == 'path' || kind == 'dropdown' || kind == 'toggle';

String? _computedFileStateValue(RenderContext context, String placeholder) {
  final separator = placeholder.lastIndexOf('.');
  if (separator <= 0 || separator >= placeholder.length - 1) {
    return null;
  }
  final fieldID = placeholder.substring(0, separator);
  final property = placeholder.substring(separator + 1);
  final rawPath = context.fieldValues[fieldID] ?? context.configValues[fieldID];
  final path = rawPath == null || rawPath.trim().isEmpty
      ? null
      : resolveUserPath(rawPath, context.bundleRootPath);
  switch (property) {
    case 'pathExtension':
      if (path == null) {
        return '';
      }
      final name = path.split(RegExp(r'[/\\]')).last;
      final dot = name.lastIndexOf('.');
      return dot >= 0 ? name.substring(dot + 1).toLowerCase() : '';
    case 'isIndexed':
      return '${path != null && _isIndexedAlignment(path)}';
    case 'isSorted':
      return '${path != null && _isSortedAlignment(path)}';
    case 'exists':
      return '${path != null && FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound}';
    case 'fileSize':
      final bytes = path == null ? null : _fileByteSize(path);
      return bytes == null ? '' : '$bytes';
    case 'fileSizeGB':
      final bytes = path == null ? null : _fileByteSize(path);
      return bytes == null ? '' : (bytes / 1073741824.0).toStringAsFixed(2);
    case 'parentDir':
      return path == null ? '' : File(path).parent.path;
    default:
      return null;
  }
}

int? _fileByteSize(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    return null;
  }
  return file.lengthSync();
}

bool _isIndexedAlignment(String path) {
  final withoutExtension =
      path.contains('.') ? path.substring(0, path.lastIndexOf('.')) : path;
  return [
    '$path.bai',
    '$path.crai',
    '$path.csi',
    '$withoutExtension.bai',
    '$withoutExtension.crai',
    '$withoutExtension.csi',
  ].any((candidate) => File(candidate).existsSync());
}

bool _isSortedAlignment(String path) {
  if (_isIndexedAlignment(path)) {
    return true;
  }
  final filename = path.split(RegExp(r'[/\\]')).last.toLowerCase();
  return filename.contains('.sorted.') ||
      filename.contains('_sorted.') ||
      filename.endsWith('.sorted.bam') ||
      filename.endsWith('.sorted.cram') ||
      filename.contains('.sort.') ||
      filename.contains('_sort.');
}

ListRowSpec _hydrateRow(
    ListRowSpec template, Map<String, String> values, int index) {
  final fallbackID = _nonEmpty(values['id']) ?? 'row-${index + 1}';
  final id = _nonEmpty(_interpolateItem(template.id, values)) ?? fallbackID;
  final title = _nonEmpty(_interpolateItem(template.title, values)) ??
      _nonEmpty(values['title']);
  final status = _nonEmpty(_interpolateItem(template.status, values)) ??
      _nonEmpty(values['status']);
  return ListRowSpec(
    id: id,
    title: title,
    status: status,
    tooltip: _nonEmpty(_interpolateItem(template.tooltip, values)),
    values: {
      for (final entry in template.values.entries)
        entry.key: _interpolateItem(entry.value, values) ?? '',
    },
    tags: template.tags
        .map((tag) => TagSpec(
              id: _interpolateItem(tag.id, values) ?? '',
              title: _interpolateItem(tag.title, values) ?? '',
              style: tag.style,
            ))
        .where((tag) => tag.title.trim().isNotEmpty)
        .toList(),
  );
}

String? _interpolateItem(String? value, Map<String, String> values) =>
    value?.replaceAllMapped(
      _placeholderPattern,
      (match) => values[match.group(1)!.trim()] ?? '',
    );

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

class RenderContext {
  const RenderContext({
    required this.bundleRootPath,
    required this.homePath,
    required this.fieldValues,
    required this.configValues,
    required this.checkedOptions,
    this.dataValues = const {},
    this.rowValues = const {},
  });

  final String bundleRootPath;
  final String homePath;
  final Map<String, String> fieldValues;
  final Map<String, String> configValues;
  final Map<String, String> checkedOptions;
  final Map<String, String> dataValues;
  final Map<String, String> rowValues;

  RenderContext copyWith({Map<String, String>? rowValues}) => RenderContext(
        bundleRootPath: bundleRootPath,
        homePath: homePath,
        fieldValues: fieldValues,
        configValues: configValues,
        checkedOptions: checkedOptions,
        dataValues: dataValues,
        rowValues: rowValues ?? this.rowValues,
      );
}
