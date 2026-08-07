import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
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

/// Convenience provider: number of stories saved offline.
final offlineStoryCountProvider = FutureProvider<int>(
  (ref) => ref.watch(storyCacheRepositoryProvider).count(),
);
