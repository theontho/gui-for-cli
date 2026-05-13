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
  final lines = text.split(RegExp(r'\r?\n'));
  for (var lineIndex = 0; lineIndex < lines.length; lineIndex += 1) {
    final rawLine = lines[lineIndex];
    final lineNumber = lineIndex + 1;
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) {
      continue;
    }
    if (line.startsWith('[') && line.endsWith(']')) {
      currentSource = line.substring(1, line.length - 1).trim();
      if (currentSource.isEmpty) {
        throw FormatException(
          'Invalid icon map TOML at line $lineNumber: $rawLine',
        );
      }
      values.putIfAbsent(currentSource, () => <String, String>{});
      continue;
    }
    final separator = _assignmentSeparator(line);
    if (separator < 0 || currentSource == null) {
      throw FormatException(
        'Invalid icon map TOML at line $lineNumber: $rawLine',
      );
    }
    final rawKey = line.substring(0, separator).trim();
    final rawValue = line.substring(separator + 1).trimLeft();
    final key = rawKey.startsWith('"')
        ? _parseTomlValue(rawKey, lineNumber, rawLine)
        : rawKey;
    values[currentSource]![key] =
        _parseTomlValue(rawValue, lineNumber, rawLine);
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

String _parseTomlValue(String value, int lineNumber, String rawLine) {
  if (!value.startsWith('"')) {
    throw FormatException(
      'Invalid icon map TOML at line $lineNumber: $rawLine',
    );
  }
  final closing = _closingQuoteIndex(value);
  if (closing == null) {
    throw FormatException(
      'Invalid icon map TOML at line $lineNumber: $rawLine',
    );
  }
  final trailing = value.substring(closing + 1).trim();
  if (trailing.isNotEmpty && !trailing.startsWith('#')) {
    throw FormatException(
      'Invalid icon map TOML at line $lineNumber: $rawLine',
    );
  }
  final content = value.substring(1, closing);
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
        if (end >= content.length) {
          throw FormatException(
            'Invalid icon map TOML at line $lineNumber: $rawLine',
          );
        }
        final hex = content.substring(index + 1, end + 1);
        final codePoint = int.tryParse(hex, radix: 16);
        if (codePoint == null) {
          throw FormatException(
            'Invalid icon map TOML at line $lineNumber: $rawLine',
          );
        }
        buffer.write(String.fromCharCode(codePoint));
        index = end;
        break;
      default:
        throw FormatException(
          'Invalid icon map TOML at line $lineNumber: $rawLine',
        );
    }
  }
  return buffer.toString();
}

int? _closingQuoteIndex(String value) {
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
  return null;
}

String _join(String first, String second) {
  if (first.endsWith(Platform.pathSeparator)) {
    return '$first$second';
  }
  return '$first${Platform.pathSeparator}$second';
}
