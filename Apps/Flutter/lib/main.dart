import 'dart:io';

import 'package:flutter/material.dart';

import 'src/bundle_loader.dart';
import 'src/models.dart';
import 'src/rendering.dart';

void main() {
  runApp(const GUIForCLIFlutterApp());
}

class GUIForCLIFlutterApp extends StatelessWidget {
  const GUIForCLIFlutterApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'GUI for CLI Flutter',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
          useMaterial3: true,
        ),
        home: const BundleHomePage(),
      );
}

class BundleHomePage extends StatefulWidget {
  const BundleHomePage({super.key});

  @override
  State<BundleHomePage> createState() => _BundleHomePageState();
}

class _BundleHomePageState extends State<BundleHomePage> {
  late final String repoRoot = resolveRepoRoot();
  late final String bundleRoot = resolveBundleRoot(repoRoot);
  late final Future<BundleManifest> _manifestFuture =
      BundleLoader(repoRoot: repoRoot, bundleRoot: bundleRoot).load();
  final _terminalLines = <String>['Loading bundle...'];
  BundleManifest? _manifest;
  BundlePage? _selectedPage;
  Map<String, String> _fieldValues = {};
  Map<String, String> _configValues = {};
  Map<String, Set<String>> _checkedOptions = {};

  @override
  Widget build(BuildContext context) => FutureBuilder<BundleManifest>(
        future: _manifestFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Scaffold(
              appBar: AppBar(title: const Text('GUI for CLI Flutter')),
              body: Padding(
                padding: const EdgeInsets.all(24),
                child: SelectableText('Could not load bundle:\n${snapshot.error}'),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          _initialize(snapshot.data!);
          return Scaffold(
            appBar: AppBar(title: Text(_manifest!.displayName)),
            body: Row(
              children: [
                _Sidebar(
                  manifest: _manifest!,
                  selectedPage: _selectedPage!,
                  onSelected: (page) => setState(() => _selectedPage = page),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: Column(
                    children: [
                      Expanded(child: _PageView(page: _selectedPage!, renderer: this)),
                      _TerminalPane(lines: _terminalLines),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );

  void _initialize(BundleManifest manifest) {
    if (_manifest != null) {
      return;
    }
    _manifest = manifest;
    _selectedPage = manifest.pages.firstWhere(
      (page) => page.id != 'settings',
      orElse: () => manifest.pages.first,
    );
    _fieldValues = initialFieldValues(manifest);
    _configValues = initialConfigValues(manifest);
    _checkedOptions = initialCheckedOptions(manifest);
    _terminalLines
      ..clear()
      ..add('Loaded ${manifest.displayName} from $bundleRoot');
  }

  RenderContext renderContext({Map<String, String> rowValues = const {}}) =>
      RenderContext(
        bundleRootPath: bundleRoot,
        homePath: Platform.environment['USERPROFILE'] ??
            Platform.environment['HOME'] ??
            Directory.current.path,
        fieldValues: _fieldValues,
        configValues: _configValues,
        checkedOptions: _checkedOptions.map((key, value) {
          final items = value.toList()..sort();
          return MapEntry(key, items.join(','));
        }),
        rowValues: rowValues,
      );

  Widget renderControl(ControlSpec control) {
    final tooltip = control.tooltip;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(control.label, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (tooltip != null) Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 6),
            child: Text(tooltip, style: Theme.of(context).textTheme.bodySmall),
          ),
          _controlBody(control),
        ],
      ),
    );
  }

  Widget renderActions(List<ActionSpec> actions, RenderContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final action in actions)
            FilledButton.tonalIcon(
              icon: const Icon(Icons.play_arrow),
              label: Text(action.title),
              onPressed: missingPlaceholders(action.command, context).isEmpty
                  ? () => _runAction(action, context)
                  : null,
            ),
        ],
      );

  Widget _controlBody(ControlSpec control) => switch (control.kind) {
        'text' || 'path' => TextFormField(
            initialValue: _fieldValues[control.id] ?? control.value ?? '',
            decoration: InputDecoration(
              hintText: control.placeholder,
              border: const OutlineInputBorder(),
              suffixIcon: control.kind == 'path' ? const Icon(Icons.folder_open) : null,
            ),
            onChanged: (value) => setState(() => _fieldValues[control.id] = value),
          ),
        'dropdown' => DropdownButtonFormField<String>(
            value: _dropdownValue(control),
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: [
              for (final option in control.options)
                DropdownMenuItem(value: option.id, child: Text(_optionTitle(option))),
            ],
            onChanged: (value) => setState(() => _fieldValues[control.id] = value ?? ''),
          ),
        'toggle' => SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(control.label),
            value: (_fieldValues[control.id] ?? control.value ?? '') == 'true',
            onChanged: (value) => setState(() => _fieldValues[control.id] = '$value'),
          ),
        'checkboxGroup' => _CheckboxGroup(
            control: control,
            selected: _checkedOptions[control.id] ?? <String>{},
            onChanged: (selected) => setState(() => _checkedOptions[control.id] = selected),
          ),
        'infoGrid' => Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in control.options) Chip(label: Text(_optionTitle(option))),
            ],
          ),
        'libraryList' => _LibraryList(control: control, renderer: this),
        'configEditor' => Column(
            children: [
              for (final setting in control.settings)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextFormField(
                    initialValue: _configValues['${control.id}.${setting.id}'] ?? setting.value ?? '',
                    decoration: InputDecoration(
                      labelText: setting.label,
                      hintText: setting.placeholder,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (value) => setState(() {
                      _configValues['${control.id}.${setting.id}'] = value;
                    }),
                  ),
                ),
            ],
          ),
        _ => Text('Unsupported control kind: ${control.kind}'),
      };

  String? _dropdownValue(ControlSpec control) {
    final selectedOptions =
        control.options.where((option) => option.selected).map((option) => option.id);
    final value = _fieldValues[control.id] ??
        control.value ??
        (selectedOptions.isEmpty ? null : selectedOptions.first);
    return control.options.any((option) => option.id == value) ? value : null;
  }

  Future<void> _runAction(ActionSpec action, RenderContext context) async {
    final commandLine = displayCommand(action.command, context);
    setState(() => _terminalLines.add('\$ $commandLine'));
    try {
      final process = await Process.start(
        interpolate(action.command.executable, context),
        action.command.arguments.map((argument) => interpolate(argument, context)).toList(),
        workingDirectory: bundleRoot,
        runInShell: false,
      );
      process.stdout.transform(systemEncoding.decoder).listen(_appendTerminal);
      process.stderr.transform(systemEncoding.decoder).listen(_appendTerminal);
      final exitCode = await process.exitCode;
      _appendTerminal('[exit $exitCode] ${action.title}');
    } catch (error) {
      _appendTerminal('Command failed: $error');
    }
  }

  void _appendTerminal(String text) {
    if (!mounted) {
      return;
    }
    setState(() {
      _terminalLines.addAll(text.trimRight().split(RegExp(r'\r?\n')));
    });
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.manifest,
    required this.selectedPage,
    required this.onSelected,
  });

  final BundleManifest manifest;
  final BundlePage selectedPage;
  final ValueChanged<BundlePage> onSelected;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 260,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            ListTile(
              leading: Text(manifest.iconEmoji ?? '🧰', style: const TextStyle(fontSize: 28)),
              title: Text(manifest.displayName),
              subtitle: Text(manifest.summary, maxLines: 3, overflow: TextOverflow.ellipsis),
            ),
            const Divider(),
            for (final page in manifest.pages)
              ListTile(
                selected: page.id == selectedPage.id,
                leading: Text(page.iconEmoji ?? '•'),
                title: Text(page.title),
                onTap: () => onSelected(page),
              ),
          ],
        ),
      );
}

