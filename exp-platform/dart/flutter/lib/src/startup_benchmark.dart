part of '../main.dart';

final class FlutterStartupBenchmark {
  FlutterStartupBenchmark._(
      {required this.startedAt, required this.outputPath});

  final DateTime startedAt;
  final String? outputPath;
  bool _wroteFirstFrame = false;
  bool _wroteContentReady = false;

  static FlutterStartupBenchmark fromArgs(List<String> args) =>
      FlutterStartupBenchmark._(
        startedAt: DateTime.now(),
        outputPath: _benchmarkOutputPath(args),
      );

  void markFirstFrame() {
    if (_wroteFirstFrame) {
      return;
    }
    _wroteFirstFrame = true;
    _write('flutter.firstFrameMs');
  }

  void markContentReady() {
    if (_wroteContentReady) {
      return;
    }
    _wroteContentReady = true;
    _write('flutter.contentReadyMs');
  }

  void _write(String metric) {
    if (outputPath == null) {
      return;
    }
    final elapsedMs =
        DateTime.now().difference(startedAt).inMicroseconds / 1000.0;
    try {
      File(outputPath!).writeAsStringSync(
        '$metric=${elapsedMs.toStringAsFixed(1)}\n',
        mode: FileMode.append,
        flush: true,
      );
    } on Object catch (error) {
      stderr.writeln('Could not write Flutter benchmark output: $error');
    }
  }

  static String? _benchmarkOutputPath(List<String> args) {
    const fromDefine = String.fromEnvironment('GFC_BENCHMARK_OUTPUT');
    if (fromDefine.isNotEmpty) {
      return fromDefine;
    }
    for (var index = 0; index < args.length; index += 1) {
      final argument = args[index];
      if (argument == '--benchmark-output' && index + 1 < args.length) {
        return args[index + 1];
      }
      if (argument.startsWith('--benchmark-output=')) {
        return argument.substring('--benchmark-output='.length);
      }
    }
    final environmentPath = Platform.environment['GFC_BENCHMARK_OUTPUT'];
    return environmentPath?.isEmpty == true ? null : environmentPath;
  }
}
