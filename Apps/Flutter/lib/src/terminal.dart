// ignore_for_file: invalid_use_of_protected_member

part of '../main.dart';

extension _BundleHomePageStateTerminal on _BundleHomePageState {
  FlutterTerminalTab get _selectedTerminalTab => _terminalTabs.firstWhere(
        (tab) => tab.id == _selectedTerminalTabID,
        orElse: () => _terminalTabs.first,
      );

  bool _isCommandRunning(String command) =>
      (_runningCommandCounts[command] ?? 0) > 0;

  String _startCommandTab({
    required String title,
    required String command,
    String prefix = 'command',
  }) {
    final tabID = newTerminalTabID(prefix);
    setState(() {
      _terminalTabs.add(
        FlutterTerminalTab(
          id: tabID,
          title: title,
          command: command,
          lines: ['\$ $command', '[queued] Preparing command environment...'],
          isRunning: true,
          status: 'running',
        ),
      );
      _selectedTerminalTabID = tabID;
      _runningCommandCounts[command] =
          (_runningCommandCounts[command] ?? 0) + 1;
    });
    return tabID;
  }

  void _registerProcess(String tabID, Process process) {
    if (_cancelledTerminalTabIDs.contains(tabID)) {
      process.kill();
      return;
    }
    _runningProcesses[tabID] = process;
  }

  bool _finishCommandTab(
    String tabID, {
    required String command,
    required int exitCode,
  }) {
    if (!mounted) {
      return false;
    }
    var completed = false;
    setState(() {
      final index = _terminalTabs.indexWhere((tab) => tab.id == tabID);
      if (_cancelledTerminalTabIDs.remove(tabID) ||
          (index >= 0 && _terminalTabs[index].status == 'cancelled')) {
        _runningProcesses.remove(tabID);
        return;
      }
      _runningProcesses.remove(tabID);
      _decrementRunningCommand(command);
      if (index >= 0) {
        _terminalTabs[index].isRunning = false;
        _terminalTabs[index].status = exitCode == 0 ? 'ok' : 'failed';
        _terminalTabs[index].lines.add('[exit $exitCode]');
        completed = true;
      }
    });
    return completed;
  }

  bool _failCommandTab(
    String tabID, {
    required String command,
    required Object error,
  }) {
    if (!mounted) {
      return false;
    }
    var failed = false;
    setState(() {
      final index = _terminalTabs.indexWhere((tab) => tab.id == tabID);
      if (_cancelledTerminalTabIDs.remove(tabID) ||
          (index >= 0 && _terminalTabs[index].status == 'cancelled')) {
        _runningProcesses.remove(tabID);
        return;
      }
      _runningProcesses.remove(tabID);
      _decrementRunningCommand(command);
      if (index >= 0) {
        _terminalTabs[index].isRunning = false;
        _terminalTabs[index].status = 'failed';
        _terminalTabs[index].lines.add('[error] $error');
        failed = true;
      }
    });
    return failed;
  }

