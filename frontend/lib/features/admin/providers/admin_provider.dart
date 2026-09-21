import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/analytics_models.dart';
import '../models/moderation_models.dart';
import '../services/admin_api_service.dart';

/// Complete dashboard summary provider.
///
/// Fetches `/api/analytics/dashboard/` — the single payload powering the
/// admin dashboard. Pull-to-refresh re-computes it in place so the previous
/// data stays visible while loading.
final dashboardSummaryProvider = FutureProvider.autoDispose<DashboardSummary>((
  ref,
) async {
  return AdminApiService.instance.getDashboardSummary();
});

/// State of an in-flight moderation action.
class ModerationState {
  const ModerationState({this.busyStoryId, this.busyAction, this.errorMessage});

  final int? busyStoryId;

  /// The action being processed (`remove` or `dismiss`) when busy.
  final String? busyAction;
  final String? errorMessage;

  bool get isSubmitting => busyStoryId != null;
}

/// Notifier performing moderation actions (remove / dismiss) on flagged
/// stories and reporting which story is currently being processed.
class ModerationNotifier extends StateNotifier<ModerationState> {
  ModerationNotifier() : super(const ModerationState());

  final AdminApiService _api = AdminApiService.instance;

  /// Run a moderation action. Returns true on success.
  Future<bool> moderate({
    required FlaggedStory story,
    required String action,
    String notes = '',
  }) async {
    state = ModerationState(busyStoryId: story.storyId, busyAction: action);
    try {
      await _api.moderateStory(slug: story.slug, action: action, notes: notes);
      state = const ModerationState();
      return true;
    } catch (e) {
      state = ModerationState(errorMessage: 'Moderation failed: $e');
      return false;
    }
  }
}

/// Moderation action state provider.
final moderationProvider =
    StateNotifierProvider<ModerationNotifier, ModerationState>(
      (ref) => ModerationNotifier(),
    );

/// Unresolved flagged stories awaiting review (admin only).
final moderationQueueProvider = FutureProvider.autoDispose<List<FlaggedStory>>((
  ref,
) async {
  return AdminApiService.instance.getModerationQueue();
});
