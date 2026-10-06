import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_provider.dart';
import '../models/analytics_models.dart';
import '../models/moderation_models.dart';
import '../models/qr_worklist_models.dart';
import '../services/admin_api_service.dart';

/// Admin API service wired to the authenticated client.
///
/// Every admin endpoint (analytics, moderation queue, consent queue, QR
/// worklist) requires a Bearer token — `IsAdminOrManager` on the backend.
/// `AdminApiService.instance` falls back to the bare `ApiClient.instance`,
/// which carries no `AuthInterceptor`, so all admin calls used to leave the
/// device anonymous and came back 401 (or, worse, would be served if the
/// server ever loosened).
final adminApiServiceProvider = Provider<AdminApiService>((ref) {
  return AdminApiService(
    dio: ref.watch(authenticatedApiClientProvider).dio,
  );
});

/// Complete dashboard summary provider.
///
/// Fetches `/api/analytics/dashboard/` — the single payload powering the
/// admin dashboard. Pull-to-refresh re-computes it in place so the previous
/// data stays visible while loading.
final dashboardSummaryProvider = FutureProvider.autoDispose<DashboardSummary>((
  ref,
) async {
  return ref.watch(adminApiServiceProvider).getDashboardSummary();
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
  ModerationNotifier(AdminApiService api)
      : _api = api,
        super(const ModerationState());

  final AdminApiService _api;

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
      (ref) => ModerationNotifier(ref.watch(adminApiServiceProvider)),
    );

/// Unresolved flagged stories awaiting review (admin only).
final moderationQueueProvider = FutureProvider.autoDispose<List<FlaggedStory>>((
  ref,
) async {
  return ref.watch(adminApiServiceProvider).getModerationQueue();
});

/// Every platform user, newest first.
///
/// Covers accounts from both the local and deployed databases once
/// `sync_local_users` has copied the local ones into the deploy database.
final adminUsersProvider = FutureProvider.autoDispose<List<AdminUser>>((
  ref,
) async {
  return ref.watch(adminApiServiceProvider).getUsers();
});

/// State of an in-flight consent decision.
class ConsentActionState {
  const ConsentActionState({this.busySlug, this.errorMessage});

  /// The story whose decision is being recorded, if any.
  final String? busySlug;
  final String? errorMessage;

  bool isBusy(String slug) => busySlug == slug;
  bool get isSubmitting => busySlug != null;
}

/// Notifier recording a moderator's consent decision.
///
/// Kept separate from [ModerationNotifier] because the two answer to different
/// obligations: flags are about a complaint, consent about someone's tradition.
/// Merging them into one "moderation" state would let a reviewer lose track of
/// which record they were in the middle of writing.
class ConsentActionNotifier extends StateNotifier<ConsentActionState> {
  ConsentActionNotifier(AdminApiService api)
      : _api = api,
        super(const ConsentActionState());

  final AdminApiService _api;

  /// Record a decision. Returns true on success.
  ///
  /// On success the caller is expected to refresh [consentQueueProvider]: the
  /// story leaves the queue, and reading that from the response rather than
  /// from the list is how the two would drift.
  Future<bool> record({
    required String slug,
    required String status,
    required String basis,
    String? rightsHolder,
    String? licence,
  }) async {
    state = ConsentActionState(busySlug: slug);
    try {
      await _api.recordStoryConsent(
        slug: slug,
        status: status,
        basis: basis,
        rightsHolder: rightsHolder,
        licence: licence,
      );
      state = const ConsentActionState();
      return true;
    } catch (e) {
      state = ConsentActionState(errorMessage: 'Could not record consent: $e');
      return false;
    }
  }
}

/// The stories a moderator still owes a consent decision on.
final consentQueueProvider = FutureProvider.autoDispose<List<ConsentReviewStory>>(
  (ref) async {
    return ref.watch(adminApiServiceProvider).getConsentQueue();
  },
);

/// Consent decision state provider.
final consentActionProvider =
    StateNotifierProvider<ConsentActionNotifier, ConsentActionState>(
      (ref) => ConsentActionNotifier(ref.watch(adminApiServiceProvider)),
    );

/// The artifacts still missing a printable QR code (manager/admin only).
final qrWorklistProvider = FutureProvider.autoDispose<QrWorklist>((ref) async {
  return ref.watch(adminApiServiceProvider).getQrWorklist();
});

/// State of an in-flight QR generation.
class QrGenerationState {
  const QrGenerationState({this.busySlug, this.generatingAll = false, this.errorMessage});

  /// The single artifact being regenerated, if that is what is in flight.
  final String? busySlug;

  /// True while the "everything still missing" button is running.
  final bool generatingAll;

  final String? errorMessage;

  bool isBusy(String slug) => busySlug == slug;
  bool get isSubmitting => busySlug != null || generatingAll;
}

/// Notifier generating QR codes from the worklist.
///
/// On success the caller refreshes [qrWorklistProvider]: a generated row moves
/// out of "no code yet", and reading that from the local list rather than from
/// the server's ordering is how the screen would claim an object is still
/// unlabelled moments after labelling it.
class QrGenerationNotifier extends StateNotifier<QrGenerationState> {
  QrGenerationNotifier(AdminApiService api)
      : _api = api,
        super(const QrGenerationState());

  final AdminApiService _api;

  /// Regenerate one artifact's code. Returns the outcome, or null on failure.
  Future<QrWorklistGeneration?> generateOne(String slug) async {
    state = QrGenerationState(busySlug: slug);
    try {
      final result = await _api.generateQrCodes(slugs: [slug]);
      state = const QrGenerationState();
      return result;
    } catch (e) {
      state = QrGenerationState(errorMessage: 'Could not generate the QR code: $e');
      return null;
    }
  }

  /// Generate for every artifact with no code yet. Returns the outcome, or
  /// null on failure.
  Future<QrWorklistGeneration?> generateAllMissing() async {
    state = const QrGenerationState(generatingAll: true);
    try {
      final result = await _api.generateQrCodes();
      state = const QrGenerationState();
      return result;
    } catch (e) {
      state = QrGenerationState(errorMessage: 'Could not generate the QR codes: $e');
      return null;
    }
  }
}

/// QR generation state provider.
final qrGenerationProvider =
    StateNotifierProvider<QrGenerationNotifier, QrGenerationState>(
      (ref) => QrGenerationNotifier(ref.watch(adminApiServiceProvider)),
    );
