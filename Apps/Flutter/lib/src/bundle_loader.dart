import 'dart:convert';
import 'dart:io';

import 'localization.dart';
import 'models.dart';

class BundleLoader {
  const BundleLoader({required this.repoRoot, required this.bundleRoot});

  final String repoRoot;
  final String bundleRoot;

  Future<BundleManifest> load({String? locale}) async {
    final rawManifest = await loadManifestFromRoot(bundleRoot);
    final selectedLocale = locale ?? rawManifest.defaultLocalizationCode;
    final table = await loadStringTable(rawManifest, selectedLocale);
    return localizeManifest(rawManifest, table);
  }

  Future<BundleManifest> loadManifestFromRoot(String root) async {
    final manifestFile = File(_join(root, 'manifest.json'));
    final manifestJson = jsonDecode(await manifestFile.readAsString()) as Map<String, Object?>;
    final pages = manifestJson['pages'];
    if (pages is List<Object?> && pages.every((page) => page is String)) {
      final loadedPages = <Map<String, Object?>>[];
      for (final page in pages.cast<String>()) {
        if (!_isSafePageFileName(page)) {
          throw FormatException('Invalid page file name: $page');
        }
        final pageFile = File(_join(_join(root, 'pages'), page));
        loadedPages.add(jsonDecode(await pageFile.readAsString()) as Map<String, Object?>);
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
    return {
      ...await _readOptionalTable(
        _join(_join(_join(_join(repoRoot, 'Sources'), 'GUIForCLICore'), 'Resources'), 'BuiltinStrings/strings.en.toml'),
      ),
      if (locale != 'en')
        ...await _readOptionalTable(
          _join(_join(_join(_join(repoRoot, 'Sources'), 'GUIForCLICore'), 'Resources'), 'BuiltinStrings/strings.$locale.toml'),
        ),
      ...await _readOptionalTable(_join(_join(bundleRoot, 'strings'), 'strings.$defaultCode.toml')),
      if (locale != defaultCode)
        ...await _readOptionalTable(_join(_join(bundleRoot, 'strings'), 'strings.$locale.toml')),
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
    if (File(_join(directory.path, 'Package.swift')).existsSync() &&
        Directory(_join(directory.path, 'Examples')).existsSync()) {
      return directory.path;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      return Directory.current.path;
    }
    directory = parent;
  }
}

String resolveBundleRoot(String repoRoot) {
  const fromDefine = String.fromEnvironment('GFC_BUNDLE_ROOT');
  return fromDefine.isNotEmpty ? fromDefine : _join(_join(repoRoot, 'Examples'), 'WGSExtract');
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
