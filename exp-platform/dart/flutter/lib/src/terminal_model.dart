class FlutterTerminalTab {
  FlutterTerminalTab({
    required this.id,
    required this.title,
    required this.command,
    List<String>? lines,
    this.isRunning = false,
    this.status = 'idle',
  }) : lines = lines ?? [];

  FlutterTerminalTab.main()
      : id = mainTabID,
        title = 'Main',
        command = 'main',
        lines = ['Loading bundle...'],
        isRunning = false,
        status = 'ok';

  static const mainTabID = 'main';

  final String id;
  String title;
  final String command;
  final List<String> lines;
  bool isRunning;
  String status;

  FlutterTerminalTab copy() => FlutterTerminalTab(
        id: id,
        title: title,
        command: command,
        lines: [...lines],
        isRunning: isRunning,
        status: status,
      );
}

String newTerminalTabID(String prefix) =>
    '$prefix-${DateTime.now().microsecondsSinceEpoch}';
