part of '../main.dart';

class _InlineDataSourceError extends StatelessWidget {
  const _InlineDataSourceError({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        liveRegion: true,
        label: 'Data source error',
        value: message,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning, color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                message,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
}

class _DataSourceLoadingLabel extends StatelessWidget {
  const _DataSourceLoadingLabel({
    required this.label,
    required this.semanticsLabel,
  });

  factory _DataSourceLoadingLabel.forRenderer(_BundleHomePageState renderer) =>
      _DataSourceLoadingLabel(
        label: renderer._appString('dataSource.loading.message'),
        semanticsLabel: renderer._appString('dataSource.loading.semanticLabel'),
      );

  final String label;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        label: semanticsLabel,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Text(label),
          ],
        ),
      );
}

class _TagPill extends StatelessWidget {
  const _TagPill({required this.label, this.style});

  final String label;
  final String? style;

  @override
  Widget build(BuildContext context) {
    final color = _tagColor(context);
    return Semantics(
      label: 'Tag $label',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          border: Border.all(color: color.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
        ),
      ),
    );
  }

  Color _tagColor(BuildContext context) {
    final normalized = style?.toLowerCase();
    if (normalized == 'installed' || normalized == 'success') {
      return Colors.green;
    }
    if (normalized == 'unindexed' ||
        normalized == 'incomplete' ||
        normalized == 'warning') {
      return Colors.orange;
    }
    if (normalized == 'missing' || normalized == 'secondary') {
      return Theme.of(context).colorScheme.outline;
    }
    return Theme.of(context).colorScheme.primary;
  }
}
