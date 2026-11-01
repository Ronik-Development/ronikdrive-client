import 'package:flutter/material.dart';

/// Preserves readable labels instead of shrinking the user's chosen text size.
class AdaptiveChoiceControl<T> extends StatelessWidget {
  const AdaptiveChoiceControl({
    super.key,
    required this.labels,
    required this.selected,
    required this.onChanged,
  });

  final Map<T, String> labels;
  final T selected;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final style = Theme.of(context).textTheme.labelLarge!;
      var widest = 0.0;
      for (final label in labels.values) {
        final painter = TextPainter(
          text: TextSpan(text: label, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        if (painter.width > widest) widest = painter.width;
        painter.dispose();
      }
      final vertical = (widest + 48) * labels.length > constraints.maxWidth;
      if (vertical) {
        final colors = Theme.of(context).colorScheme;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final entry in labels.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Semantics(
                  selected: selected == entry.key,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      backgroundColor: selected == entry.key
                          ? colors.secondaryContainer
                          : null,
                      foregroundColor: selected == entry.key
                          ? colors.onSecondaryContainer
                          : null,
                    ),
                    onPressed: onChanged == null
                        ? null
                        : () => onChanged!(entry.key),
                    child: Text(entry.value, textAlign: TextAlign.center),
                  ),
                ),
              ),
          ],
        );
      }
      return SegmentedButton<T>(
        expandedInsets: EdgeInsets.zero,
        showSelectedIcon: false,
        style: const ButtonStyle(
          minimumSize: WidgetStatePropertyAll(Size(48, 48)),
        ),
        segments: [
          for (final entry in labels.entries)
            ButtonSegment(value: entry.key, label: Text(entry.value)),
        ],
        selected: {selected},
        onSelectionChanged: onChanged == null
            ? null
            : (values) => onChanged!(values.first),
      );
    },
  );
}
