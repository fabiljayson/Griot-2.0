import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../models/analytics_models.dart';

/// Simple, dependency-free bar chart for growth timelines.
///
/// Renders daily counts as vertical bars with date labels at the start,
/// middle, and end of the window.
class GrowthChart extends StatelessWidget {
  const GrowthChart({
    super.key,
    required this.data,
    this.color = AppColors.terracotta,
    this.maxBars = 14,
  });

  final List<GrowthPoint> data;
  final Color color;
  final int maxBars;

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  String _shortDate(String iso) {
    try {
      final d = DateTime.parse(iso);
      return '${d.day} ${_months[d.month - 1]}';
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final points = data.length <= maxBars
        ? List.of(data)
        : data.sublist(data.length - maxBars);

    if (points.isEmpty) {
      return Container(
        height: 130,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.4,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          'No activity recorded yet',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final maxValue = points.fold<int>(0, (m, p) => p.count > m ? p.count : m);
    final safeMax = maxValue == 0 ? 1 : maxValue;
    const chartHeight = 110.0;
    final mid = points[points.length ~/ 2];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final p in points)
              Expanded(
                child: Tooltip(
                  message: '${_shortDate(p.date)}: ${p.count}',
                  child: Container(
                    height: chartHeight,
                    alignment: Alignment.bottomCenter,
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOut,
                      height: p.count == 0
                          ? 2
                          : (p.count / safeMax) * chartHeight,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [color.withValues(alpha: 0.5), color],
                        ),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(
              _shortDate(points.first.date),
              style: theme.textTheme.labelSmall,
            ),
            const Spacer(),
            if (points.length > 2)
              Text(
                _shortDate(mid.date),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            const Spacer(),
            Text(
              _shortDate(points.last.date),
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ],
    );
  }
}
