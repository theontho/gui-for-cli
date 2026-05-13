part of '../config_io.dart';

Map<String, String> parseFlatToml(String text) {
  final values = <String, String>{};
  for (final rawLine in text.split(RegExp(r'\r?\n'))) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#') || !line.contains('=')) {
      continue;
    }
    final separator = _assignmentSeparator(line);
    if (separator < 0) {
      continue;
    }
    final rawKey = line.substring(0, separator).trim();
    final rawValue = line.substring(separator + 1).trim();
    final key = rawKey.startsWith('"') ? _parseTomlValue(rawKey) : rawKey;
    values[key] = _parseTomlValue(rawValue);
  }
  return values;
}

String serializeFlatToml(Map<String, String> values) {
  final entries = values.entries.toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  return '${entries.map((entry) => '${_tomlKey(entry.key)} = ${_tomlValue(entry.value)}').join('\n')}\n';
}

int _assignmentSeparator(String line) {
  var inQuotes = false;
  var escaped = false;
  for (var index = 0; index < line.length; index += 1) {
    final character = line[index];
    if (escaped) {
      escaped = false;
    } else if (character == '\\' && inQuotes) {
      escaped = true;
    } else if (character == '"') {
      inQuotes = !inQuotes;
    } else if (character == '=' && !inQuotes) {
      return index;
    }
  }
  return -1;
}

String _tomlKey(String key) =>
    RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(key) ? key : _tomlValue(key);

String _tomlValue(String value) =>
    '"${value.replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll('\n', r'\n')}"';

String _parseTomlValue(String value) {
  if (!value.startsWith('"') || !value.endsWith('"')) {
    return value;
  }
  return value.substring(1, value.length - 1).replaceAllMapped(
        RegExp(r'\\([nrt"\\])'),
        (match) => switch (match.group(1)!) {
          'n' => '\n',
          'r' => '\r',
          't' => '\t',
          '"' => '"',
          '\\' => '\\',
          _ => match.group(1)!,
        },
      );
}
