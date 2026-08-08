/// Shared JSON fixtures for admin analytics tests.
///
/// Shapes mirror the backend `api/serializers_analytics.py` responses so the
/// Flutter models and API service are tested against realistic payloads.
library;

Map<String, dynamic> adminUserStatsJson() => {
  'total_users': 142,
  'active_users_30d': 58,
  'users_by_role': {
    'visitor': 90,
    'contributor': 40,
    'institution_manager': 6,
    'admin': 6,
  },
  'user_growth': [
    {'date': '2026-07-01', 'count': 3},
    {'date': '2026-07-02', 'count': 5},
    {'date': '2026-07-03', 'count': 0},
  ],
};

Map<String, dynamic> adminStoryStatsJson() => {
  'total_stories': 87,
  'stories_by_status': {
    'draft': 9,
    'pending': 3,
    'published': 74,
    'rejected': 1,
  },
  'stories_by_language': {'en': 60, 'fr': 10, 'ful': 2, 'dua': 1, 'ewo': 1},
  'engagement': {
    'total_views': 12500,
    'total_likes': 842,
    'total_bookmarks': 391,
    'total_shares': 156,
  },
  'top_stories': [
    {
      'id': 1,
      'title': 'The Wise Spider',
      'view_count': 3200,
      'like_count': 210,
      'bookmark_count': 95,
      'share_count': 44,
    },
    {
      'id': 2,
      'title': 'Tortoise and the Drum',
      'view_count': 2800,
      'like_count': 180,
      'bookmark_count': 70,
      'share_count': 30,
    },
  ],
  'story_growth': [
    {'date': '2026-07-01', 'count': 1},
    {'date': '2026-07-02', 'count': 2},
  ],
  'pending_review': 3,
};

Map<String, dynamic> adminGamificationJson() => {
  'total_quizzes_taken': 214,
  'quizzes_passed': 168,
  'pass_rate': 78.5,
  'avg_score': 81.0,
  'total_xp_earned': 12200,
  'badges_earned': 96,
  'top_users': [
    {
      'user__username': 'kemi',
      'total_xp': 1450,
      'level': 14,
      'stories_read': 32,
      'quizzes_passed': 12,
      'current_streak': 7,
    },
  ],
  'quiz_stats': [
    {
      'id': 1,
      'title': 'Wise Spider Quiz',
      'attempt_count': 120,
      'pass_count': 95,
    },
  ],
};

Map<String, dynamic> adminQrJson() => {
  'total_artifacts': 45,
  'published_artifacts': 40,
  'total_scans': 987,
  'unique_scanners': 312,
  'scan_growth': [
    {'date': '2026-07-01', 'count': 12},
    {'date': '2026-07-02', 'count': 18},
  ],
  'top_artifacts': [
    {
      'id': 1,
      'title': 'Bamoun Mask',
      'museum_name': 'Musée du Cameroun',
      'scan_count': 210,
    },
  ],
};

Map<String, dynamic> adminEngagementJson() => {
  'total_reading_time': 148200,
  'completed_readings': 63,
  'total_likes': 842,
  'total_bookmarks': 391,
  'total_shares': 156,
  'total_flags': 4,
  'unresolved_flags': 1,
  'recent_activity_7d': {
    'new_users': 12,
    'new_stories': 4,
    'quiz_attempts': 36,
    'qr_scans': 58,
    'shares': 19,
  },
};

/// `/api/stories/moderation-queue/` payload (a list of flagged stories).
List<Map<String, dynamic>> adminModerationQueueJson() => [
  {
    'story_id': 11,
    'slug': 'the-wrong-spider',
    'title': 'The Wrong Spider',
    'status': 'published',
    'author_username': 'author1',
    'flags': [
      {
        'id': 1,
        'reason': 'cultural_inaccuracy',
        'reason_display': 'Cultural Inaccuracy',
        'details': 'The story misrepresents traditional customs.',
        'reporter': 'reader1',
        'created_at': '2026-07-01T10:00:00Z',
      },
      {
        'id': 2,
        'reason': 'inappropriate_content',
        'reason_display': 'Inappropriate Content',
        'details': '',
        'reporter': 'reader2',
        'created_at': '2026-07-02T10:00:00Z',
      },
    ],
  },
];

/// Complete `/api/analytics/dashboard/` payload.
Map<String, dynamic> adminDashboardJson() => {
  'users': adminUserStatsJson(),
  'stories': adminStoryStatsJson(),
  'gamification': adminGamificationJson(),
  'qr_codes': adminQrJson(),
  'engagement': adminEngagementJson(),
};
