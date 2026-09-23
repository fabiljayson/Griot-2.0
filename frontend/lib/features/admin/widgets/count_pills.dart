import 'package:flutter/material.dart';

/// Generic count pills row (used for story status & language breakdowns).
class CountPills extends StatelessWidget {
  const CountPills({
    super.key,
    required this.items,
    required this.labelFor,
    required this.colorFor,
  });

  final Map<String, int> items;
  final String Function(String key) labelFor;
  final Color Function(String key) colorFor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (items.isEmpty) {
      return Text(
        'No data yet',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final entry in items.entries)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: colorFor(entry.key).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: colorFor(entry.key).withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  labelFor(entry.key),
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${entry.value}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: colorFor(entry.key),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
