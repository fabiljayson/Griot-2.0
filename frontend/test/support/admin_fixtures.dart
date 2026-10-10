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
  // Distinct from `total_quizzes_taken`: the completed subset that
  // `pass_rate` is measured over. The two used to be the same number under a
  // field called "taken", which hid every abandoned attempt.
  'quizzes_completed': 190,
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

/// `/api/stories/moderation_queue/` payload (a list of flagged stories).
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

/// `/api/stories/verification_queue/` payload: two stories awaiting a
/// verification decision — one partly documented, one with nothing on record.
List<Map<String, dynamic>> adminVerificationQueueJson() => [
  {
    'story_id': 31,
    'slug': 'the-baobab-and-the-drum',
    'title': 'The Baobab and the Drum',
    'summary': 'A tale about rhythm and patience.',
    'status': 'under_review',
    'author_username': 'moussa',
    'origin': 'oral_transcription',
    'provenance_notes':
        'Recorded in Foumban in 2019 with the elder\'s permission.',
    'consent_status': 'granted',
    'language': 'en',
    'region': 'Northwest',
    'created_at': '2026-07-01T10:00:00Z',
    'sources': [
      {
        'id': 1,
        'story': 31,
        'source_type': 'COMMUNITY_TESTIMONY',
        'name': 'Elder Njoya testimony',
        'author': '',
        'institution': 'Bamoun council of elders',
        'url': '',
        'reference': 'Told at the Foumban cultural festival',
        'notes': '',
        'is_verified': true,
        'verified_by': 'amina',
        'verified_at': '2026-07-03T09:00:00Z',
        'created_at': '2026-07-01T11:00:00Z',
        'updated_at': '2026-07-03T09:00:00Z',
      },
      {
        'id': 2,
        'story': 31,
        'source_type': 'BOOK',
        'name': 'Tamara vol. II',
        'author': 'Tardits',
        'institution': '',
        'url': '',
        'reference': 'p. 142',
        'notes': '',
        'is_verified': false,
        'verified_by': null,
        'verified_at': null,
        'created_at': '2026-07-01T11:05:00Z',
        'updated_at': '2026-07-01T11:05:00Z',
      },
    ],
    'trust_score': 50,
    'trust_level': 'partial',
    'breakdown': [
      {'criterion': 'source_verified', 'label': 'Reliable/documented source', 'weight': 25, 'confirmed': true},
      {'criterion': 'community_validated', 'label': 'Community validation', 'weight': 25, 'confirmed': true},
      {'criterion': 'expert_validated', 'label': 'Cultural expert/reviewer validation', 'weight': 25, 'confirmed': false},
      {'criterion': 'references_confirmed', 'label': 'Historical/reference evidence', 'weight': 15, 'confirmed': false},
      {'criterion': 'consistency_confirmed', 'label': 'Content consistency', 'weight': 10, 'confirmed': false},
    ],
    'reviewer': 'amina',
    'verified_at': '2026-07-03T09:00:00Z',
  },
  {
    'story_id': 32,
    'slug': 'a-tale-without-a-source',
    'title': 'A Tale Without a Source',
    'summary': '',
    'status': 'pending',
    'author_username': 'kemi',
    'origin': 'seeded',
    'provenance_notes': 'Seeded demonstration content.',
    'consent_status': 'not_requested',
    'language': 'en',
    'region': '',
    'created_at': '2026-07-02T10:00:00Z',
    'sources': [],
    'trust_score': 0,
    'trust_level': 'unverified',
    'breakdown': [
      {'criterion': 'source_verified', 'label': 'Reliable/documented source', 'weight': 25, 'confirmed': false},
      {'criterion': 'community_validated', 'label': 'Community validation', 'weight': 25, 'confirmed': false},
      {'criterion': 'expert_validated', 'label': 'Cultural expert/reviewer validation', 'weight': 25, 'confirmed': false},
      {'criterion': 'references_confirmed', 'label': 'Historical/reference evidence', 'weight': 15, 'confirmed': false},
      {'criterion': 'consistency_confirmed', 'label': 'Content consistency', 'weight': 10, 'confirmed': false},
    ],
    'reviewer': null,
    'verified_at': null,
  },
];

/// `/api/stories/consent_queue/` payload: two stories still awaiting a
/// moderator's decision, one of them live and published.
List<Map<String, dynamic>> adminConsentQueueJson() => [
  {
    'story_id': 21,
    'slug': 'the-baobab-and-the-drum',
    'title': 'The Baobab and the Drum',
    'summary': 'A tale about rhythm and patience.',
    'status': 'published',
    'author_username': 'moussa',
    'origin': 'oral_transcription',
    'provenance_notes': 'Recorded in Foumban in 2019 with the elder\'s permission.',
    'consent_status': 'pending',
    'consent_basis': '',
    'rights_holder': 'The Bamoun council of elders',
    'licence': 'cc_by_nc',
    'language': 'en',
    'region': 'Northwest',
    'created_at': '2026-07-01T10:00:00Z',
    'consent_attested_by': null,
    'consent_attested_at': null,
  },
  {
    'story_id': 22,
    'slug': 'a-tale-without-a-source',
    'title': 'A Tale Without a Source',
    'summary': '',
    'status': 'draft',
    'author_username': 'kemi',
    'origin': 'seeded',
    'provenance_notes': 'Seeded demonstration content.',
    'consent_status': 'not_requested',
    'consent_basis': '',
    'rights_holder': '',
    'licence': 'undetermined',
    'language': 'en',
    'region': '',
    'created_at': '2026-07-02T10:00:00Z',
    'consent_attested_by': null,
    'consent_attested_at': null,
  },
];
