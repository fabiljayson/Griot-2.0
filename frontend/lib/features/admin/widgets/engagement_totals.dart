import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../models/analytics_models.dart';
import 'stat_card.dart';
import 'value_formatters.dart';

/// Total engagement counters (views / likes / bookmarks / shares).
class EngagementTotals extends StatelessWidget {
  const EngagementTotals({super.key, required this.stories});

  final StoryStats stories;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: MiniStat(
            icon: AppIcons.visibility_outlined,
            label: 'Views',
            value: formatCount(stories.totalViews),
            color: AppColors.terracotta,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: MiniStat(
            icon: AppIcons.favorite_outline,
            label: 'Likes',
            value: formatCount(stories.totalLikes),
            color: AppColors.ochre,
          ),
        ),
      ],
    );
  }
}
