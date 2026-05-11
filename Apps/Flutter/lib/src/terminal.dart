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
      _terminalTabs.add(FlutterTerminalTab(
        id: tabID,
        title: title,
        command: command,
        lines: [
          '\$ $command',
          '[queued] Preparing command environment...',
        ],
        isRunning: true,
        status: 'running',
      ));
      _selectedTerminalTabID = tabID;
      _runningCommandCounts[command] =
          (_runningCommandCounts[command] ?? 0) + 1;
    });
    return tabID;
  }

  void _registerProcess(String tabID, Process process) {
    _runningProcesses[tabID] = process;
  }

  void _finishCommandTab(
    String tabID, {
    required String command,
    required int exitCode,
  }) {
    if (!mounted) {
      return;
    }
    setState(() {
      _runningProcesses.remove(tabID);
      final count = _runningCommandCounts[command] ?? 0;
      if (count <= 1) {
        _runningCommandCounts.remove(command);
      } else {
        _runningCommandCounts[command] = count - 1;
      }
      final index = _terminalTabs.indexWhere((tab) => tab.id == tabID);
      if (index >= 0) {
        _terminalTabs[index].isRunning = false;
        _terminalTabs[index].status = exitCode == 0 ? 'ok' : 'failed';
        _terminalTabs[index].lines.add('[exit $exitCode]');
      }
    });
  }

  void _failCommandTab(
    String tabID, {
    required String command,
    required Object error,
  }) {
    if (!mounted) {
      return;
    }
    setState(() {
      _runningProcesses.remove(tabID);
      final count = _runningCommandCounts[command] ?? 0;
      if (count <= 1) {
        _runningCommandCounts.remove(command);
      } else {
        _runningCommandCounts[command] = count - 1;
      }
      final index = _terminalTabs.indexWhere((tab) => tab.id == tabID);
      if (index >= 0) {
        _terminalTabs[index].isRunning = false;
        _terminalTabs[index].status = 'failed';
        _terminalTabs[index].lines.add('[error] $error');
      }
    });
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
    final process = _runningProcesses.remove(tabID);
    process?.kill();
    setState(() {
      final tab = _terminalTabs.firstWhere(
        (candidate) => candidate.id == tabID,
        orElse: () => FlutterTerminalTab.main(),
      );
      if (tab.id != FlutterTerminalTab.mainTabID) {
        final count = _runningCommandCounts[tab.command] ?? 0;
        if (count <= 1) {
          _runningCommandCounts.remove(tab.command);
        } else {
          _runningCommandCounts[tab.command] = count - 1;
        }
      }
      _terminalTabs.removeWhere((tab) => tab.id == tabID);
      if (_selectedTerminalTabID == tabID) {
        _selectedTerminalTabID = _terminalTabs.first.id;
      }
    });
  }

  Future<void> _copySelectedTerminal() async {
    await Clipboard.setData(
      ClipboardData(text: _selectedTerminalTab.lines.join('\n')),
    );
    _appendTerminal('[terminal] Copied selected tab text.');
  }
}

class _TerminalPane extends StatelessWidget {
  const _TerminalPane({required this.renderer});

  final _BundleHomePageState renderer;

  @override
  Widget build(BuildContext context) {
    final selectedTab = renderer._selectedTerminalTab;
    return Container(
      height: 240,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
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
                alignment: AlignmentDirectional.topStart,
                child: SelectableText(
                  selectedTab.lines.join('\n'),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
          ),
        ],
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
    return InputChip(
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
