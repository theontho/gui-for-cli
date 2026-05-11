part of '../main.dart';

class _PageView extends StatelessWidget {
  const _PageView({required this.page, required this.renderer});

  final BundlePage page;
  final _BundleHomePageState renderer;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(page.title, style: Theme.of(context).textTheme.headlineMedium),
          if (page.summary.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 16),
              child: Text(page.summary),
            ),
          if (page.id == 'settings') ...[
            _StandardOptionsCard(renderer: renderer),
            _SetupCard(renderer: renderer),
          ],
          for (final section in page.sections)
            _SectionCard(section: section, renderer: renderer),
        ],
      );
}

class _SetupCard extends StatelessWidget {
  const _SetupCard({required this.renderer});

  final _BundleHomePageState renderer;

  @override
  Widget build(BuildContext context) {
    final manifest = renderer._manifest;
    if (manifest == null || manifest.setup.steps.isEmpty) {
      return const SizedBox.shrink();
    }
    return Semantics(
      container: true,
      label: 'Bundle setup',
      value: _setupSummary(renderer),
      child: Card(
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Bundle setup',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: renderer.openBundleWorkspace,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Open workspace'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed:
                        renderer._setupRunning ? null : renderer.runSetup,
                    icon: const Icon(Icons.settings_backup_restore),
                    label: Text(
                      renderer._setupRunning
                          ? 'Running setup...'
                          : renderer._bundleState.setupRun?.status == 'ok'
                              ? 'Run setup again'
                              : 'Run setup',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _setupSummary(renderer),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              for (final step in manifest.setup.steps)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    _setupIcon(renderer._setupStatuses[step.id] ?? 'pending'),
                  ),
                  title: Text(step.label),
                  subtitle: Text(_setupStepSubtitle(renderer, step)),
                  trailing: Text(renderer._setupStatuses[step.id] ?? 'pending'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.section, required this.renderer});

  final PageSection section;
  final _BundleHomePageState renderer;

  @override
  Widget build(BuildContext context) {
    final renderContext = renderer.renderContext();
    return Semantics(
      container: true,
      label: section.title ?? section.id,
      hint: section.summary,
      child: Card(
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (section.title != null)
                Text(
                  section.title!,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              if (section.summary != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Text(section.summary!),
                ),
              if (section.subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 12),
                  child: Text(section.subtitle!),
                ),
              if (renderer._dataSourceErrors[section.id] != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _InlineDataSourceError(
                    message: renderer._dataSourceErrors[section.id]!,
                    onRetry: renderer.retryDataSources,
                  ),
                ),
              if (renderer._loadingDataSources.contains(section.id))
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: _DataSourceLoadingLabel(),
                ),
              for (final control in section.controls)
                renderer.renderControl(control),
              if (section.actions.isNotEmpty)
                renderer.renderActions(section.actions, renderContext),
            ],
          ),
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
            Semantics(
              button: true,
              toggled: selected.contains(option.id),
              label: _optionTitle(option),
              hint: selected.contains(option.id)
                  ? 'Selected checkbox option'
                  : 'Unselected checkbox option',
              child: FilterChip(
                label: Text(_optionTitle(option)),
                selected: selected.contains(option.id),
                onSelected: (value) {
                  final next = {...selected};
                  value ? next.add(option.id) : next.remove(option.id);
                  onChanged(next);
                },
              ),
            ),
        ],
      );
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.action,
    required this.context,
    required this.isRunning,
    required this.onRun,
  });

  final ActionSpec action;
  final RenderContext context;
  final bool isRunning;
  final Future<void> Function() onRun;

  @override
  Widget build(BuildContext buildContext) {
    final missing = missingPlaceholders(action.command, context);
    final disabled = disabledReason(action, context);
    final precheck = evaluateActionPrecheck(action.precheck, context);
    final precheckWarning =
        precheck?.severity == ActionPrecheckSeverity.warning;
    final isDisabled =
        isRunning || missing.isNotEmpty || disabled != null || precheckWarning;
    final help = _helpText(missing, disabled, precheck);
    final button = Semantics(
      button: true,
      enabled: !isDisabled,
      label: action.title,
      hint: help,
      child: FilledButton.tonalIcon(
        icon: Icon(_actionIcon(action)),
        label: action.iconOnly
            ? const SizedBox.shrink()
            : Text(isRunning ? 'Running...' : action.title),
        style: action.destructive || action.role == 'destructive'
            ? FilledButton.styleFrom(
                foregroundColor: Theme.of(buildContext).colorScheme.error,
              )
            : null,
        onPressed: isDisabled ? null : () => onRun(),
      ),
    );
    return Tooltip(
      message: help,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (precheck != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _PrecheckBanner(result: precheck),
            ),
          button,
        ],
      ),
    );
  }

  String _helpText(
    List<String> missing,
    String? disabled,
    ActionPrecheckResult? precheck,
  ) {
    if (precheck?.severity == ActionPrecheckSeverity.warning) {
      return precheck!.message;
    }
    if (isRunning) {
      return 'This command is already running.';
    }
    if (missing.isNotEmpty) {
      final text = 'Missing: ${missing.join(', ')}';
      return action.tooltip == null ? text : '${action.tooltip}\n\n$text';
    }
    if (disabled != null) {
      return action.tooltip == null
          ? disabled
          : '${action.tooltip}\n\n$disabled';
    }
    return action.tooltip ?? displayCommand(action.command, context);
  }
}

