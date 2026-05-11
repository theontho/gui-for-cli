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
        return FlutterSetupStepRunState(id: step.id, status: 'cancelled');
      }
      switch (step.kind) {
        case 'pathTool':
          return _checkPathTool(step, tabID);
        case 'setupScript':
          return _runSetupScript(step, tabID);
        default:
          _appendTerminal(
              '[setup:${step.id}] Unsupported step kind: ${step.kind}',
              tabID: tabID);
          return FlutterSetupStepRunState(
            id: step.id,
            status: step.optional ? 'warning' : 'failed',
            message: 'Unsupported step kind: ${step.kind}',
          );
      }
    } on Object catch (error) {
      _appendTerminal('[setup:${step.id}] $error', tabID: tabID);
      return FlutterSetupStepRunState(
        id: step.id,
        status: step.optional ? 'warning' : 'failed',
        message: '$error',
      );
    }
  }

  Future<FlutterSetupStepRunState> _checkPathTool(
    SetupStepSpec step,
    String tabID,
  ) async {
    final tool = interpolate(step.value ?? step.id, renderContext());
    final result = await Process.run(
      Platform.isWindows ? 'where' : 'which',
      [tool],
      workingDirectory: bundleRoot,
      runInShell: true,
    );
    final output = '${result.stdout}${result.stderr}'.trim();
    if (output.isNotEmpty) {
      _appendTerminal(output, tabID: tabID);
    }
    if (result.exitCode == 0) {
      return FlutterSetupStepRunState(
        id: step.id,
        status: 'ok',
        exitCode: result.exitCode,
      );
    }
    return FlutterSetupStepRunState(
      id: step.id,
      status: step.optional ? 'warning' : 'failed',
      exitCode: result.exitCode,
      message: '$tool was not found on PATH.',
    );
  }

  Future<FlutterSetupStepRunState> _runSetupScript(
    SetupStepSpec step,
    String tabID,
  ) async {
    final context = renderContext();
    final executable = interpolate(step.value ?? '', context);
    if (executable.isEmpty) {
      return FlutterSetupStepRunState(
        id: step.id,
        status: step.optional ? 'warning' : 'failed',
        message: 'Setup script path is empty.',
      );
    }
    final resolvedExecutable = executable.startsWith(Platform.pathSeparator)
        ? executable
        : '$bundleRoot${Platform.pathSeparator}$executable';
    final process = await Process.start(
      resolvedExecutable,
      step.arguments.map((argument) => interpolate(argument, context)).toList(),
      workingDirectory: bundleRoot,
      environment: {
        ...Platform.environment,
        'GUI_FOR_CLI_BUNDLE_ROOT': bundleRoot,
        'GUI_FOR_CLI_BUNDLE_WORKSPACE': bundleRoot,
        for (final entry in step.environment.entries)
          entry.key: interpolate(entry.value, context),
      },
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
      return FlutterSetupStepRunState(
        id: step.id,
        status: 'cancelled',
        exitCode: exitCode,
      );
    }
    return FlutterSetupStepRunState(
      id: step.id,
      status: exitCode == 0 ? 'ok' : (step.optional ? 'warning' : 'failed'),
      exitCode: exitCode,
    );
  }

  Map<String, FlutterSetupStepRunState> get _setupResultsByID => {
        for (final result in _bundleState.setupRun?.results ??
            const <FlutterSetupStepRunState>[])
          result.id: result,
      };
}
