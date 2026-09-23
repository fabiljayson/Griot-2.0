import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Story status labels (mirrors backend Story.Status choices).
const statusLabels = {
  'draft': 'Draft',
  'pending': 'Pending review',
  'published': 'Published',
  'rejected': 'Rejected',
  'archived': 'Archived',
};

String statusLabel(String key) => statusLabels[key] ?? key;

Color statusColorFor(String key) {
  switch (key) {
    case 'published':
      return AppColors.savannahGreen;
    case 'pending':
      return AppColors.ochre;
    case 'rejected':
      return AppColors.error;
    default:
      return AppColors.charcoalMuted;
  }
}
