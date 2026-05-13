// ignore_for_file: invalid_use_of_protected_member

part of '../main.dart';

extension _BundleHomePageStateSetup on _BundleHomePageState {
  Future<void> runSetup() async {
    final manifest = _manifest;
    if (manifest == null || _setupRunning) {
      return;
    }
    if (manifest.setup.steps.isEmpty) {
      _appendTerminal('[setup] Bundle has no setup steps.');
      return;
    }

    final tabID = _startCommandTab(
      title: 'Setup',
      command: 'bundle setup',
      prefix: 'setup',
    );
    setState(() {
      _setupRunning = true;
      _bundleState.setupRun = FlutterSetupRunState(status: 'running');
      for (final step in manifest.setup.steps) {
        _setupStatuses[step.id] = 'pending';
      }
    });

    final results = <FlutterSetupStepRunState>[];
    var failedRequiredStep = false;
    var cancelled = false;
    for (final step in manifest.setup.steps) {
      if (_isTerminalTabCancelled(tabID)) {
        cancelled = true;
        break;
      }
      setState(() => _setupStatuses[step.id] = 'running');
      _appendTerminal('[setup:${step.id}] ${step.label}', tabID: tabID);
      final result = await _runSetupStep(step, tabID);
      results.add(result);
      if (result.status == 'cancelled') {
        cancelled = true;
      }
      setState(() {
        _setupStatuses[step.id] = result.status;
        _bundleState.setupRun = FlutterSetupRunState(
          status: 'running',
          results: [...results],
        );
      });
      _persistBundleState();
      if (cancelled) {
        break;
      }
      if (result.status == 'failed' && !step.optional) {
        failedRequiredStep = true;
        break;
      }
    }

    final completedRun = FlutterSetupRunState(
      status: cancelled
          ? 'cancelled'
          : failedRequiredStep
              ? 'failed'
              : 'ok',
      completedAt: DateTime.now().toUtc().toIso8601String(),
      results: results,
    );
    if (mounted) {
      setState(() {
        _setupRunning = false;
        _bundleState.setupRun = completedRun;
      });
      _persistBundleState();
      if (!cancelled) {
        _finishCommandTab(
          tabID,
          command: 'bundle setup',
          exitCode: failedRequiredStep ? 1 : 0,
        );
      }
    }
  }

  Future<FlutterSetupStepRunState> _runSetupStep(
    SetupStepSpec step,
    String tabID,
  ) async {
    try {
      if (_isTerminalTabCancelled(tabID)) {
        return _setupResult(step, status: 'cancelled');
      }
      final command = _planSetupCommand(step);
      _appendTerminal('\$ ${command.displayCommand}', tabID: tabID);
      return _runPlannedSetupCommand(step, command, tabID);
    } on Object catch (error) {
      _appendTerminal('[setup:${step.id}] $error', tabID: tabID);
      return _setupResult(
        step,
        status: step.optional ? 'warning' : 'failed',
        message: '$error',
      );
    }
  }

