import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gui_for_cli_flutter/src/bundle_loader.dart';
import 'package:gui_for_cli_flutter/src/bundle_paths.dart';
import 'package:gui_for_cli_flutter/src/config_io.dart';
import 'package:gui_for_cli_flutter/src/icon_map.dart';
import 'package:gui_for_cli_flutter/src/localization.dart';
import 'package:gui_for_cli_flutter/src/models.dart';
import 'package:gui_for_cli_flutter/src/rendering.dart';
import 'package:gui_for_cli_flutter/src/terminal_model.dart';

void main() {
  test('parses TOML localization strings', () {
    final table = parseTomlStrings(
      '"bundle.displayName" = "Demo"\nplain = "Value"\n'
      'line = "First\\nSecond"\nliteral = "First\\\\nSecond"',
    );

    expect(table['bundle.displayName'], 'Demo');
    expect(table['plain'], 'Value');
    expect(table['line'], 'First\nSecond');
    expect(table['literal'], r'First\nSecond');
  });

  test('loads and localizes the WGS Extract bundle', () async {
    final repoRoot = _repoRoot();
    final manifest = await BundleLoader(
      repoRoot: repoRoot,
      bundleRoot: _join(_join(repoRoot, 'examples'), 'WGSExtract'),
    ).load();

    expect(manifest.displayName, 'WGS Extract');
    expect(manifest.terminalTextDirection, 'ltr');
    expect(manifest.pages, isNotEmpty);
    expect(allControls(manifest), isNotEmpty);
  });

  test('rejects malformed icon map TOML', () {
    expect(
      () => parseIconMapToml('[emoji]\n"warning" = "\\uZZZZ"'),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => parseIconMapToml('[emoji]\n"warning" "⚠️"'),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => parseIconMapToml('[emoji]\n"warning" = "⚠️" trailing'),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects unsafe localization codes', () async {
    final repoRoot = _repoRoot();
    final loader = BundleLoader(
      repoRoot: repoRoot,
      bundleRoot: _join(_join(repoRoot, 'examples'), 'WGSExtract'),
    );
    final manifest = await loader.loadManifestFromRoot(
      _join(_join(repoRoot, 'examples'), 'WGSExtract'),
    );

    expect(
      () => loader.loadStringTable(manifest, '../en'),
      throwsA(isA<FormatException>()),
    );
  });

  test('repo root resolution fails explicitly outside a repository', () async {
    final previous = Directory.current;
    final temp = await Directory.systemTemp.createTemp('gfc-no-repo-');
    addTearDown(() {
      Directory.current = previous;
      temp.deleteSync(recursive: true);
    });

    Directory.current = temp;

    expect(resolveRepoRoot, throwsA(isA<StateError>()));
  });

  test('normalizes manifest terminal text direction', () {
    final rtlManifest = BundleManifest.fromJson({
      'id': 'demo',
      'displayName': 'Demo',
      'summary': '',
      'terminalTextDirection': 'rtl',
      'sidebarIconStyle': 'image',
      'pages': <Object?>[],
    });
    final defaultManifest = BundleManifest.fromJson({
      'id': 'demo',
      'displayName': 'Demo',
      'summary': '',
      'terminalTextDirection': 'sideways',
      'sidebarIconStyle': 'sideways',
      'pages': <Object?>[],
    });

    expect(rtlManifest.terminalTextDirection, 'rtl');
    expect(rtlManifest.sidebarIconStyle, 'image');
    expect(defaultManifest.terminalTextDirection, 'ltr');
    expect(defaultManifest.sidebarIconStyle, 'automatic');
  });

  test('renders commands with current control values', () async {
    final repoRoot = _repoRoot();
    final bundleRoot = _join(_join(repoRoot, 'examples'), 'WGSExtract');
    final manifest = await BundleLoader(
      repoRoot: repoRoot,
      bundleRoot: bundleRoot,
    ).load();
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

  test('evaluates action visibility and disabled conditions', () async {
    final repoRoot = _repoRoot();
    final bundleRoot = _join(_join(repoRoot, 'examples'), 'WGSExtract');
    final manifest = await BundleLoader(
      repoRoot: repoRoot,
      bundleRoot: bundleRoot,
    ).load();
    final actions = manifest.pages
        .expand((page) => page.sections)
        .expand((section) => section.actions)
        .toList();
    final download = actions.firstWhere(
      (action) => action.id == 'gene-map-download',
    );
    final delete = actions.firstWhere(
      (action) => action.id == 'gene-map-delete',
    );
    final bootstrapped = actions.firstWhere(
      (action) => action.id == 'library-bootstrapped',
    );
    final context = RenderContext(
      bundleRootPath: bundleRoot,
      homePath: Directory.current.path,
      fieldValues: const {'ref_path': '/tmp/ref'},
      configValues: const {},
      checkedOptions: const {},
      dataValues: const {
        'library.geneMapInstalled': 'false',
        'library.isBootstrapped': 'true',
      },
    );

    expect(isActionVisible(download, context), isTrue);
    expect(isActionVisible(delete, context), isFalse);
    expect(disabledReason(bootstrapped, context), isNotNull);
    expect(delete.confirm, isNotNull);
  });

  test('parses config files and syncs config-backed field values', () {
    final manifest = BundleManifest(
      id: 'demo',
      displayName: 'Demo',
      summary: '',
      pages: [
        BundlePage(
          id: 'main',
          title: 'Main',
          summary: '',
          sections: [
            PageSection(
              id: 'inputs',
              controls: [
                ControlSpec(id: 'out_dir', label: 'Out', kind: 'path'),
                ControlSpec(
                  id: 'settings',
                  label: 'Settings',
                  kind: 'configEditor',
                  configFile: const ConfigFileSpec(path: 'settings.toml'),
                  settings: [
                    ConfigSettingSpec(
                      id: 'out_dir',
                      kind: 'path',
                      key: 'output_directory',
                      label: 'Out',
                    ),
                  ],
                ),
              ],
              actions: const [],
            ),
          ],
        ),
      ],
    );
    final configValues = {'settings.out_dir': '/tmp/output'};

    expect(
      parseFlatToml('"output_directory" = "/tmp/output"\n')['output_directory'],
      '/tmp/output',
    );
    expect(
      initialFieldValuesFromStateAndConfig(
        manifest,
        configValues,
        FlutterBundleState(),
      )['out_dir'],
      '/tmp/output',
    );
  });

  test('computes file-state placeholders', () async {
    final temp = await Directory.systemTemp.createTemp('gfc-flutter-test-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final file = File(_join(temp.path, 'sample.sorted.bam'));
    await file.writeAsString('abcd');
    await File('${file.path}.bai').writeAsString('index');
    final context = RenderContext(
      bundleRootPath: temp.path,
      homePath: Directory.current.path,
      fieldValues: {'bam_path': file.path},
      configValues: const {},
      checkedOptions: const {},
    );

    expect(contextValue(context, 'bam_path.pathExtension'), 'bam');
    expect(contextValue(context, 'bam_path.exists'), 'true');
    expect(contextValue(context, 'bam_path.isIndexed'), 'true');
    expect(contextValue(context, 'bam_path.isSorted'), 'true');
    expect(contextValue(context, 'bam_path.fileSize'), '4');
  });

  test('round-trips app options and setup run state', () {
    final state = FlutterBundleState.fromJson({
      'localizationCode': 'fr',
      'iconSet': 'emoji',
      'colorTheme': 'dark',
      'sidebarWidth': 312,
      'dataSourceErrors': {'library': 'Could not load data source'},
      'selectedPageID': 'settings',
      'setupRun': {
        'status': 'ok',
        'completedAt': '2024-01-01T00:00:00Z',
        'results': [
          {
            'id': 'pixi',
            'label': 'Pixi',
            'kind': 'pathTool',
            'command': '/usr/bin/env which pixi',
            'status': 'warning',
            'exitCode': 1,
          },
        ],
      },
    });

    expect(state.localizationCode, 'fr');
    expect(state.iconSet, 'emoji');
    expect(state.colorTheme, 'dark');
    expect(state.sidebarWidth, 312);
    expect(state.dataSourceErrors['library'], 'Could not load data source');
    expect(state.setupRun?.results.single.id, 'pixi');
    expect(state.setupRun?.results.single.label, 'Pixi');
    expect(state.setupRun?.results.single.kind, 'pathTool');
    expect(state.setupRun?.results.single.command, '/usr/bin/env which pixi');
    expect(
      FlutterBundleState.fromJson(
        state.toJson(),
      ).setupRun?.results.single.status,
      'warning',
    );
    expect(
      FlutterBundleState.fromJson(state.toJson())
          .setupRun
          ?.results
          .single
          .command,
      '/usr/bin/env which pixi',
    );
    expect(
      FlutterBundleState.fromJson(state.toJson()).dataSourceErrors['library'],
      'Could not load data source',
    );
  });

  test('manual config load reports missing files', () async {
    final temp = await Directory.systemTemp.createTemp('gfc-flutter-config-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final control = ControlSpec(
      id: 'settings',
      label: 'Settings',
      kind: 'configEditor',
      settings: [
        ConfigSettingSpec(
          id: 'out_dir',
          kind: 'path',
          key: 'output_directory',
          label: 'Out',
        ),
      ],
    );

    expect(
      () => loadConfigFile(
        control: control,
        path: 'missing.toml',
        bundleRoot: temp.path,
      ),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('setup specs parse working directories', () {
    final step = SetupStepSpec.fromJson({
      'id': 'install',
      'label': 'Install',
      'kind': 'setupScript',
      'value': 'scripts/install.sh',
      'workingDirectory': 'runtime',
    });

    expect(step.workingDirectory, 'runtime');
  });

  test('localization preserves setup working directories', () {
    final manifest = BundleManifest(
      id: 'demo',
      displayName: 'Demo',
      summary: 'Summary',
      setup: SetupSpec(
        steps: [
          SetupStepSpec(
            id: 'install',
            label: 'setup.install',
            kind: 'setupScript',
            value: 'scripts/install.sh',
            workingDirectory: 'runtime',
          ),
        ],
      ),
      pages: const [],
    );

    final localized = localizeManifest(manifest, {'setup.install': 'Install'});

    expect(localized.setup.steps.single.label, 'Install');
    expect(localized.setup.steps.single.workingDirectory, 'runtime');
  });

  test('bundled paths reject absolute and escaping paths', () async {
    final temp = await Directory.systemTemp.createTemp('gfc-flutter-paths-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final script = File(_join(_join(temp.path, 'scripts'), 'tool.sh'));
    await script.parent.create(recursive: true);
    await script.writeAsString('#!/bin/sh\n');

    expect(resolveBundledPath('scripts/tool.sh', temp.path), script.path);
    expect(isAbsoluteFilePath(r'C:\tools\tool.sh'), isTrue);
    expect(isAbsoluteFilePath(r'\\server\share\tool.sh'), isTrue);
    expect(
      () => resolveBundledPath('/tmp/tool.sh', temp.path, mustExist: false),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => resolveBundledPath('../tool.sh', temp.path, mustExist: false),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => resolveBundledPath('{{bundleRoot}}/scripts/tool.sh', temp.path),
      throwsA(isA<FormatException>()),
    );
  });

  test('creates mutable terminal tab state', () {
    final tab = FlutterTerminalTab.main();

    tab.lines.add('Ready');
    tab.status = 'ok';

    expect(tab.id, FlutterTerminalTab.mainTabID);
    expect(tab.lines, contains('Ready'));
    expect(newTerminalTabID('command'), startsWith('command-'));
  });
}

String _repoRoot() {
  var directory = Directory.current;
  while (true) {
    final applePackage = _join(
      _join(_join(directory.path, 'platform'), 'apple'),
      'Package.swift',
    );
    if (File(applePackage).existsSync()) {
      return directory.path;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError(
        'Could not find repository root from ${Directory.current.path}',
      );
    }
    directory = parent;
  }
}

String _join(String first, String second) =>
    first.endsWith(Platform.pathSeparator)
        ? '$first$second'
        : '$first${Platform.pathSeparator}$second';
