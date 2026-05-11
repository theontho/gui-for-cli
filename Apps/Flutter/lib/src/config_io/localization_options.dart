part of '../config_io.dart';

class FlutterLocalizationOption {
  const FlutterLocalizationOption({
    required this.code,
    required this.displayName,
  });

  final String code;
  final String displayName;
}

List<FlutterLocalizationOption> availableLocalizationOptions(
  String bundleRoot,
  String defaultCode,
) {
  final codes = <String>{defaultCode, 'en'};
  final stringsDirectory = Directory(_join(bundleRoot, 'strings'));
  if (stringsDirectory.existsSync()) {
    for (final entity in stringsDirectory.listSync()) {
      if (entity is! File) {
        continue;
      }
      final name = entity.uri.pathSegments.last;
      final match =
          RegExp(r'^strings\.([A-Za-z0-9_-]+)\.toml$').firstMatch(name);
      if (match != null) {
        codes.add(match.group(1)!);
      }
    }
  }
  final sorted = codes.toList()
    ..sort((left, right) {
      if (_isEnglish(left) && !_isEnglish(right)) {
        return -1;
      }
      if (!_isEnglish(left) && _isEnglish(right)) {
        return 1;
      }
      return _languageDisplayName(left).compareTo(_languageDisplayName(right));
    });
  return [
    for (final code in sorted)
      FlutterLocalizationOption(
          code: code, displayName: _languageDisplayName(code)),
  ];
}

bool _isEnglish(String code) {
  final lower = code.toLowerCase();
  return lower == 'en' || lower.startsWith('en-') || lower.startsWith('en_');
}

String _languageDisplayName(String code) => switch (code) {
      'ar' => 'Arabic (ar)',
      'bn' => 'Bengali (bn)',
      'de' => 'German (de)',
      'en' => 'English (en)',
      'es' => 'Spanish (es)',
      'fa' => 'Persian (fa)',
      'fi' => 'Finnish (fi)',
      'fr' => 'French (fr)',
      'he' => 'Hebrew (he)',
      'hi' => 'Hindi (hi)',
      'it' => 'Italian (it)',
      'ja' => 'Japanese (ja)',
      'ko' => 'Korean (ko)',
      'nl' => 'Dutch (nl)',
      'pl' => 'Polish (pl)',
      'pt' => 'Portuguese (pt)',
      'ru' => 'Russian (ru)',
      'sv' => 'Swedish (sv)',
      'uk' => 'Ukrainian (uk)',
      'ur' => 'Urdu (ur)',
      'zh-Hans' => 'Chinese Simplified (zh-Hans)',
      'zh-Hant' => 'Chinese Traditional (zh-Hant)',
      _ => code,
    };
