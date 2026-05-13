import 'dart:io';

class BundleIconMap {
  const BundleIconMap(this.values);

  static const empty = BundleIconMap({});

  final Map<String, Map<String, String>> values;

  String? resolve(String source, String? key) {
    final trimmed = key?.trim() ?? '';
    if (trimmed.isEmpty) {
      return null;
    }
    return values[source]?[trimmed];
  }

  BundleIconMap merge(BundleIconMap overlay) {
    final merged = {
      for (final entry in values.entries) entry.key: {...entry.value},
    };
    for (final entry in overlay.values.entries) {
      merged[entry.key] = {...?merged[entry.key], ...entry.value};
    }
    return BundleIconMap(merged);
  }
}

Future<BundleIconMap> loadIconMap(String repoRoot, String bundleRoot) async =>
    (await _readOptionalIconMap(
      _join(_join(_join(repoRoot, 'resources'), 'BuiltinIconMap'),
          'iconmap.toml'),
    ))
        .merge(await _readOptionalIconMap(_join(bundleRoot, 'iconmap.toml')));

Future<BundleIconMap> _readOptionalIconMap(String path) async {
  final file = File(path);
  if (!await file.exists()) {
    return BundleIconMap.empty;
  }
  return parseIconMapToml(await file.readAsString());
}

BundleIconMap parseIconMapToml(String text) {
  final values = <String, Map<String, String>>{};
  String? currentSource;
  for (final rawLine in text.split(RegExp(r'\r?\n'))) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) {
      continue;
    }
    if (line.startsWith('[') && line.endsWith(']')) {
      currentSource = line.substring(1, line.length - 1).trim();
      values.putIfAbsent(currentSource, () => <String, String>{});
      continue;
    }
    final separator = _assignmentSeparator(line);
    if (separator < 0 || currentSource == null) {
      continue;
    }
    final rawKey = line.substring(0, separator).trim();
    final rawValue = line.substring(separator + 1).trim();
    final key = rawKey.startsWith('"') ? _parseTomlValue(rawKey) : rawKey;
    values[currentSource]![key] = _parseTomlValue(rawValue);
  }
  return BundleIconMap(values);
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

String _parseTomlValue(String value) {
  if (!value.startsWith('"') || !value.endsWith('"')) {
    return value;
  }
  final content = value.substring(1, value.length - 1);
  final buffer = StringBuffer();
  for (var index = 0; index < content.length; index += 1) {
    final character = content[index];
    if (character != '\\' || index == content.length - 1) {
      buffer.write(character);
      continue;
    }
    index += 1;
    final escaped = content[index];
    switch (escaped) {
      case 'n':
        buffer.write('\n');
        break;
      case 'r':
        buffer.write('\r');
        break;
      case 't':
        buffer.write('\t');
        break;
      case '"':
        buffer.write('"');
        break;
      case '\\':
        buffer.write('\\');
        break;
      case 'u':
      case 'U':
        final length = escaped == 'u' ? 4 : 8;
        final end = index + length;
        if (end < content.length) {
          final hex = content.substring(index + 1, end + 1);
          final codePoint = int.tryParse(hex, radix: 16);
          if (codePoint != null) {
            buffer.write(String.fromCharCode(codePoint));
            index = end;
            break;
          }
        }
        buffer.write('\\$escaped');
        break;
      default:
        buffer.write(escaped);
        break;
    }
  }
  return buffer.toString();
}

String _join(String first, String second) {
  if (first.endsWith(Platform.pathSeparator)) {
    return '$first$second';
  }
  return '$first${Platform.pathSeparator}$second';
}
