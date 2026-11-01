import 'package:flutter/material.dart';

class SelectionActionBarItem {
  const SelectionActionBarItem({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
}

class SelectionActionBar extends StatelessWidget {
  const SelectionActionBar({
    super.key,
    required this.selectedCount,
    required this.onClear,
    required this.actions,
  });

  final int selectedCount;
  final VoidCallback onClear;
  final List<SelectionActionBarItem> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final maxWidth = screenWidth < 504
        ? (screenWidth - 24).clamp(0.0, 480.0)
        : 480.0;
    final minimumWidth = maxWidth < 240 ? maxWidth : 240.0;
    final barWidth = (176 + actions.length * 40.0).clamp(
      minimumWidth,
      maxWidth,
    );

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: barWidth,
          child: Material(
            color: theme.colorScheme.surface,
            elevation: 10,
            shadowColor: Colors.black.withValues(alpha: 0.24),
            borderRadius: BorderRadius.circular(18),
            child: LayoutBuilder(
              builder: (context, constraints) {
                const actionWidth = 40.0;
                const reservedLeadingWidth = 154.0;
                final availableSlots = actions.isEmpty
                    ? 0
                    : ((constraints.maxWidth - reservedLeadingWidth) /
                              actionWidth)
                          .floor()
                          .clamp(1, actions.length);
                final hasOverflow = actions.length > availableSlots;
                final visibleCount = hasOverflow
                    ? (availableSlots - 1).clamp(0, actions.length)
                    : actions.length;
                final firstVisible = actions.length - visibleCount;
                final overflowActions = hasOverflow
                    ? actions.take(firstVisible).toList(growable: false)
                    : const <SelectionActionBarItem>[];
                final visibleActions = actions
                    .skip(firstVisible)
                    .toList(growable: false);

                return Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 6,
                    horizontal: 10,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close),
                        onPressed: onClear,
                        tooltip: 'Clear selection',
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '$selectedCount selected',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      if (overflowActions.isNotEmpty)
                        PopupMenuButton<SelectionActionBarItem>(
                          tooltip: 'More actions',
                          icon: const Icon(Icons.more_horiz_rounded),
                          onSelected: (action) => action.onPressed(),
                          itemBuilder: (context) => [
                            for (final action in overflowActions)
                              PopupMenuItem<SelectionActionBarItem>(
                                value: action,
                                child: Row(
                                  children: [
                                    Icon(action.icon, size: 20),
                                    const SizedBox(width: 12),
                                    Flexible(child: Text(action.tooltip)),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      for (final action in visibleActions)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: Icon(action.icon),
                          onPressed: action.onPressed,
                          tooltip: action.tooltip,
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
