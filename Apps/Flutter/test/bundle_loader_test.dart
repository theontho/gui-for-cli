import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gui_for_cli_flutter/src/bundle_loader.dart';
import 'package:gui_for_cli_flutter/src/localization.dart';
import 'package:gui_for_cli_flutter/src/rendering.dart';

void main() {
  test('parses TOML localization strings', () {
    final table = parseTomlStrings('"bundle.displayName" = "Demo"\nplain = "Value"');

    expect(table['bundle.displayName'], 'Demo');
    expect(table['plain'], 'Value');
  });

  test('loads and localizes the WGS Extract bundle', () async {
    final repoRoot = _repoRoot();
    final manifest = await BundleLoader(
      repoRoot: repoRoot,
      bundleRoot: _join(_join(repoRoot, 'Examples'), 'WGSExtract'),
    ).load();

    expect(manifest.displayName, 'WGS Extract');
    expect(manifest.pages, isNotEmpty);
    expect(allControls(manifest), isNotEmpty);
  });

  test('renders commands with current control values', () async {
    final repoRoot = _repoRoot();
    final bundleRoot = _join(_join(repoRoot, 'Examples'), 'WGSExtract');
    final manifest = await BundleLoader(repoRoot: repoRoot, bundleRoot: bundleRoot).load();
    final action = manifest.pages
        .expand((page) => page.sections)
        .expand((section) => section.actions)
        .firstWhere((candidate) => candidate.command.executable.isNotEmpty);
    final context = RenderContext(
      bundleRootPath: bundleRoot,
      homePath: Directory.current.path,
      fieldValues: initialFieldValues(manifest),
      configValues: initialConfigValues(manifest),
      checkedOptions: const {},
    );

    expect(displayCommand(action.command, context), isNotEmpty);
  });
}

String _repoRoot() {
  var directory = Directory.current;
  while (true) {
    if (File(_join(directory.path, 'Package.swift')).existsSync()) {
      return directory.path;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('Could not find repository root from ${Directory.current.path}');
    }
    directory = parent;
  }
}

String _join(String first, String second) =>
    first.endsWith(Platform.pathSeparator) ? '$first$second' : '$first${Platform.pathSeparator}$second';
