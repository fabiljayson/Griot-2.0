import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../database/repositories/offline_request_repository.dart';
import '../database/repositories/offline_user_repository.dart';
import '../database/repositories/reading_progress_repository.dart';
import '../database/repositories/search_history_repository.dart';
import '../database/repositories/story_cache_repository.dart';
import '../network/api_client.dart';

/// Single shared API client.
final apiClientProvider = Provider<ApiClient>((ref) => ApiClient.instance);

/// The app-wide SQLite helper singleton.
final appDatabaseProvider = Provider<AppDatabase>((ref) => AppDatabase.instance);

/// Offline story cache DAO.
final storyCacheRepositoryProvider = Provider<StoryCacheRepository>(
  (ref) => StoryCacheRepository(),
);

/// Local search history DAO.
final searchHistoryRepositoryProvider = Provider<SearchHistoryRepository>(
  (ref) => SearchHistoryRepository(),
);

/// Reading progress DAO.
final readingProgressRepositoryProvider = Provider<ReadingProgressRepository>(
  (ref) => ReadingProgressRepository(),
);

/// Offline request queue repository.
final offlineRequestRepositoryProvider = Provider<OfflineRequestRepository>(
  (ref) => OfflineRequestRepository(),
);

/// Offline user registration repository.
final offlineUserRepositoryProvider = Provider<OfflineUserRepository>(
  (ref) => OfflineUserRepository(),
);

/// Convenience provider: number of stories saved offline.
final offlineStoryCountProvider = FutureProvider<int>(
  (ref) => ref.watch(storyCacheRepositoryProvider).count(),
);

/// Convenience provider: number of pending offline requests.
final pendingOfflineRequestsProvider = FutureProvider<int>(
  (ref) => ref.watch(offlineRequestRepositoryProvider).getPendingCount(),
);

/// Convenience provider: number of pending offline user registrations.
final pendingOfflineUsersProvider = FutureProvider<int>(
  (ref) => ref.watch(offlineUserRepositoryProvider).getPendingCount(),
);
