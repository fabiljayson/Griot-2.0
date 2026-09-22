import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_icons.dart';

/// Platform metrics row displayed in branding panels.
///
/// Shows Stories, Museums, and Free-always stats with icons.
/// Shared between login, register, and loading screens.
class BrandMetricsRow extends StatelessWidget {
  const BrandMetricsRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const BrandMetricItem(
          icon: AppIcons.auto_stories_outlined,
          value: '340+',
          label: 'Stories',
        ),
        BrandMetricDivider(),
        const BrandMetricItem(
          icon: AppIcons.museum_outlined,
          value: '28',
          label: 'Museums',
        ),
        BrandMetricDivider(),
        const BrandMetricItem(
          icon: AppIcons.favorite_outline,
          value: 'Free',
          label: 'Always',
        ),
      ],
    );
  }
}

/// Single metric item within the metrics row.
class BrandMetricItem extends StatelessWidget {
  const BrandMetricItem({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: AppColors.bronzeDark,
            size: 20,
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Fraunces',
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.charcoal,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'PlusJakartaSans',
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppColors.muted,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Vertical divider between metric items.
class BrandMetricDivider extends StatelessWidget {
  const BrandMetricDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      width: 1,
      color: AppColors.terracotta.withValues(alpha: 0.3),
    );
  }
}
