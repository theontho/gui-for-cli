import 'dart:io';

String expandBundlePathTokens(String value, String bundleRoot) => value
    .replaceAll('{{bundleRoot}}', bundleRoot)
    .replaceAll('{{bundleWorkspace}}', bundleRoot)
    .replaceAll('{{bundleRootBasename}}', _basename(bundleRoot));

String resolveBundledPath(
  String path,
  String bundleRoot, {
  bool mustExist = true,
  bool allowRoot = false,
}) {
  final expanded = expandBundlePathTokens(path, bundleRoot).trim();
  if (expanded.isEmpty) {
    if (allowRoot) {
      return bundleRoot;
    }
    throw FormatException('Bundled path is empty.');
  }
  if (isAbsoluteFilePath(expanded) || containsParentTraversal(expanded)) {
    throw FormatException('Unsafe bundled path: $path');
  }
  final resolved = _join(bundleRoot, expanded);
  if (mustExist &&
      !File(resolved).existsSync() &&
      !Directory(resolved).existsSync()) {
    throw FileSystemException('Missing bundled path', resolved);
  }
  return resolved;
}

bool isAbsoluteFilePath(String path) =>
    path.startsWith(Platform.pathSeparator) ||
    RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path) ||
    path.startsWith(r'\\');

bool containsParentTraversal(String path) =>
    path.split(RegExp(r'[\\/]')).any((component) => component.trim() == '..');

String _basename(String path) {
  final parts = path.split(RegExp(r'[\\/]')).where((part) => part.isNotEmpty);
  return parts.isEmpty ? '' : parts.last;
}

String _join(String first, String second) =>
    first.endsWith(Platform.pathSeparator)
        ? '$first$second'
        : '$first${Platform.pathSeparator}$second';
