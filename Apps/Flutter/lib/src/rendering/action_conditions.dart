part of '../rendering.dart';

bool isActionVisible(ActionSpec action, RenderContext context) =>
    action.visibleWhen
        .every((condition) => conditionMatches(condition, context));

String? disabledReason(
  ActionSpec action,
  RenderContext context, {
  String fallback = 'This action is not available.',
}) {
  if (!action.disabledWhen
      .any((condition) => conditionMatches(condition, context))) {
    return null;
  }
  return action.disabledTooltip == null
      ? fallback
      : interpolate(action.disabledTooltip!, context);
}

bool conditionMatches(ActionConditionSpec condition, RenderContext context) {
  final value = (contextValue(context, condition.placeholder) ?? '').trim();
  if (condition.exists != null && condition.exists != value.isNotEmpty) {
    return false;
  }
  if (condition.equals != null &&
      value != interpolate(condition.equals!, context)) {
    return false;
  }
  if (condition.notEquals != null &&
      value == interpolate(condition.notEquals!, context)) {
    return false;
  }
  if (condition.inValues.isNotEmpty &&
      !condition.inValues
          .map((item) => interpolate(item, context))
          .contains(value)) {
    return false;
  }
  if (condition.notInValues
      .map((item) => interpolate(item, context))
      .contains(value)) {
    return false;
  }
  if (condition.lessThan != null &&
      !_compareNumeric(value, interpolate(condition.lessThan!, context),
          (left, right) => left < right)) {
    return false;
  }
  if (condition.lessThanOrEqual != null &&
      !_compareNumeric(value, interpolate(condition.lessThanOrEqual!, context),
          (left, right) => left <= right)) {
    return false;
  }
  if (condition.greaterThan != null &&
      !_compareNumeric(value, interpolate(condition.greaterThan!, context),
          (left, right) => left > right)) {
    return false;
  }
  if (condition.greaterThanOrEqual != null &&
      !_compareNumeric(
          value,
          interpolate(condition.greaterThanOrEqual!, context),
          (left, right) => left >= right)) {
    return false;
  }
  return true;
}

ActionPrecheckResult? evaluateActionPrecheck(
    ActionPrecheckSpec? precheck, RenderContext context) {
  final raw = precheck?.diskSpaceGB?.trim();
  if (raw == null || raw.isEmpty) {
    return null;
  }
  final requiredGB = evaluateNumeric(interpolate(raw, context));
  if (requiredGB == null || requiredGB <= 0) {
    return null;
  }
  var targetPath =
      interpolate(precheck!.diskSpacePath ?? '{{out_dir}}', context).trim();
  if (targetPath.isEmpty) {
    targetPath = context.bundleRootPath;
  }
  final resolvedPath = resolveUserPath(targetPath, context.bundleRootPath);
  final availableGB = _volumeAvailableGB(resolvedPath);
  if (availableGB == null) {
    return null;
  }
  final isLow = availableGB < requiredGB;
  final required = _formatGB(requiredGB);
  final available = _formatGB(availableGB);
  final pathLabel = File(resolvedPath).parent.path;
  final message = isLow && precheck.warningMessage != null
      ? interpolate(precheck.warningMessage!, context)
      : isLow
          ? 'Need $required GB free at $pathLabel, only $available GB available.'
          : 'Estimated $required GB needed at $pathLabel ($available GB free).';
  return ActionPrecheckResult(
    severity:
        isLow ? ActionPrecheckSeverity.warning : ActionPrecheckSeverity.info,
    title: isLow ? 'Not enough free disk space' : 'Disk space estimate',
    message: message,
  );
}

bool _compareNumeric(
  String left,
  String right,
  bool Function(double left, double right) compare,
) {
  final leftValue = evaluateNumeric(left);
  final rightValue = evaluateNumeric(right);
  return leftValue != null &&
      rightValue != null &&
      compare(leftValue, rightValue);
}

double? _volumeAvailableGB(String path) {
  if (Platform.isWindows) {
    return null;
  }
  var probe = path;
  while (probe.isNotEmpty &&
      FileSystemEntity.typeSync(probe) == FileSystemEntityType.notFound) {
    final parent = File(probe).parent.path;
    if (parent == probe) {
      break;
    }
    probe = parent;
  }
  final ProcessResult result;
  try {
    result = Process.runSync('df', ['-k', probe]);
  } on ProcessException {
    return null;
  }
  if (result.exitCode != 0) {
    return null;
  }
  final lines = result.stdout.toString().trim().split(RegExp(r'\r?\n'));
  if (lines.length < 2) {
    return null;
  }
  final columns = lines.last.trim().split(RegExp(r'\s+'));
  if (columns.length < 4) {
    return null;
  }
  final availableK = int.tryParse(columns[3]);
  return availableK == null ? null : availableK / 1048576.0;
}

String _formatGB(double value) {
  if (value >= 100) {
    return value.toStringAsFixed(0);
  }
  if (value >= 10) {
    return value.toStringAsFixed(1);
  }
  return value.toStringAsFixed(2);
}

enum ActionPrecheckSeverity { info, warning }

class ActionPrecheckResult {
  const ActionPrecheckResult({
    required this.severity,
    required this.title,
    required this.message,
  });

  final ActionPrecheckSeverity severity;
  final String title;
  final String message;
}

class _NumericParser {
  _NumericParser(this.text);

  final String text;
  int index = 0;

  double? parse() {
    final value = _expression();
    _skipWhitespace();
    return index == text.length ? value : null;
  }

  double? _expression() {
    var value = _term();
    while (value != null) {
      _skipWhitespace();
      if (_consume('+')) {
        final right = _term();
        if (right == null) return null;
        value += right;
      } else if (_consume('-')) {
        final right = _term();
        if (right == null) return null;
        value -= right;
      } else {
        return value;
      }
    }
    return null;
  }

  double? _term() {
    var value = _factor();
    while (value != null) {
      _skipWhitespace();
      if (_consume('*')) {
        final right = _factor();
        if (right == null) return null;
        value *= right;
      } else if (_consume('/')) {
        final right = _factor();
        if (right == null) return null;
        value /= right;
      } else {
        return value;
      }
    }
    return null;
  }

  double? _factor() {
    _skipWhitespace();
    if (_consume('+')) return _factor();
    if (_consume('-')) {
      final value = _factor();
      return value == null ? null : -value;
    }
    if (_consume('(')) {
      final value = _expression();
      return _consume(')') ? value : null;
    }
    return _number();
  }

  double? _number() {
    _skipWhitespace();
    final start = index;
    while (index < text.length && RegExp(r'[0-9.]').hasMatch(text[index])) {
      index += 1;
    }
    return start == index
        ? null
        : double.tryParse(text.substring(start, index));
  }

  bool _consume(String token) {
    if (index < text.length && text[index] == token) {
      index += 1;
      return true;
    }
    return false;
  }

  void _skipWhitespace() {
    while (index < text.length && text[index].trim().isEmpty) {
      index += 1;
    }
  }
}
