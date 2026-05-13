import 'dart:convert';
import 'dart:io';

import 'icon_map.dart';
import 'localization.dart';
import 'models.dart';

class LoadedBundle {
  const LoadedBundle({required this.manifest, required this.iconMap});

  final BundleManifest manifest;
  final BundleIconMap iconMap;
}

class BundleLoader {
  const BundleLoader({required this.repoRoot, required this.bundleRoot});

  final String repoRoot;
  final String bundleRoot;

  Future<BundleManifest> load({String? locale}) async {
    return (await loadBundle(locale: locale)).manifest;
  }

  Future<LoadedBundle> loadBundle({String? locale}) async {
    final rawManifest = await loadManifestFromRoot(bundleRoot);
    final selectedLocale = locale ?? rawManifest.defaultLocalizationCode;
    final table = await loadStringTable(rawManifest, selectedLocale);
    return LoadedBundle(
      manifest: localizeManifest(rawManifest, table),
      iconMap: await loadIconMap(repoRoot, bundleRoot),
    );
  }

  Future<BundleManifest> loadManifestFromRoot(String root) async {
    final manifestFile = File(_join(root, 'manifest.json'));
    final manifestJson =
        jsonDecode(await manifestFile.readAsString()) as Map<String, Object?>;
    final pages = manifestJson['pages'];
    if (pages is List<Object?> && pages.every((page) => page is String)) {
      final loadedPages = <Map<String, Object?>>[];
      for (final page in pages.cast<String>()) {
        if (!_isSafePageFileName(page)) {
          throw FormatException('Invalid page file name: $page');
        }
        final pageFile = File(_join(_join(root, 'pages'), page));
        loadedPages.add(
            jsonDecode(await pageFile.readAsString()) as Map<String, Object?>);
      }
      manifestJson['pages'] = loadedPages;
    }
    return BundleManifest.fromJson(manifestJson);
  }

  Future<Map<String, String>> loadStringTable(
    BundleManifest manifest,
    String locale,
  ) async {
    final defaultCode = manifest.defaultLocalizationCode;
    if (!_isSafeLocaleCode(locale) || !_isSafeLocaleCode(defaultCode)) {
      throw FormatException('Invalid localization code: $locale');
    }
    final builtinStrings =
        _join(_join(repoRoot, 'resources'), 'BuiltinStrings');
    return {
      ...await _readOptionalTable(
        _join(builtinStrings, 'strings.en.toml'),
      ),
      if (locale != 'en')
        ...await _readOptionalTable(
          _join(builtinStrings, 'strings.$locale.toml'),
        ),
      ...await _readOptionalTable(
          _join(_join(bundleRoot, 'strings'), 'strings.$defaultCode.toml')),
      if (locale != defaultCode)
        ...await _readOptionalTable(
            _join(_join(bundleRoot, 'strings'), 'strings.$locale.toml')),
    };
  }

  Future<Map<String, String>> _readOptionalTable(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      return const {};
    }
    return parseTomlStrings(await file.readAsString());
  }
}

String resolveRepoRoot() {
  const fromDefine = String.fromEnvironment('GFC_REPO_ROOT');
  if (fromDefine.isNotEmpty) {
    return fromDefine;
  }

  var directory = Directory.current;
  while (true) {
    if (Directory(_join(_join(directory.path, 'resources'), 'BuiltinStrings'))
            .existsSync() &&
        Directory(_join(directory.path, 'examples')).existsSync()) {
      return directory.path;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError(
        'Could not find repository root from ${Directory.current.path}. '
        'Set GFC_REPO_ROOT or run from inside the GUI for CLI repository.',
      );
    }
    directory = parent;
  }
}

String resolveBundleRoot(String repoRoot) {
  const fromDefine = String.fromEnvironment('GFC_BUNDLE_ROOT');
  return fromDefine.isNotEmpty
      ? fromDefine
      : _join(_join(repoRoot, 'examples'), 'WGSExtract');
}

String _join(String first, String second) {
  if (first.endsWith(Platform.pathSeparator)) {
    return '$first$second';
  }
  return '$first${Platform.pathSeparator}$second';
}

bool _isSafePageFileName(String fileName) =>
    RegExp(r'^[A-Za-z0-9._-]+\.json$').hasMatch(fileName) &&
    !fileName.contains('/') &&
    !fileName.contains('\\');

bool _isSafeLocaleCode(String code) =>
    RegExp(r'^[A-Za-z0-9]+(?:[-_][A-Za-z0-9]+)*$').hasMatch(code);
