/// Admin dashboard feature — Phase 9.
///
/// Aggregated platform analytics for admins and institution managers:
///   - Overview KPIs (users, stories, quizzes, QR scans)
///   - Growth timelines for users & stories
///   - Content library health & top stories
///   - Gamification leaderboards & quiz performance
///   - Museum artifact / QR scan analytics
///   - Community engagement & moderation signals
library;

// Models
export 'models/analytics_models.dart';
export 'models/moderation_models.dart';

// Services
export 'services/admin_api_service.dart';

// Providers
export 'providers/admin_provider.dart';

// Widgets
export 'widgets/stat_card.dart';
export 'widgets/growth_chart.dart';
export 'widgets/dashboard_section.dart';
export 'widgets/ranked_tile.dart';
export 'widgets/moderation_widgets.dart';

// Screens
export 'screens/admin_dashboard_screen.dart';
