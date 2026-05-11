part of '../main.dart';

class _StandardOptionsCard extends StatelessWidget {
  const _StandardOptionsCard({required this.renderer});

  final _BundleHomePageState renderer;

  @override
  Widget build(BuildContext context) {
    final manifest = renderer._manifest;
    if (manifest == null) {
      return const SizedBox.shrink();
    }
    final languages = availableLocalizationOptions(
      renderer.bundleRoot,
      manifest.defaultLocalizationCode,
    );
    final selectedCode = renderer._bundleState.localizationCode ??
        manifest.defaultLocalizationCode;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Standard options',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            _SettingsRow(
              title: 'Language',
              child: DropdownButtonFormField<String>(
                initialValue:
                    languages.any((option) => option.code == selectedCode)
                        ? selectedCode
                        : manifest.defaultLocalizationCode,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final option in languages)
                    DropdownMenuItem(
                      value: option.code,
                      child: Text(option.displayName),
                    ),
                ],
                onChanged: (code) {
                  if (code != null) {
                    renderer.selectLocalizationCode(code);
                  }
                },
              ),
            ),
            const SizedBox(height: 12),
            _SettingsRow(
              title: 'Icon set',
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'platform',
                    icon: Icon(Icons.widgets),
                    label: Text('Platform'),
                  ),
                  ButtonSegment(
                    value: 'emoji',
                    icon: Text('🧬'),
                    label: Text('Emoji'),
                  ),
                ],
                selected: {renderer._bundleState.iconSet},
                onSelectionChanged: (values) =>
                    renderer.selectIconSet(values.first),
              ),
            ),
            const SizedBox(height: 12),
            _SettingsRow(
              title: 'Color theme',
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'system', label: Text('System')),
                  ButtonSegment(value: 'light', label: Text('Light')),
                  ButtonSegment(value: 'dark', label: Text('Dark')),
                ],
                selected: {renderer._bundleState.colorTheme},
                onSelectionChanged: (values) =>
                    renderer.selectColorTheme(values.first),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 560;
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                child,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 160,
                child:
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
              ),
              Expanded(child: child),
            ],
          );
        },
      );
}
