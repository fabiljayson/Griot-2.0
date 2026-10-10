/// Data models for the admin verification queue.
///
/// Mirrors the backend `StoryViewSet.verification_queue` / `verify` /
/// `verify_source` responses in `backend/stories/views.py`.
library;

import '../../stories/models/story_model.dart';

/// One row of the evidence checklist: what counted, and how much.
///
/// Mirrors `stories.trust.score_breakdown` — the reviewer must see which
/// levers move the score, not just the number the levers produce.
class TrustBreakdownRow {
  const TrustBreakdownRow({
    this.criterion = '',
    this.label = '',
    this.weight = 0,
    this.confirmed = false,
  });

  final String criterion;
  final String label;
  final int weight;
  final bool confirmed;

  factory TrustBreakdownRow.fromJson(Map<String, dynamic> json) {
    return TrustBreakdownRow(
      criterion: json['criterion'] as String? ?? '',
      label: json['label'] as String? ?? '',
      weight: (json['weight'] as num?)?.toInt() ?? 0,
      confirmed: json['confirmed'] as bool? ?? false,
    );
  }
}

/// The verification decisions a reviewer may record, with the wire value the
/// server accepts (`stories.services.VERIFY_ACTIONS`).
enum VerifyAction {
  startReview('start_review', 'Start review'),
  approve('approve', 'Approve'),
  reject('reject', 'Reject'),
  requestChanges('request_changes', 'Request changes');

  const VerifyAction(this.value, this.label);

  final String value;
  final String label;

  factory VerifyAction.fromString(String value) {
    return VerifyAction.values.firstWhere(
      (a) => a.value == value,
      orElse: () => VerifyAction.startReview,
    );
  }
}

/// A story awaiting a verification decision.
///
/// Mirrors one row of `StoryViewSet.verification_queue`
/// (`backend/stories/views.py`). The payload carries the provenance the
/// contributor declared, the attached sources, *and* the evidence checklist
/// with the score it currently produces — a reviewer asked to approve from a
/// title and a number alone is being asked to vouch for documentation they
/// have not seen.
class VerificationQueueEntry {
  const VerificationQueueEntry({
    this.storyId = 0,
    this.slug = '',
    this.title = '',
    this.summary = '',
    this.status = '',
    this.authorUsername = '',
    this.origin = 'unknown',
    this.provenanceNotes = '',
    this.consentStatus = 'not_requested',
    this.language = 'en',
    this.region = '',
    this.createdAt = '',
    this.sources = const [],
    this.trustScore = 0,
    this.trustLevel = 'unverified',
    this.breakdown = const [],
    this.reviewer,
    this.verifiedAt,
  });

  final int storyId;
  final String slug;
  final String title;
  final String summary;
  final String status;
  final String authorUsername;
  final String origin;
  final String provenanceNotes;
  final String consentStatus;
  final String language;
  final String region;
  final String createdAt;
  final List<StorySourceModel> sources;
  final int trustScore;
  final String trustLevel;

  /// Per-criterion rows in display order. Server-computed; this client only
  /// renders them.
  final List<TrustBreakdownRow> breakdown;

  final String? reviewer;
  final String? verifiedAt;

  factory VerificationQueueEntry.fromJson(Map<String, dynamic> json) {
    return VerificationQueueEntry(
      storyId: (json['story_id'] as num?)?.toInt() ?? 0,
      slug: json['slug'] as String? ?? '',
      title: json['title'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      status: json['status'] as String? ?? '',
      authorUsername: json['author_username'] as String? ?? '',
      origin: json['origin'] as String? ?? 'unknown',
      provenanceNotes: json['provenance_notes'] as String? ?? '',
      consentStatus: json['consent_status'] as String? ?? 'not_requested',
      language: json['language'] as String? ?? 'en',
      region: json['region'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
      sources: (json['sources'] as List<dynamic>? ?? [])
          .map((e) => StorySourceModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      trustScore: (json['trust_score'] as num?)?.toInt() ?? 0,
      trustLevel: json['trust_level'] as String? ?? 'unverified',
      breakdown: (json['breakdown'] as List<dynamic>? ?? [])
          .map((e) => TrustBreakdownRow.fromJson(e as Map<String, dynamic>))
          .toList(),
      reviewer: json['reviewer'] as String?,
      verifiedAt: json['verified_at'] as String?,
    );
  }
}

/// What `POST /api/stories/{slug}/verify/` reports back: the story's new
/// status and the score the decision was based on.
class VerificationDecision {
  const VerificationDecision({
    this.slug = '',
    this.status = '',
    this.trustScore = 0,
    this.trustLevel = 'unverified',
    this.breakdown = const [],
    this.consentStatus = 'not_requested',
  });

  final String slug;
  final String status;
  final int trustScore;
  final String trustLevel;
  final List<TrustBreakdownRow> breakdown;
  final String consentStatus;

  factory VerificationDecision.fromJson(Map<String, dynamic> json) {
    return VerificationDecision(
      slug: json['slug'] as String? ?? '',
      status: json['status'] as String? ?? '',
      trustScore: (json['trust_score'] as num?)?.toInt() ?? 0,
      trustLevel: json['trust_level'] as String? ?? 'unverified',
      breakdown: (json['breakdown'] as List<dynamic>? ?? [])
          .map((e) => TrustBreakdownRow.fromJson(e as Map<String, dynamic>))
          .toList(),
      consentStatus: json['consent_status'] as String? ?? 'not_requested',
    );
  }
}
