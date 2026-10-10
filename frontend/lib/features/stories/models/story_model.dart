import 'package:flutter/material.dart';

import '../../../core/constants/story_assets.dart';
import '../../auth/models/user_model.dart';

/// Story model representing a cultural story or oral tradition.
class StoryModel {
  const StoryModel({
    required this.id,
    required this.title,
    this.slug = '',
    this.content = '',
    this.summary = '',
    required this.author,
    this.categories = const [],
    this.language = 'en',
    this.region = '',
    this.tags = '',
    this.coverImage,
    this.coverImageBlurhash = '',
    this.audioUrl = '',
    this.videoUrl = '',
    this.culturalContext = '',
    this.moralLesson = '',
    this.source = '',
    this.estimatedReadTime = 0,
    this.status = 'published',
    // Only ever populated for the story's author and for moderators — the API
    // returns '' to everyone else. It is why a rejection is actionable rather
    // than a bare `rejected` label.
    this.reviewerNotes = '',
    // Wire values are spelled out rather than read off the enums: a const
    // default cannot read an instance field. They mirror
    // `StoryOrigin.unknown.value` and friends.
    this.origin = 'unknown',
    this.provenanceNotes = '',
    this.consentStatus = 'not_requested',
    this.rightsHolder = '',
    this.licence = 'undetermined',
    this.recordedAt,
    this.attribution = '',
    this.isSyntheticOrigin = false,
    this.viewCount = 0,
    this.likeCount = 0,
    this.bookmarkCount = 0,
    this.isBookmarked = false,
    this.isLiked = false,
    this.readingProgress,
    this.createdAt = '',
    this.publishedAt,
    // Cultural Trust Score: evidence strength, never a truth claim. The
    // server computes it (`stories.trust`); the app only renders it.
    this.trustScore = 0,
    this.trustLevel = 'unverified',
    this.sources = const [],
    this.verification,
  });

  final int id;
  final String title;
  final String slug;
  final String content;
  final String summary;
  final UserModel author;
  final List<StoryCategory> categories;
  final String language;
  final String region;
  final String tags;
  final String? coverImage;
  final String coverImageBlurhash;
  final String audioUrl;
  final String videoUrl;
  final String culturalContext;
  final String moralLesson;
  final String source;
  final int estimatedReadTime;
  final String status;
  final String reviewerNotes;

  // --- Provenance & rights ---
  //
  // The app renders oral traditions it did not record. These fields let the
  // reader tell a community recording from seeded demo content, and let the
  // UI state plainly when consent has not been established.
  final String origin;
  final String provenanceNotes;
  final String consentStatus;
  final String rightsHolder;
  final String licence;
  final String? recordedAt;

  /// Credit line composed server-side so the app can never word it differently
  /// from the web. Empty when the server sent nothing.
  final String attribution;

  /// True when this text is generated or seeded rather than sourced.
  final bool isSyntheticOrigin;

  final int viewCount;
  final int likeCount;
  final int bookmarkCount;
  final bool isBookmarked;
  final bool isLiked;
  final ReadingProgressData? readingProgress;
  final String createdAt;
  final String? publishedAt;

  /// 0-100 weighted evidence score, and the band it falls into
  /// (`unverified` / `partial` / `verified`). Documentation strength, not
  /// probability of truth — the UI must never word it as one.
  final int trustScore;
  final String trustLevel;

  /// Structured provenance: who documented where this account came from.
  final List<StorySourceModel> sources;

  /// The evidence row behind [trustScore], when a reviewer recorded one.
  final StoryVerificationModel? verification;

