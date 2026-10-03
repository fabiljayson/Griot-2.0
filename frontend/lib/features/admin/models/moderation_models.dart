/// Data models for the admin moderation queue.
///
/// Mirrors the backend `StoryViewSet.moderation_queue` / `moderate` responses
/// in `backend/stories/views.py`.
library;

/// A single report/flag on a story.
class FlagDetail {
  const FlagDetail({
    this.id = 0,
    this.reason = '',
    this.reasonDisplay = '',
    this.details = '',
    this.reporter = '',
    this.createdAt = '',
  });

  final int id;
  final String reason;
  final String reasonDisplay;
  final String details;
  final String reporter;
  final String createdAt;

  factory FlagDetail.fromJson(Map<String, dynamic> json) {
    return FlagDetail(
      id: (json['id'] as num?)?.toInt() ?? 0,
      reason: json['reason'] as String? ?? '',
      reasonDisplay: json['reason_display'] as String? ?? '',
      details: json['details'] as String? ?? '',
      reporter: json['reporter'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
    );
  }
}

/// A flagged story awaiting moderation, with its unresolved flags.
class FlaggedStory {
  const FlaggedStory({
    this.storyId = 0,
    this.slug = '',
    this.title = '',
    this.status = '',
    this.authorUsername = '',
    this.flags = const [],
  });

  final int storyId;
  final String slug;
  final String title;
  final String status;
  final String authorUsername;
  final List<FlagDetail> flags;

  factory FlaggedStory.fromJson(Map<String, dynamic> json) {
    return FlaggedStory(
      storyId: (json['story_id'] as num?)?.toInt() ?? 0,
      slug: json['slug'] as String? ?? '',
      title: json['title'] as String? ?? '',
      status: json['status'] as String? ?? '',
      authorUsername: json['author_username'] as String? ?? '',
      flags: (json['flags'] as List<dynamic>? ?? [])
          .map((e) => FlagDetail.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// A story still awaiting a moderator's consent decision.
///
/// Mirrors one row of `StoryViewSet.consent_queue`
/// (`backend/stories/views.py`), whose membership rule lives in
/// `stories.services.consent_review_queue`. The payload deliberately carries
/// what the contributor *declared* about the text as well as the current
/// consent state: a moderator is being asked to decide on someone else's
/// tradition, and cannot do that from a status alone.
class ConsentReviewStory {
  const ConsentReviewStory({
    this.storyId = 0,
    this.slug = '',
    this.title = '',
    this.summary = '',
    this.status = '',
    this.authorUsername = '',
    this.origin = 'unknown',
    this.provenanceNotes = '',
    this.consentStatus = 'not_requested',
    this.consentBasis = '',
    this.rightsHolder = '',
    this.licence = 'undetermined',
    this.language = 'en',
    this.region = '',
    this.createdAt = '',
    this.consentAttestedBy,
    this.consentAttestedAt,
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
  final String consentBasis;
  final String rightsHolder;
  final String licence;
  final String language;
  final String region;
  final String createdAt;

  /// Non-null only when a moderator previously recorded a decision that a
  /// later change sent back to an undecided state.
  final String? consentAttestedBy;
  final String? consentAttestedAt;

  factory ConsentReviewStory.fromJson(Map<String, dynamic> json) {
    return ConsentReviewStory(
      storyId: (json['story_id'] as num?)?.toInt() ?? 0,
      slug: json['slug'] as String? ?? '',
      title: json['title'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      status: json['status'] as String? ?? '',
      authorUsername: json['author_username'] as String? ?? '',
      origin: json['origin'] as String? ?? 'unknown',
      provenanceNotes: json['provenance_notes'] as String? ?? '',
      consentStatus: json['consent_status'] as String? ?? 'not_requested',
      consentBasis: json['consent_basis'] as String? ?? '',
      rightsHolder: json['rights_holder'] as String? ?? '',
      licence: json['licence'] as String? ?? 'undetermined',
      language: json['language'] as String? ?? 'en',
      region: json['region'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
      consentAttestedBy: json['consent_attested_by'] as String?,
      consentAttestedAt: json['consent_attested_at'] as String?,
    );
  }
}