  _PlannedSetupCommand _planSetupCommand(SetupStepSpec step) {
    final context = renderContext();
    final value = _expandSetupValue(step.value ?? '', context);
    if (_requiresSetupValue(step.kind) && value.trim().isEmpty) {
      throw FormatException('Setup step value is empty: ${step.id}');
    }
    final arguments = step.arguments
        .map((argument) => _expandSetupValue(argument, context))
        .toList();
    final workingDirectory = step.workingDirectory == null
        ? bundleRoot
        : resolveBundledPath(
            _expandSetupValue(step.workingDirectory!, context),
            bundleRoot,
            mustExist: false,
            allowRoot: true,
          );
    final environment = {
      ...Platform.environment,
      'GUI_FOR_CLI_BUNDLE_ROOT': bundleRoot,
      'GUI_FOR_CLI_BUNDLE_WORKSPACE': bundleRoot,
      for (final entry in step.environment.entries)
        entry.key: _expandSetupValue(entry.value, context),
    };

    switch (step.kind) {
      case 'pathTool':
        return _PlannedSetupCommand(
          executable: Platform.isWindows ? 'where' : '/usr/bin/env',
          arguments: Platform.isWindows ? [value] : ['which', value],
          workingDirectory: workingDirectory,
          environment: environment,
        );
      case 'homebrewPackage':
        if (Platform.isWindows) {
          throw UnsupportedError(
              'Homebrew setup steps are not supported on Windows.');
        }
        return _PlannedSetupCommand(
          executable: '/usr/bin/env',
          arguments: ['brew', 'list', value],
          workingDirectory: workingDirectory,
          environment: environment,
        );
      case 'bundledScript':
      case 'setupScript':
        final scriptPath = resolveBundledPath(value, bundleRoot);
        if (Platform.isWindows) {
          final lowerPath = scriptPath.toLowerCase();
          if (lowerPath.endsWith('.bat') || lowerPath.endsWith('.cmd')) {
            return _PlannedSetupCommand(
              executable: 'cmd.exe',
              arguments: ['/C', scriptPath, ...arguments],
              workingDirectory: workingDirectory,
              environment: environment,
            );
          }
          if (lowerPath.endsWith('.ps1')) {
            return _PlannedSetupCommand(
              executable: 'powershell.exe',
              arguments: [
                '-NoProfile',
                '-ExecutionPolicy',
                'Bypass',
                '-File',
                scriptPath,
                ...arguments,
              ],
              workingDirectory: workingDirectory,
              environment: environment,
            );
          }
          if (lowerPath.endsWith('.exe')) {
            return _PlannedSetupCommand(
              executable: scriptPath,
              arguments: arguments,
              workingDirectory: workingDirectory,
              environment: environment,
            );
          }
          throw UnsupportedError(
              'Unsupported Windows setup script type: $scriptPath');
        }
        return _PlannedSetupCommand(
          executable: '/bin/sh',
          arguments: [
            scriptPath,
            ...arguments,
          ],
          workingDirectory: workingDirectory,
          environment: environment,
        );
      case 'pixiInstall':
        return _PlannedSetupCommand(
          executable: Platform.isWindows ? 'pixi' : '/usr/bin/env',
          arguments: Platform.isWindows
              ? ['install', ...arguments]
              : ['pixi', 'install', ...arguments],
          workingDirectory: workingDirectory,
          environment: environment,
        );
      case 'pixiRun':
        return _PlannedSetupCommand(
          executable: Platform.isWindows ? 'pixi' : '/usr/bin/env',
          arguments: Platform.isWindows
              ? ['run', value, ...arguments]
              : ['pixi', 'run', value, ...arguments],
          workingDirectory: workingDirectory,
          environment: environment,
        );
      default:
        throw UnsupportedError('Unsupported step kind: ${step.kind}');
    }
  }

  Future<FlutterSetupStepRunState> _runPlannedSetupCommand(
    SetupStepSpec step,
    _PlannedSetupCommand command,
    String tabID,
  ) async {
    try {
      final process = await Process.start(
        command.executable,
        command.arguments,
        workingDirectory: command.workingDirectory,
        environment: command.environment,
      );
      _registerProcess(tabID, process);
      process.stdout
          .transform(systemEncoding.decoder)
          .listen((text) => _appendTerminal(text, tabID: tabID));
      process.stderr
          .transform(systemEncoding.decoder)
          .listen((text) => _appendTerminal(text, tabID: tabID));
      final exitCode = await process.exitCode;
      _runningProcesses.remove(tabID);
      if (_isTerminalTabCancelled(tabID)) {
        return _setupResult(
          step,
          status: 'cancelled',
          command: command.displayCommand,
          exitCode: exitCode,
        );
      }
      return _setupResult(
        step,
        status: _setupStatusForExit(step, exitCode),
        command: command.displayCommand,
        exitCode: exitCode,
      );
    } on Object catch (error) {
      _appendTerminal('[setup:${step.id}] $error', tabID: tabID);
      return _setupResult(
        step,
        status: step.optional ? 'warning' : 'failed',
        command: command.displayCommand,
        message: '$error',
      );
    }
  }

  FlutterSetupStepRunState _setupResult(
    SetupStepSpec step, {
    required String status,
    String? command,
    int? exitCode,
    String? message,
  }) =>
      FlutterSetupStepRunState(
        id: step.id,
        label: step.label,
        kind: step.kind,
        command: command,
        status: status,
        exitCode: exitCode,
        message: message,
      );

  String _setupStatusForExit(SetupStepSpec step, int exitCode) =>
      exitCode == 0 ? 'ok' : (step.optional ? 'warning' : 'failed');

  String _expandSetupValue(String value, RenderContext context) =>
      expandBundlePathTokens(interpolate(value, context), bundleRoot);

  bool _requiresSetupValue(String kind) => kind != 'pixiInstall';

  Map<String, FlutterSetupStepRunState> get _setupResultsByID => {
        for (final result in _bundleState.setupRun?.results ??
            const <FlutterSetupStepRunState>[])
          result.id: result,
      };
}

class _PlannedSetupCommand {
  const _PlannedSetupCommand({
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
    required this.environment,
  });

  final String executable;
  final List<String> arguments;
  final String workingDirectory;
  final Map<String, String> environment;

  String get displayCommand =>
      [executable, ...arguments].map(shellQuote).join(' ');
}