  factory StoryModel.fromJson(Map<String, dynamic> json) {
    return StoryModel(
      id: json['id'] as int? ?? 0,
      title: json['title'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      content: json['content'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      author: UserModel.fromJson(json['author'] as Map<String, dynamic>? ?? {}),
      categories: (json['categories'] as List<dynamic>?)
              ?.map((c) => StoryCategory.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [],
      language: json['language'] as String? ?? 'en',
      region: json['region'] as String? ?? '',
      tags: json['tags'] as String? ?? '',
      coverImage: StoryCoverAssets.forSlug(json['slug'] as String? ?? '') ??
          json['cover_image'] as String?,
      coverImageBlurhash: json['cover_image_blurhash'] as String? ?? '',
      audioUrl: json['audio_url'] as String? ?? '',
      videoUrl: json['video_url'] as String? ?? '',
      culturalContext: json['cultural_context'] as String? ?? '',
      moralLesson: json['moral_lesson'] as String? ?? '',
      source: json['source'] as String? ?? '',
      estimatedReadTime: json['estimated_read_time'] as int? ?? 0,
      status: json['status'] as String? ?? 'published',
      reviewerNotes: json['reviewer_notes'] as String? ?? '',
      origin: json['origin'] as String? ?? 'unknown',
      provenanceNotes: json['provenance_notes'] as String? ?? '',
      consentStatus: json['consent_status'] as String? ?? 'not_requested',
      rightsHolder: json['rights_holder'] as String? ?? '',
      licence: json['licence'] as String? ?? 'undetermined',
      recordedAt: json['recorded_at'] as String?,
      attribution: json['attribution'] as String? ?? '',
      isSyntheticOrigin: json['is_synthetic_origin'] as bool? ?? false,
      viewCount: json['view_count'] as int? ?? 0,
      likeCount: json['like_count'] as int? ?? 0,
      bookmarkCount: json['bookmark_count'] as int? ?? 0,
      isBookmarked: json['is_bookmarked'] as bool? ?? false,
      isLiked: json['is_liked'] as bool? ?? false,
      readingProgress: json['reading_progress'] != null
          ? ReadingProgressData.fromJson(
              json['reading_progress'] as Map<String, dynamic>)
          : null,
      createdAt: json['created_at'] as String? ?? '',
      publishedAt: json['published_at'] as String?,
      trustScore: json['trust_score'] as int? ?? 0,
      trustLevel: json['trust_level'] as String? ?? 'unverified',
      sources: (json['sources'] as List<dynamic>?)
              ?.map((s) => StorySourceModel.fromJson(
                  s as Map<String, dynamic>))
              .toList() ??
          const [],
      verification: json['verification'] != null
          ? StoryVerificationModel.fromJson(
              json['verification'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'slug': slug,
        'content': content,
        'summary': summary,
        'author': author.toJson(),
        'categories': categories.map((c) => c.toJson()).toList(),
        'language': language,
        'region': region,
        'tags': tags,
        'cover_image': coverImage,
        'cover_image_blurhash': coverImageBlurhash,
        'audio_url': audioUrl,
        'video_url': videoUrl,
        'cultural_context': culturalContext,
        'moral_lesson': moralLesson,
        'source': source,
        'estimated_read_time': estimatedReadTime,
        'status': status,
        'reviewer_notes': reviewerNotes,
        'origin': origin,
        'provenance_notes': provenanceNotes,
        'consent_status': consentStatus,
        'rights_holder': rightsHolder,
        'licence': licence,
        'recorded_at': recordedAt,
        'attribution': attribution,
        'is_synthetic_origin': isSyntheticOrigin,
        'view_count': viewCount,
        'like_count': likeCount,
        'bookmark_count': bookmarkCount,
        'is_bookmarked': isBookmarked,
        'is_liked': isLiked,
        'reading_progress': readingProgress?.toJson(),
        'created_at': createdAt,
        'published_at': publishedAt,
        'trust_score': trustScore,
        'trust_level': trustLevel,
        'sources': sources.map((s) => s.toJson()).toList(),
        'verification': verification?.toJson(),
      };

  /// List of tags parsed from comma-separated string.
  List<String> get tagList {
    if (tags.isEmpty) return [];
    return tags.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
  }

  /// Whether this story is publicly visible.
  ///
  /// The media endpoints open generation on any published story, so the UI
  /// needs the same notion of "public" rather than re-deriving it.
  bool get isPublished =>
      status == StoryStatus.published.value;

  /// The origin as a display label, resolved locally for the offline case.
  String get originLabel => StoryOrigin.fromString(origin).label;

  /// The licence as a display label, resolved locally for the offline case.
  String get licenceLabel => StoryLicence.fromString(licence).label;

  /// Whether the source community has agreed to this publication.
  ///
  /// Only [StoryConsent.granted] and [StoryConsent.grantedRestricted] count —
  /// "we haven't asked" is not permission.
  bool get hasEstablishedConsent =>
      consentStatus == StoryConsent.granted.value ||
      consentStatus == StoryConsent.grantedRestricted.value;

  /// True when the reader should be warned that consent is not established.
  bool get needsConsentDisclosure =>
      !hasEstablishedConsent || consentStatus == StoryConsent.withheld.value;

  /// Whether [user] may record "I have asked the community" about this story.
  ///
  /// Only the author, and only a contributor. The server answers anything else
  /// with a 403 (`stories.services.request_consent`), so offering the button to
  /// a stranger would be a control that can only ever fail. Mirrors
  /// `UserModel.canContribute` on the role half — the two lists of roles have
  /// already drifted once, and a gate that is looser than the API is worse than
  /// one that is stricter.
  bool canRequestConsent(UserModel? user) =>
      user != null && user.canContribute && user.id == author.id;

  /// Formatted view count (e.g., "1.2K").
  String get formattedViewCount => _formatCount(viewCount);

  /// Formatted like count.
  String get formattedLikeCount => _formatCount(likeCount);

  /// Formatted bookmark count.
  String get formattedBookmarkCount => _formatCount(bookmarkCount);

  /// Estimated read time display.
  String get readTimeDisplay => '$estimatedReadTime min read';

  static String _formatCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return count.toString();
  }

  StoryModel copyWith({
    int? id,
    String? title,
    String? slug,
    String? content,
    String? summary,
    UserModel? author,
    List<StoryCategory>? categories,
    String? language,
    String? region,
    String? tags,
    String? coverImage,
    String? coverImageBlurhash,
    String? audioUrl,
    String? videoUrl,
    String? culturalContext,
    String? moralLesson,
    String? source,
    int? estimatedReadTime,
    String? status,
    String? reviewerNotes,
    String? origin,
    String? provenanceNotes,
    String? consentStatus,
    String? rightsHolder,
    String? licence,
    String? recordedAt,
    String? attribution,
    bool? isSyntheticOrigin,
    int? viewCount,
    int? likeCount,
    int? bookmarkCount,
    bool? isBookmarked,
    bool? isLiked,
    ReadingProgressData? readingProgress,
    String? createdAt,
    String? publishedAt,
    int? trustScore,
    String? trustLevel,
    List<StorySourceModel>? sources,
    StoryVerificationModel? verification,
  }) {
    return StoryModel(
      id: id ?? this.id,
      title: title ?? this.title,
      slug: slug ?? this.slug,
      content: content ?? this.content,
      summary: summary ?? this.summary,
      author: author ?? this.author,
      categories: categories ?? this.categories,
      language: language ?? this.language,
      region: region ?? this.region,
      tags: tags ?? this.tags,
      coverImage: coverImage ?? this.coverImage,
      coverImageBlurhash: coverImageBlurhash ?? this.coverImageBlurhash,
      audioUrl: audioUrl ?? this.audioUrl,
      videoUrl: videoUrl ?? this.videoUrl,
      culturalContext: culturalContext ?? this.culturalContext,
      moralLesson: moralLesson ?? this.moralLesson,
      source: source ?? this.source,
      estimatedReadTime: estimatedReadTime ?? this.estimatedReadTime,
      status: status ?? this.status,
      reviewerNotes: reviewerNotes ?? this.reviewerNotes,
      origin: origin ?? this.origin,
      provenanceNotes: provenanceNotes ?? this.provenanceNotes,
      consentStatus: consentStatus ?? this.consentStatus,
      rightsHolder: rightsHolder ?? this.rightsHolder,
      licence: licence ?? this.licence,
      recordedAt: recordedAt ?? this.recordedAt,
      attribution: attribution ?? this.attribution,
      isSyntheticOrigin: isSyntheticOrigin ?? this.isSyntheticOrigin,
      viewCount: viewCount ?? this.viewCount,
      likeCount: likeCount ?? this.likeCount,
      bookmarkCount: bookmarkCount ?? this.bookmarkCount,
      isBookmarked: isBookmarked ?? this.isBookmarked,
      isLiked: isLiked ?? this.isLiked,
      readingProgress: readingProgress ?? this.readingProgress,
      createdAt: createdAt ?? this.createdAt,
      publishedAt: publishedAt ?? this.publishedAt,
      trustScore: trustScore ?? this.trustScore,
      trustLevel: trustLevel ?? this.trustLevel,
      sources: sources ?? this.sources,
      verification: verification ?? this.verification,
    );
  }
}

/// Story category model.
class StoryCategory {
  const StoryCategory({
    required this.id,
    required this.name,
    this.slug = '',
    this.description = '',
    this.icon = '📖',
    this.color = '#8B4513',
    this.storyCount = 0,
  });

  final int id;
  final String name;
  final String slug;
  final String description;
  final String icon;
  final String color;
  final int storyCount;

  factory StoryCategory.fromJson(Map<String, dynamic> json) {
    return StoryCategory(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      description: json['description'] as String? ?? '',
      icon: json['icon'] as String? ?? '📖',
      color: json['color'] as String? ?? '#8B4513',
      storyCount: json['story_count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'slug': slug,
        'description': description,
        'icon': icon,
        'color': color,
        'story_count': storyCount,
      };

  /// Convert hex color string to Color.
  Color get colorValue {
    try {
      final hex = color.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return const Color(0xFFC68B29); // Default Foumban bronze (web accent)
    }
  }
}

/// Reading progress data.
class ReadingProgressData {
  const ReadingProgressData({
    this.percent = 0,
    this.lastPosition = 0,
    this.completed = false,
  });

  final int percent;
  final int lastPosition;
  final bool completed;

  factory ReadingProgressData.fromJson(Map<String, dynamic> json) {
    return ReadingProgressData(
      percent: json['percent'] as int? ?? 0,
      lastPosition: json['last_position'] as int? ?? 0,
      completed: json['completed'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'percent': percent,
        'last_position': lastPosition,
        'completed': completed,
      };
}

/// Story status enum.
enum StoryStatus {
  draft('draft', 'Draft'),
  pending('pending', 'Pending Review'),
  underReview('under_review', 'Under Review'),
  needsRevision('needs_revision', 'Changes Requested'),
  published('published', 'Published'),
  rejected('rejected', 'Rejected'),
  archived('archived', 'Archived');

  const StoryStatus(this.value, this.label);

  final String value;
  final String label;

  factory StoryStatus.fromString(String value) {
    return StoryStatus.values.firstWhere(
      (s) => s.value == value,
      orElse: () => StoryStatus.draft,
    );
  }
}

/// Story language enum.
enum StoryLanguage {  english('en', 'English', '🇬🇧'),
  french('fr', 'French', '🇫🇷'),
  fula('ful', 'Fula', '🌍'),
  duala('dua', 'Duala', '🌍'),
  ewondo('ewo', 'Ewondo', '🌍'),
  bamileke('bml', 'Bamileke', '🌍'),
  other('other', 'Other', '🌐');

  const StoryLanguage(this.value, this.label, this.flag);

  final String value;
  final String label;
  final String flag;

  factory StoryLanguage.fromString(String value) {
    return StoryLanguage.values.firstWhere(
      (l) => l.value == value,
      orElse: () => StoryLanguage.english,
    );
  }
}
/// Where a story's text came from, before it entered this database.
///
/// Mirrors `Story.Origin` in the backend. The labels are duplicated rather
/// than fetched so the app can label a cached story while offline; the values
/// are the contract, the labels are presentation.
enum StoryOrigin {
  communityRecorded(
    'community_recorded',
    'Recorded from a community member',
  ),
  oralTranscription(
    'oral_transcription',
    'Transcribed from an oral telling',
  ),
  publishedCollection(
    'published_collection',
    'From a published collection',
  ),
  contributorOriginal(
    'contributor_original',
    'Original contribution',
  ),
  seeded('seeded', 'Seeded demonstration content'),
  unknown('unknown', 'Unknown');

  const StoryOrigin(this.value, this.label);

  final String value;
  final String label;

  factory StoryOrigin.fromString(String value) {
    return StoryOrigin.values.firstWhere(
      (o) => o.value == value,
      orElse: () => StoryOrigin.unknown,
    );
  }
}

/// Whether the people behind a story agreed to its publication.
///
/// Mirrors `Story.Consent` in the backend. The app never writes this field —
/// a contributor recording their own community's consent is the claim this
/// exists to make trustworthy.
enum StoryConsent {
  notRequested('not_requested', 'Consent not yet requested'),
  pending('pending', 'Consent pending'),
  granted('granted', 'Consent granted'),
  grantedRestricted(
    'granted_restricted',
    'Consent granted with restrictions',
  ),
  withheld('withheld', 'Consent withheld');

  const StoryConsent(this.value, this.label);

  final String value;
  final String label;

  /// The states that are an actual answer from the community.
  ///
  /// `notRequested` and `pending` are the *absence* of one, so a form offering
  /// them as a "Decision" lets a moderator file "not requested" as what the
  /// community said — complete with a basis and an attestation, and the story
  /// stays in the queue for the next moderator. Mirrors
  /// `stories.services.CONSENT_DECISIONS`.
  static const decisions = [granted, grantedRestricted, withheld];

  factory StoryConsent.fromString(String value) {
    return StoryConsent.values.firstWhere(
      (c) => c.value == value,
      orElse: () => StoryConsent.notRequested,
    );
  }
}

/// Rights under which a story's text is shared.
///
/// Mirrors `Story.Licence` in the backend.
enum StoryLicence {
  allRightsReserved('all_rights_reserved', 'All rights reserved'),
  ccBy('cc_by', 'CC BY 4.0'),
  ccBySa('cc_by_sa', 'CC BY-SA 4.0'),
  ccByNc('cc_by_nc', 'CC BY-NC 4.0'),
  ccByNcSa('cc_by_nc_sa', 'CC BY-NC-SA 4.0'),
  publicDomain('public_domain', 'Public domain'),
  undetermined('undetermined', 'Undetermined');

  const StoryLicence(this.value, this.label);

  final String value;
  final String label;

  factory StoryLicence.fromString(String value) {
    return StoryLicence.values.firstWhere(
      (l) => l.value == value,
      orElse: () => StoryLicence.undetermined,
    );
  }
}

/// One documented source behind a story — the structured provenance.
///
/// Mirrors `StorySource` in the backend. `isVerified` is a moderator's
/// attestation, so it is never writable from the app's own forms.
class StorySourceModel {
  const StorySourceModel({
    required this.id,
    required this.sourceType,
    required this.name,
    this.author = '',
    this.institution = '',
    this.url = '',
    this.reference = '',
    this.notes = '',
    this.isVerified = false,
    this.verifiedBy,
    this.verifiedAt,
  });

  final int id;
  final String sourceType;
  final String name;
  final String author;
  final String institution;
  final String url;
  final String reference;
  final String notes;
  final bool isVerified;
  final String? verifiedBy;
  final String? verifiedAt;

  factory StorySourceModel.fromJson(Map<String, dynamic> json) {
    return StorySourceModel(
      id: json['id'] as int? ?? 0,
      sourceType: json['source_type'] as String? ?? 'other',
      name: json['name'] as String? ?? '',
      author: json['author'] as String? ?? '',
      institution: json['institution'] as String? ?? '',
      url: json['url'] as String? ?? '',
      reference: json['reference'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      isVerified: json['is_verified'] as bool? ?? false,
      verifiedBy: json['verified_by'] as String?,
      verifiedAt: json['verified_at'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'source_type': sourceType,
        'name': name,
        'author': author,
        'institution': institution,
        'url': url,
        'reference': reference,
        'notes': notes,
        'is_verified': isVerified,
        'verified_by': verifiedBy,
        'verified_at': verifiedAt,
      };

  /// Display label for the source type, resolved locally so it works offline.
  String get typeLabel => StorySourceType.fromString(sourceType).label;

  /// The line under the name: who recorded/kept it, if the record says.
  String get citation {
    final parts = [if (author.isNotEmpty) author, if (institution.isNotEmpty) institution];
    return parts.join(', ');
  }
}

/// How a source was recorded, mirroring `StorySource.SourceType`.
///
/// Values are uppercase because that is what the API emits; lookup is
/// case-insensitive so a legacy lowercase row still resolves its label
/// instead of silently degrading to "Other".
enum StorySourceType {
  oralTradition('ORAL_TRADITION', 'Oral tradition'),
  communityTestimony('COMMUNITY_TESTIMONY', 'Community testimony'),
  book('BOOK', 'Book'),
  academicReference('ACADEMIC_REFERENCE', 'Academic reference'),
  museum('MUSEUM', 'Museum'),
  culturalInstitution('CULTURAL_INSTITUTION', 'Cultural institution'),
  archive('ARCHIVE', 'Archive'),
  officialSource('OFFICIAL_SOURCE', 'Official source'),
  other('OTHER', 'Other');

  const StorySourceType(this.value, this.label);

  final String value;
  final String label;

  factory StorySourceType.fromString(String value) {
    final needle = value.trim().toUpperCase();
    return StorySourceType.values.firstWhere(
      (t) => t.value == needle,
      orElse: () => StorySourceType.other,
    );
  }
}

/// The evidence row behind the Cultural Trust Score.
///
/// Mirrors `StoryVerification`. The score is derived server-side from the
/// criteria, so the app renders but never recomputes it.
class StoryVerificationModel {
  const StoryVerificationModel({
    this.sourceVerified = false,
    this.communityValidated = false,
    this.expertValidated = false,
    this.referencesConfirmed = false,
    this.consistencyConfirmed = false,
    this.trustScore = 0,
    this.trustLevel = 'unverified',
    this.breakdown = const [],
    this.disclaimer = '',
    this.reviewer,
    this.notes = '',
    this.verifiedAt,
  });

  final bool sourceVerified;
  final bool communityValidated;
  final bool expertValidated;
  final bool referencesConfirmed;
  final bool consistencyConfirmed;
  final int trustScore;
  final String trustLevel;

  /// Per-criterion rows `{criterion, label, weight, confirmed}` in display
  /// order — exactly what the reviewer saw when they recorded it.
  final List<Map<String, dynamic>> breakdown;

  /// Server-worded explanation that the score measures documentation
  /// strength, not truth. Rendered verbatim; rewriting it locally is how
  /// the two surfaces would start disagreeing about what the number means.
  final String disclaimer;

  final String? reviewer;
  final String notes;
  final String? verifiedAt;

  factory StoryVerificationModel.fromJson(Map<String, dynamic> json) {
    return StoryVerificationModel(
      sourceVerified: json['source_verified'] as bool? ?? false,
      communityValidated: json['community_validated'] as bool? ?? false,
      expertValidated: json['expert_validated'] as bool? ?? false,
      referencesConfirmed: json['references_confirmed'] as bool? ?? false,
      consistencyConfirmed: json['consistency_confirmed'] as bool? ?? false,
      trustScore: json['trust_score'] as int? ?? 0,
      trustLevel: json['trust_level'] as String? ?? 'unverified',
      breakdown: (json['breakdown'] as List<dynamic>?)
              ?.map((row) => Map<String, dynamic>.from(row as Map))
              .toList() ??
          const [],
      disclaimer: json['disclaimer'] as String? ?? '',
      reviewer: json['reviewer'] as String?,
      notes: json['notes'] as String? ?? '',
      verifiedAt: json['verified_at'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'source_verified': sourceVerified,
        'community_validated': communityValidated,
        'expert_validated': expertValidated,
        'references_confirmed': referencesConfirmed,
        'consistency_confirmed': consistencyConfirmed,
        'trust_score': trustScore,
        'trust_level': trustLevel,
        'breakdown': breakdown,
        'disclaimer': disclaimer,
        'reviewer': reviewer,
        'notes': notes,
        'verified_at': verifiedAt,
      };
}

/// Reader-facing band for a trust score, mirroring `stories.trust`.
enum TrustLevel {
  unverified('unverified', 'Unverified'),
  partial('partial', 'Partially verified'),
  verified('verified', 'Verified');

  const TrustLevel(this.value, this.label);

  final String value;
  final String label;

  factory TrustLevel.fromString(String value) {
    return TrustLevel.values.firstWhere(
      (l) => l.value == value,
      orElse: () => TrustLevel.unverified,
    );
  }
}
