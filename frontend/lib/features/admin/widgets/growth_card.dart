import 'package:flutter/material.dart';

import '../models/analytics_models.dart';
import 'dashboard_section.dart';
import 'growth_chart.dart';

/// Growth chart wrapped in a titled card.
class GrowthCard extends StatelessWidget {
  const GrowthCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.data,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final List<GrowthPoint> data;

  @override
  Widget build(BuildContext context) {
    return DashboardSection(
      title: title,
      subtitle: subtitle,
      trailing: Icon(icon, color: color),
      child: GrowthChart(data: data, color: color),
    );
  }
}
