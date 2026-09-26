/// Notifications feature — reader inbox.
///
/// Complete notification system including:
///   - Bell badge on the home header with an unread count
///   - Inbox of new stories, the weekly trending digest and streak nudges
///   - Admin announcements broadcast to every active reader
///   - Daily activity ping that both keeps the reading streak alive and
///     delivers whatever is waiting, since there is no scheduler on the backend
library;

// Models & Services
export 'models/notification_model.dart';
export 'services/notification_api_service.dart';

// Providers
export 'providers/notification_provider.dart';

// Screens
export 'screens/notifications_screen.dart';

// Widgets
export 'widgets/notification_bell.dart';
export 'widgets/daily_activity_pinger.dart';
