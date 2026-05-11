part of '../main.dart';

extension _BundleHomePageStateActions on _BundleHomePageState {
  Future<bool> _confirmAction(
    ActionSpec action,
    ActionConfirmationSpec confirmation,
    RenderContext context,
  ) async {
    var input = '';
    final requiredText = confirmation.requiredText == null
        ? null
        : interpolate(confirmation.requiredText!, context);
    final confirmed = await showDialog<bool>(
      context: this.context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final canConfirm = requiredText == null || input == requiredText;
          return AlertDialog(
            title: Text(interpolate(confirmation.title, context)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (confirmation.message != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(interpolate(confirmation.message!, context)),
                  ),
                if (requiredText != null)
                  TextField(
                    decoration: InputDecoration(
                      labelText: interpolate(
                        confirmation.prompt ??
                            'Type "$requiredText" to confirm.',
                        context,
                      ),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (value) => setDialogState(() => input = value),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child:
                    Text(interpolate(confirmation.cancelButtonTitle, context)),
              ),
              FilledButton(
                onPressed: canConfirm
                    ? () => Navigator.of(dialogContext).pop(true)
                    : null,
                child:
                    Text(interpolate(confirmation.confirmButtonTitle, context)),
              ),
            ],
          );
        },
      ),
    );
    return confirmed == true;
  }

  Future<void> _requestRunAction(
      ActionSpec action, RenderContext context) async {
    final confirmation = action.confirm;
    if (confirmation != null &&
        !await _confirmAction(action, confirmation, context)) {
      return;
    }
    await _runAction(action, context);
  }

  Future<void> _runAction(ActionSpec action, RenderContext context) async {
    final commandLine = displayCommand(action.command, context);
    final tabID = _startCommandTab(
      title: action.title,
      command: commandLine,
    );
    try {
      final process = await Process.start(
        interpolate(action.command.executable, context),
        commandArguments(action.command, context),
        workingDirectory: bundleRoot,
        runInShell: false,
      );
      _registerProcess(tabID, process);
      process.stdout
          .transform(systemEncoding.decoder)
          .listen((text) => _appendTerminal(text, tabID: tabID));
      process.stderr
          .transform(systemEncoding.decoder)
          .listen((text) => _appendTerminal(text, tabID: tabID));
      final exitCode = await process.exitCode;
      _finishCommandTab(tabID, command: commandLine, exitCode: exitCode);
      final manifest = _manifest;
      if (manifest != null) {
        await _refreshDataSources(manifest, force: true);
      }
    } catch (error) {
      _failCommandTab(tabID, command: commandLine, error: error);
    }
  }
}