  void _appendTerminal(String text, {String? tabID}) {
    if (!mounted) {
      return;
    }
    final targetID = tabID ?? FlutterTerminalTab.mainTabID;
    final lines = text
        .trimRight()
        .split(RegExp(r'\r?\n'))
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) {
      return;
    }
    setState(() {
      final index = _terminalTabs.indexWhere((tab) => tab.id == targetID);
      if (index >= 0) {
        _terminalTabs[index].lines.addAll(lines);
      }
    });
  }

  void _selectTerminalTab(String tabID) {
    setState(() => _selectedTerminalTabID = tabID);
  }

  void _closeTerminalTab(String tabID) {
    if (tabID == FlutterTerminalTab.mainTabID) {
      return;
    }
    final process = _runningProcesses[tabID];
    setState(() {
      final index = _terminalTabs.indexWhere((tab) => tab.id == tabID);
      if (index < 0) {
        return;
      }
      final tab = _terminalTabs[index];
      if (tab.isRunning) {
        _runningProcesses.remove(tabID);
        _cancelledTerminalTabIDs.add(tabID);
        _decrementRunningCommand(tab.command);
        tab.isRunning = false;
        tab.status = 'cancelled';
        tab.lines.add('[cancelled] Command cancelled by user.');
        if (tab.command == 'bundle setup') {
          _setupRunning = false;
          for (final entry in _setupStatuses.entries.toList()) {
            if (entry.value == 'running') {
              _setupStatuses[entry.key] = 'cancelled';
            }
          }
          _bundleState.setupRun = FlutterSetupRunState(
            status: 'cancelled',
            completedAt: DateTime.now().toUtc().toIso8601String(),
          );
        }
        _selectedTerminalTabID = tabID;
        return;
      }
      _terminalTabs.removeWhere((tab) => tab.id == tabID);
      if (_selectedTerminalTabID == tabID) {
        _selectedTerminalTabID = _terminalTabs.first.id;
      }
    });
    if (process != null) {
      process.kill();
    }
    if (_bundleState.setupRun?.status == 'cancelled') {
      _persistBundleState();
    }
  }

  Future<void> _copySelectedTerminal() async {
    await Clipboard.setData(
      ClipboardData(text: _selectedTerminalTab.lines.join('\n')),
    );
    _appendTerminal('[terminal] Copied selected tab text.');
  }

  bool _isTerminalTabCancelled(String tabID) =>
      _cancelledTerminalTabIDs.contains(tabID) ||
      _terminalTabs.any(
        (tab) => tab.id == tabID && tab.status == 'cancelled',
      );

  void _decrementRunningCommand(String command) {
    final count = _runningCommandCounts[command] ?? 0;
    if (count <= 1) {
      _runningCommandCounts.remove(command);
    } else {
      _runningCommandCounts[command] = count - 1;
    }
  }
}

class _TerminalPane extends StatelessWidget {
  const _TerminalPane({required this.renderer});

  final _BundleHomePageState renderer;

  @override
  Widget build(BuildContext context) {
    final selectedTab = renderer._selectedTerminalTab;
    final terminalDirection = renderer._terminalTextDirection;
    return Semantics(
      container: true,
      label: 'Terminal output',
      child: Container(
        height: 240,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          border: Border(
            top: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: Column(
          children: [
            SizedBox(
              height: 44,
              child: Row(
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Icon(Icons.terminal, size: 20),
                  ),
                  Expanded(
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemBuilder: (context, index) {
                        final tab = renderer._terminalTabs[index];
                        return _TerminalTabChip(
                          tab: tab,
                          selected: tab.id == selectedTab.id,
                          onSelected: () => renderer._selectTerminalTab(tab.id),
                          onClosed: tab.id == FlutterTerminalTab.mainTabID
                              ? null
                              : () => renderer._closeTerminalTab(tab.id),
                        );
                      },
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
                      itemCount: renderer._terminalTabs.length,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy terminal text',
                    icon: const Icon(Icons.copy),
                    onPressed: renderer._copySelectedTerminal,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                reverse: true,
                padding: const EdgeInsets.all(12),
                child: Align(
                  alignment: terminalDirection == TextDirection.rtl
                      ? AlignmentDirectional.topEnd
                      : AlignmentDirectional.topStart,
                  child: Directionality(
                    textDirection: terminalDirection,
                    child: SelectableText(
                      selectedTab.lines.join('\n'),
                      textAlign: terminalDirection == TextDirection.rtl
                          ? TextAlign.right
                          : TextAlign.left,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TerminalTabChip extends StatelessWidget {
  const _TerminalTabChip({
    required this.tab,
    required this.selected,
    required this.onSelected,
    required this.onClosed,
  });

  final FlutterTerminalTab tab;
  final bool selected;
  final VoidCallback onSelected;
  final VoidCallback? onClosed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Terminal tab ${tab.title}',
      value: tab.status,
      hint: tab.command,
      child: InputChip(
        selected: selected,
        avatar: tab.isRunning
            ? const SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                _terminalStatusIcon(tab.status),
                size: 16,
                color: tab.status == 'failed' ? colorScheme.error : null,
              ),
        label: Text(tab.title, overflow: TextOverflow.ellipsis),
        onPressed: onSelected,
        onDeleted: onClosed,
        tooltip: tab.command,
      ),
    );
  }
}

IconData _terminalStatusIcon(String status) => switch (status) {
      'running' => Icons.sync,
      'failed' => Icons.error,
      'cancelled' => Icons.cancel,
      'ok' => Icons.check_circle,
      _ => Icons.terminal,
    };
