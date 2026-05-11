part of '../main.dart';

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.manifest,
    required this.selectedPage,
    required this.iconSet,
    required this.width,
    required this.onSelected,
    required this.onWidthChanged,
  });

  static const _minimumWidth = 180.0;
  static const _maximumWidth = 420.0;
  static const _bottomPageIDs = {'library', 'settings'};

  final BundleManifest manifest;
  final BundlePage selectedPage;
  final String iconSet;
  final double width;
  final ValueChanged<BundlePage> onSelected;
  final ValueChanged<double> onWidthChanged;

  @override
  Widget build(BuildContext context) {
    final primaryGroups = _sidebarGroups(
      manifest.pages.where((page) => !_bottomPageIDs.contains(page.id)),
    );
    final bottomPages = manifest.pages.where(
      (page) => _bottomPageIDs.contains(page.id),
    );
    return Semantics(
      container: true,
      label: 'Bundle pages',
      child: SizedBox(
        width: width,
        child: Stack(
          children: [
            Column(
              children: [
                _BundleSidebarHeader(manifest: manifest, iconSet: iconSet),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    children: [
                      for (final group in primaryGroups) ...[
                        if (group.title != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: Text(
                              group.title!,
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ),
                        for (final page in group.pages) _pageTile(page),
                      ],
                    ],
                  ),
                ),
                if (bottomPages.isNotEmpty) const Divider(height: 1),
                for (final page in bottomPages) _pageTile(page),
                const SizedBox(height: 8),
              ],
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeLeftRight,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragUpdate: (details) {
                    onWidthChanged(
                      (width + details.delta.dx)
                          .clamp(_minimumWidth, _maximumWidth)
                          .toDouble(),
                    );
                  },
                  child: const SizedBox(width: 8, height: double.infinity),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pageTile(BundlePage page) => Semantics(
    button: true,
    selected: page.id == selectedPage.id,
    label: page.title,
    child: ListTile(
      selected: page.id == selectedPage.id,
      leading: _bundleIcon(
        iconName: page.iconName,
        iconEmoji: page.iconEmoji,
        fallback: Icons.description,
        iconSet: iconSet,
      ),
      title: Text(page.title),
      onTap: () => onSelected(page),
    ),
  );

  List<_SidebarPageGroup> _sidebarGroups(Iterable<BundlePage> pages) {
    final groups = <_SidebarPageGroup>[];
    for (final page in pages) {
      final title = page.sidebarGroup?.trim();
      if (groups.isNotEmpty && groups.last.title == title) {
        groups.last.pages.add(page);
      } else {
        groups.add(
          _SidebarPageGroup(
            title: title == null || title.isEmpty ? null : title,
            pages: [page],
          ),
        );
      }
    }
    return groups;
  }
}

class _BundleSidebarHeader extends StatelessWidget {
  const _BundleSidebarHeader({required this.manifest, required this.iconSet});

  final BundleManifest manifest;
  final String iconSet;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: _bundleIcon(
            iconName: manifest.iconName,
            iconEmoji: manifest.iconEmoji,
            fallback: Icons.widgets,
            iconSet: iconSet,
            size: 30,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                manifest.displayName,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (manifest.summary.isNotEmpty)
                Text(
                  manifest.summary,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _SidebarPageGroup {
  _SidebarPageGroup({required this.title, required this.pages});

  final String? title;
  final List<BundlePage> pages;
}

Widget _bundleIcon({
  required String? iconName,
  required String? iconEmoji,
  required IconData fallback,
  required String iconSet,
  double size = 22,
}) {
  if (iconSet == 'emoji' && iconEmoji != null && iconEmoji.isNotEmpty) {
    return Text(iconEmoji, style: TextStyle(fontSize: size));
  }
  return Icon(_iconData(iconName) ?? fallback, size: size);
}

IconData? _iconData(String? iconName) {
  final name = iconName ?? '';
  if (name.contains('gearshape') || name.contains('slider')) {
    return Icons.settings;
  }
  if (name.contains('folder')) {
    return Icons.folder_open;
  }
  if (name.contains('library') || name.contains('books')) {
    return Icons.local_library;
  }
  if (name.contains('checklist') || name.contains('check')) {
    return Icons.checklist;
  }
  if (name.contains('doc') || name.contains('text')) {
    return Icons.description;
  }
  if (name.contains('arrow.down')) {
    return Icons.download;
  }
  if (name.contains('terminal')) {
    return Icons.terminal;
  }
  if (name.contains('person') || name.contains('figure')) {
    return Icons.family_restroom;
  }
  if (name.contains('point') || name.contains('dna')) {
    return Icons.hub;
  }
  return null;
}