class _PrecheckBanner extends StatelessWidget {
  const _PrecheckBanner({required this.result});

  final ActionPrecheckResult result;

  @override
  Widget build(BuildContext context) {
    final color = result.severity == ActionPrecheckSeverity.warning
        ? Colors.orange
        : Theme.of(context).colorScheme.primary;
    return Container(
      constraints: const BoxConstraints(maxWidth: 360),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            result.severity == ActionPrecheckSeverity.warning
                ? Icons.warning
                : Icons.storage,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  result.title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  result.message,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LibraryList extends StatelessWidget {
  const _LibraryList({required this.control, required this.renderer});

  final ControlSpec control;
  final _BundleHomePageState renderer;

  @override
  Widget build(BuildContext context) {
    if (renderer._loadingDataSources.contains(control.id) &&
        renderer._dynamicControlData[control.id] == null) {
      return const _DataSourceLoadingLabel();
    }
    final rows = hydrateRows(control);
    if (rows.isEmpty) {
      return const Text('No library items are defined.');
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: [
          for (final column in control.columns)
            DataColumn(label: Text(column.title)),
          if (control.rowActions.isNotEmpty)
            const DataColumn(label: Text('Actions')),
        ],
        rows: [
          for (final row in rows)
            DataRow(
              cells: [
                for (final column in control.columns)
                  DataCell(_LibraryCell(row: row, column: column)),
                if (control.rowActions.isNotEmpty)
                  DataCell(
                    renderer.renderActions(
                      control.rowActions,
                      rowContext(renderer.renderContext(), row),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _LibraryCell extends StatelessWidget {
  const _LibraryCell({required this.row, required this.column});

  final ListRowSpec row;
  final ListColumnSpec column;

  @override
  Widget build(BuildContext context) {
    final text = _displayValue();
    final children = <Widget>[
      Text(
        text,
        style: column.id == 'name'
            ? const TextStyle(fontWeight: FontWeight.w600)
            : null,
      ),
    ];
    if (column.id == 'name' && (row.status != null || row.tags.isNotEmpty)) {
      children.add(
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            if (row.status != null)
              _TagPill(label: row.status!, style: row.status),
            for (final tag in row.tags)
              _TagPill(label: tag.title, style: tag.style),
          ],
        ),
      );
    }
    return Tooltip(
      message: row.tooltip ?? text,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }

  String _displayValue() {
    if (column.id == 'name') {
      return row.title ?? row.values[column.id] ?? row.id ?? '';
    }
    if (column.id == 'status') {
      return row.status ?? row.values[column.id] ?? '';
    }
    return row.values[column.id] ?? '';
  }
}

String _optionTitle(ControlOption option) =>
    '${option.group == null ? option.title : '${option.group}: ${option.title}'}${option.status == null ? '' : ' (${option.status})'}';

String _setupSummary(_BundleHomePageState renderer) {
  if (renderer._setupRunning) {
    return 'Setup is running.';
  }
  return switch (renderer._bundleState.setupRun?.status) {
    'ok' => 'Setup completed successfully.',
    'failed' => 'Setup failed. Review the terminal output.',
    _ => 'Setup has not completed for this workspace.',
  };
}

String _setupStepSubtitle(_BundleHomePageState renderer, SetupStepSpec step) {
  final result = renderer._setupResultsByID[step.id];
  final parts = [
    step.kind,
    if (step.optional) 'optional',
    if (result?.exitCode != null) 'exit ${result!.exitCode}',
    if (result?.message != null) result!.message!,
  ];
  return parts.join(' • ');
}

IconData _setupIcon(String status) => switch (status) {
      'ok' => Icons.check_circle,
      'warning' || 'skipped' => Icons.warning,
      'failed' => Icons.error,
      'running' => Icons.sync,
      _ => Icons.radio_button_unchecked,
    };

IconData _actionIcon(ActionSpec action) {
  final iconName = action.iconName ?? '';
  if (action.destructive ||
      action.role == 'destructive' ||
      iconName.contains('trash')) {
    return Icons.delete;
  }
  if (iconName.contains('check')) {
    return Icons.check_circle;
  }
  if (iconName.contains('arrow.down')) {
    return Icons.download;
  }
  if (iconName.contains('arrow.clockwise')) {
    return Icons.refresh;
  }
  if (iconName.contains('folder')) {
    return Icons.folder_open;
  }
  if (iconName.contains('number')) {
    return Icons.pin;
  }
  return Icons.play_arrow;
}