class _PageView extends StatelessWidget {
  const _PageView({required this.page, required this.renderer});

  final BundlePage page;
  final _BundleHomePageState renderer;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(page.title, style: Theme.of(context).textTheme.headlineMedium),
          if (page.summary.isNotEmpty) Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 16),
            child: Text(page.summary),
          ),
          for (final section in page.sections) _SectionCard(section: section, renderer: renderer),
        ],
      );
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.section, required this.renderer});

  final PageSection section;
  final _BundleHomePageState renderer;

  @override
  Widget build(BuildContext context) {
    final renderContext = renderer.renderContext();
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (section.title != null)
              Text(section.title!, style: Theme.of(context).textTheme.titleLarge),
            if (section.subtitle != null) Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 12),
              child: Text(section.subtitle!),
            ),
            for (final control in section.controls) renderer.renderControl(control),
            if (section.actions.isNotEmpty) renderer.renderActions(section.actions, renderContext),
          ],
        ),
      ),
    );
  }
}

class _CheckboxGroup extends StatelessWidget {
  const _CheckboxGroup({
    required this.control,
    required this.selected,
    required this.onChanged,
  });

  final ControlSpec control;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 16,
        children: [
          for (final option in control.options)
            FilterChip(
              label: Text(_optionTitle(option)),
              selected: selected.contains(option.id),
              onSelected: (value) {
                final next = {...selected};
                value ? next.add(option.id) : next.remove(option.id);
                onChanged(next);
              },
            ),
        ],
      );
}

class _LibraryList extends StatelessWidget {
  const _LibraryList({required this.control, required this.renderer});

  final ControlSpec control;
  final _BundleHomePageState renderer;

  @override
  Widget build(BuildContext context) {
    final rows = hydrateRows(control);
    if (rows.isEmpty) {
      return const Text('No library items are defined.');
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: [
          for (final column in control.columns) DataColumn(label: Text(column.title)),
          if (control.rowActions.isNotEmpty) const DataColumn(label: Text('Actions')),
        ],
        rows: [
          for (final row in rows)
            DataRow(cells: [
              for (final column in control.columns) DataCell(Text(row.values[column.id] ?? '')),
              if (control.rowActions.isNotEmpty)
                DataCell(renderer.renderActions(
                  control.rowActions,
                  rowContext(renderer.renderContext(), row),
                )),
            ]),
        ],
      ),
    );
  }
}

class _TerminalPane extends StatelessWidget {
  const _TerminalPane({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) => Container(
        height: 180,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
        ),
        padding: const EdgeInsets.all(12),
        child: SelectableText(
          lines.join('\n'),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
      );
}

String _optionTitle(ControlOption option) =>
    option.group == null ? option.title : '${option.group}: ${option.title}';

