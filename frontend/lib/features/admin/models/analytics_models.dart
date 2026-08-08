/// Data models for the admin analytics API.
///
/// Mirrors the backend `api/serializers_analytics.py` response shapes.
library;

/// A single point on a growth timeline (daily counts).
class GrowthPoint {
  const GrowthPoint({required this.date, required this.count});

  final String date;
  final int count;

  factory GrowthPoint.fromJson(Map<String, dynamic> json) {
    return GrowthPoint(
      date: json['date'] as String? ?? '',
      count: (json['count'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Aggregated user statistics.
class UserStats {
  const UserStats({
    this.totalUsers = 0,
    this.activeUsers30d = 0,
    this.usersByRole = const {},
    this.userGrowth = const [],
  });

  final int totalUsers;
  final int activeUsers30d;
  final Map<String, int> usersByRole;
  final List<GrowthPoint> userGrowth;

  factory UserStats.fromJson(Map<String, dynamic> json) {
    final rawRoles = json['users_by_role'] as Map<String, dynamic>? ?? {};
    return UserStats(
      totalUsers: (json['total_users'] as num?)?.toInt() ?? 0,
      activeUsers30d: (json['active_users_30d'] as num?)?.toInt() ?? 0,
      usersByRole: rawRoles.map(
        (key, value) => MapEntry(key, (value as num?)?.toInt() ?? 0),
      ),
      userGrowth: _parseGrowth(json['user_growth']),
    );
  }
}

/// A story in the top-stories leaderboard.
class TopStory {
  const TopStory({
    this.id = 0,
    this.title = '',
    this.viewCount = 0,
    this.likeCount = 0,
    this.bookmarkCount = 0,
    this.shareCount = 0,
  });

  final int id;
  final String title;
  final int viewCount;
  final int likeCount;
  final int bookmarkCount;
  final int shareCount;

  factory TopStory.fromJson(Map<String, dynamic> json) {
    return TopStory(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: json['title'] as String? ?? '',
      viewCount: (json['view_count'] as num?)?.toInt() ?? 0,
      likeCount: (json['like_count'] as num?)?.toInt() ?? 0,
      bookmarkCount: (json['bookmark_count'] as num?)?.toInt() ?? 0,
      shareCount: (json['share_count'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Aggregated story statistics.
class StoryStats {
  const StoryStats({
    this.totalStories = 0,
    this.storiesByStatus = const {},
    this.storiesByLanguage = const {},
    this.totalViews = 0,
    this.totalLikes = 0,
    this.totalBookmarks = 0,
    this.totalShares = 0,
    this.topStories = const [],
    this.storyGrowth = const [],
    this.pendingReview = 0,
  });

  final int totalStories;
  final Map<String, int> storiesByStatus;
  final Map<String, int> storiesByLanguage;
  final int totalViews;
  final int totalLikes;
  final int totalBookmarks;
  final int totalShares;
  final List<TopStory> topStories;
  final List<GrowthPoint> storyGrowth;
  final int pendingReview;

  factory StoryStats.fromJson(Map<String, dynamic> json) {
    final engagement = json['engagement'] as Map<String, dynamic>? ?? {};
    return StoryStats(
      totalStories: (json['total_stories'] as num?)?.toInt() ?? 0,
      storiesByStatus: _stringToIntMap(
        json['stories_by_status'] as Map<String, dynamic>?,
      ),
      storiesByLanguage: _stringToIntMap(
        json['stories_by_language'] as Map<String, dynamic>?,
      ),
      totalViews: (engagement['total_views'] as num?)?.toInt() ?? 0,
      totalLikes: (engagement['total_likes'] as num?)?.toInt() ?? 0,
      totalBookmarks: (engagement['total_bookmarks'] as num?)?.toInt() ?? 0,
      totalShares: (engagement['total_shares'] as num?)?.toInt() ?? 0,
      topStories: (json['top_stories'] as List<dynamic>? ?? [])
          .map((e) => TopStory.fromJson(e as Map<String, dynamic>))
          .toList(),
      storyGrowth: _parseGrowth(json['story_growth']),
      pendingReview: (json['pending_review'] as num?)?.toInt() ?? 0,
    );
  }
}

/// A user on the gamification leaderboard.
class TopUser {
  const TopUser({
    this.username = '',
    this.totalXp = 0,
    this.level = 1,
    this.storiesRead = 0,
    this.quizzesPassed = 0,
    this.currentStreak = 0,
  });

  final String username;
  final int totalXp;
  final int level;
  final int storiesRead;
  final int quizzesPassed;
  final int currentStreak;

  factory TopUser.fromJson(Map<String, dynamic> json) {
    return TopUser(
      username: json['user__username'] as String? ?? '',
      totalXp: (json['total_xp'] as num?)?.toInt() ?? 0,
      level: (json['level'] as num?)?.toInt() ?? 1,
      storiesRead: (json['stories_read'] as num?)?.toInt() ?? 0,
      quizzesPassed: (json['quizzes_passed'] as num?)?.toInt() ?? 0,
      currentStreak: (json['current_streak'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Per-quiz attempt / pass counts.
class QuizStat {
  const QuizStat({
    this.id = 0,
    this.title = '',
    this.attemptCount = 0,
    this.passCount = 0,
  });

  final int id;
  final String title;
  final int attemptCount;
  final int passCount;

  factory QuizStat.fromJson(Map<String, dynamic> json) {
    return QuizStat(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: json['title'] as String? ?? '',
      attemptCount: (json['attempt_count'] as num?)?.toInt() ?? 0,
      passCount: (json['pass_count'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Aggregated gamification statistics.
class GamificationStats {
  const GamificationStats({
    this.totalQuizzesTaken = 0,
    this.quizzesPassed = 0,
    this.passRate = 0.0,
    this.avgScore = 0.0,
    this.totalXpEarned = 0,
    this.badgesEarned = 0,
    this.topUsers = const [],
    this.quizStats = const [],
  });

  final int totalQuizzesTaken;
  final int quizzesPassed;
  final double passRate;
  final double avgScore;
  final int totalXpEarned;
  final int badgesEarned;
  final List<TopUser> topUsers;
  final List<QuizStat> quizStats;

  factory GamificationStats.fromJson(Map<String, dynamic> json) {
    return GamificationStats(
      totalQuizzesTaken: (json['total_quizzes_taken'] as num?)?.toInt() ?? 0,
      quizzesPassed: (json['quizzes_passed'] as num?)?.toInt() ?? 0,
      passRate: (json['pass_rate'] as num?)?.toDouble() ?? 0.0,
      avgScore: (json['avg_score'] as num?)?.toDouble() ?? 0.0,
      totalXpEarned: (json['total_xp_earned'] as num?)?.toInt() ?? 0,
      badgesEarned: (json['badges_earned'] as num?)?.toInt() ?? 0,
      topUsers: (json['top_users'] as List<dynamic>? ?? [])
          .map((e) => TopUser.fromJson(e as Map<String, dynamic>))
          .toList(),
      quizStats: (json['quiz_stats'] as List<dynamic>? ?? [])
          .map((e) => QuizStat.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// A top-scanned museum artifact.
class TopArtifact {
  const TopArtifact({
    this.id = 0,
    this.title = '',
    this.museumName = '',
    this.scanCount = 0,
  });

  final int id;
  final String title;
  final String museumName;
  final int scanCount;

  factory TopArtifact.fromJson(Map<String, dynamic> json) {
    return TopArtifact(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: json['title'] as String? ?? '',
      museumName: json['museum_name'] as String? ?? '',
      scanCount: (json['scan_count'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Aggregated QR / artifact statistics.
class QRStats {
  const QRStats({
    this.totalArtifacts = 0,
    this.publishedArtifacts = 0,
    this.totalScans = 0,
    this.uniqueScanners = 0,
    this.scanGrowth = const [],
    this.topArtifacts = const [],
  });

  final int totalArtifacts;
  final int publishedArtifacts;
  final int totalScans;
  final int uniqueScanners;
  final List<GrowthPoint> scanGrowth;
  final List<TopArtifact> topArtifacts;

  factory QRStats.fromJson(Map<String, dynamic> json) {
    return QRStats(
      totalArtifacts: (json['total_artifacts'] as num?)?.toInt() ?? 0,
      publishedArtifacts: (json['published_artifacts'] as num?)?.toInt() ?? 0,
      totalScans: (json['total_scans'] as num?)?.toInt() ?? 0,
      uniqueScanners: (json['unique_scanners'] as num?)?.toInt() ?? 0,
      scanGrowth: _parseGrowth(json['scan_growth']),
      topArtifacts: (json['top_artifacts'] as List<dynamic>? ?? [])
          .map((e) => TopArtifact.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Activity counts over the last 7 days.
class RecentActivity {
  const RecentActivity({
    this.newUsers = 0,
    this.newStories = 0,
    this.quizAttempts = 0,
    this.qrScans = 0,
    this.shares = 0,
  });

  final int newUsers;
  final int newStories;
  final int quizAttempts;
  final int qrScans;
  final int shares;

  factory RecentActivity.fromJson(Map<String, dynamic> json) {
    return RecentActivity(
      newUsers: (json['new_users'] as num?)?.toInt() ?? 0,
      newStories: (json['new_stories'] as num?)?.toInt() ?? 0,
      quizAttempts: (json['quiz_attempts'] as num?)?.toInt() ?? 0,
      qrScans: (json['qr_scans'] as num?)?.toInt() ?? 0,
      shares: (json['shares'] as num?)?.toInt() ?? 0,
    );
  }
}

/// High-level engagement summary.
class EngagementSummary {
  const EngagementSummary({
    this.totalReadingTime = 0,
    this.completedReadings = 0,
    this.totalLikes = 0,
    this.totalBookmarks = 0,
    this.totalShares = 0,
    this.totalFlags = 0,
    this.unresolvedFlags = 0,
    this.recentActivity = const RecentActivity(),
  });

  /// Sum of tracked reading positions (character indices) — not minutes.
  final int totalReadingTime;
  final int completedReadings;
  final int totalLikes;
  final int totalBookmarks;
  final int totalShares;
  final int totalFlags;
  final int unresolvedFlags;
  final RecentActivity recentActivity;

  factory EngagementSummary.fromJson(Map<String, dynamic> json) {
    return EngagementSummary(
      totalReadingTime: (json['total_reading_time'] as num?)?.toInt() ?? 0,
      completedReadings: (json['completed_readings'] as num?)?.toInt() ?? 0,
      totalLikes: (json['total_likes'] as num?)?.toInt() ?? 0,
      totalBookmarks: (json['total_bookmarks'] as num?)?.toInt() ?? 0,
      totalShares: (json['total_shares'] as num?)?.toInt() ?? 0,
      totalFlags: (json['total_flags'] as num?)?.toInt() ?? 0,
      unresolvedFlags: (json['unresolved_flags'] as num?)?.toInt() ?? 0,
      recentActivity: RecentActivity.fromJson(
        json['recent_activity_7d'] as Map<String, dynamic>? ?? {},
      ),
    );
  }
}

/// The complete dashboard payload (`/api/analytics/dashboard/`).
class DashboardSummary {
  const DashboardSummary({
    this.users = const UserStats(),
    this.stories = const StoryStats(),
    this.gamification = const GamificationStats(),
    this.qrCodes = const QRStats(),
    this.engagement = const EngagementSummary(),
  });

  final UserStats users;
  final StoryStats stories;
  final GamificationStats gamification;
  final QRStats qrCodes;
  final EngagementSummary engagement;

  factory DashboardSummary.fromJson(Map<String, dynamic> json) {
    return DashboardSummary(
      users: UserStats.fromJson(json['users'] as Map<String, dynamic>? ?? {}),
      stories: StoryStats.fromJson(
        json['stories'] as Map<String, dynamic>? ?? {},
      ),
      gamification: GamificationStats.fromJson(
        json['gamification'] as Map<String, dynamic>? ?? {},
      ),
      qrCodes: QRStats.fromJson(
        json['qr_codes'] as Map<String, dynamic>? ?? {},
      ),
      engagement: EngagementSummary.fromJson(
        json['engagement'] as Map<String, dynamic>? ?? {},
      ),
    );
  }
}

// --- Helpers ---------------------------------------------------------------

List<GrowthPoint> _parseGrowth(List<dynamic>? raw) {
  return (raw ?? [])
      .map((e) => GrowthPoint.fromJson(e as Map<String, dynamic>))
      .toList();
}

Map<String, int> _stringToIntMap(Map<String, dynamic>? raw) {
  return (raw ?? {}).map(
    (key, value) => MapEntry(key, (value as num?)?.toInt() ?? 0),
  );
}
