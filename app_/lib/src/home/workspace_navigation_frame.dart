import 'package:flutter/material.dart';

/// Navigation stays outside the scrolling file area on desktop.
class WorkspaceNavigationFrame extends StatelessWidget {
  const WorkspaceNavigationFrame({
    super.key,
    required this.child,
    this.account,
    this.nativeDriveLabel,
    required this.selected,
    required this.onSelected,
    required this.onSettings,
    required this.backupsAvailable,
  });
  final Widget child;
  final Widget? account;
  final String? nativeDriveLabel;
  final int selected;
  final ValueChanged<int> onSelected;
  final VoidCallback onSettings;
  final bool backupsAvailable;

  @override
  Widget build(BuildContext context) {
    final destinations = <({int id, String label, IconData icon})>[
      (id: 0, label: 'Files', icon: Icons.folder_outlined),
      if (backupsAvailable)
        (id: 1, label: 'Backups', icon: Icons.backup_outlined),
      (id: 2, label: 'Offline', icon: Icons.offline_pin_outlined),
      if (nativeDriveLabel != null)
        (id: 3, label: nativeDriveLabel!, icon: Icons.desktop_windows_outlined),
    ];
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 1000) {
          return Column(
            children: [
              Expanded(child: child),
              if (account != null) account!,
              NavigationBar(
                selectedIndex: destinations
                    .indexWhere((item) => item.id == selected)
                    .clamp(0, destinations.length - 1),
                onDestinationSelected: (index) => index == destinations.length
                    ? onSettings()
                    : onSelected(destinations[index].id),
                destinations: [
                  for (final item in destinations)
                    NavigationDestination(
                      icon: Icon(item.icon),
                      label: item.label,
                    ),
                  const NavigationDestination(
                    icon: Icon(Icons.tune),
                    label: 'Settings',
                  ),
                ],
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 216,
              decoration: BoxDecoration(
                color: colors.surface,
                border: Border(right: BorderSide(color: colors.outlineVariant)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (account != null)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: account!,
                    ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: [
                        for (final item in destinations)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: ListTile(
                              leading: Icon(item.icon, size: 20),
                              title: Text(item.label),
                              selected: selected == item.id,
                              selectedColor: colors.primary,
                              selectedTileColor: colors.primary.withValues(
                                alpha: .08,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              onTap: () => onSelected(item.id),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: ListTile(
                      leading: const Icon(Icons.tune, size: 20),
                      title: const Text('Settings'),
                      onTap: onSettings,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: child),
          ],
        );
      },
    );
  }
}
