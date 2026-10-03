/// Data models for the admin QR code worklist.
///
/// Mirrors `GET /api/artifacts/qr/worklist/` and
/// `POST /api/artifacts/qr/worklist/generate/` in
/// `backend/qr_codes/views.py`.
///
/// A QR code is not a record — it is derived from an artifact's deep link and
/// only exists once someone generates it. So this list is not "the artifacts",
/// it is "the artifacts still missing the label they are supposed to carry on
/// the museum wall", which is why the server orders it that way and why this
/// model does not try to re-sort it.
library;

/// One row of the QR worklist.
class QrWorklistEntry {
  const QrWorklistEntry({
    this.id = 0,
    this.slug = '',
    this.title = '',
    this.category = '',
    this.museumName = '',
    this.isPublished = true,
    this.deepLink = '',
    this.scanTotal = 0,
    this.hasQrCode = false,
  });

  final int id;
  final String slug;
  final String title;
  final String category;
  final String museumName;
  final bool isPublished;

  /// The URL the generated code will encode — shown so a curator can confirm
  /// the code points at the object they are holding, not somewhere else.
  final String deepLink;

  final int scanTotal;
  final bool hasQrCode;

  factory QrWorklistEntry.fromJson(Map<String, dynamic> json) {
    return QrWorklistEntry(
      id: (json['id'] as num?)?.toInt() ?? 0,
      slug: json['slug'] as String? ?? '',
      title: json['title'] as String? ?? '',
      category: json['category'] as String? ?? '',
      museumName: json['museum_name'] as String? ?? '',
      isPublished: json['is_published'] as bool? ?? true,
      deepLink: json['qr_deep_link'] as String? ?? '',
      scanTotal: (json['scan_total'] as num?)?.toInt() ?? 0,
      hasQrCode: json['has_qr_code'] as bool? ?? false,
    );
  }
}

/// The worklist plus the counts the section header reads.
class QrWorklist {
  const QrWorklist({
    this.entries = const [],
    this.total = 0,
    this.generated = 0,
    this.truncated = false,
  });

  final List<QrWorklistEntry> entries;

  /// Every artifact in the catalog, including ones not on this page.
  final int total;

  /// How many already have a printable code.
  final int generated;

  /// True when [entries] is a prefix of the catalog rather than all of it.
  final bool truncated;

  /// The ones doing nothing on the wall — the reason this screen exists.
  List<QrWorklistEntry> get unlabelled =>
      entries.where((entry) => !entry.hasQrCode).toList();

  factory QrWorklist.fromJson(Map<String, dynamic> json) {
    return QrWorklist(
      entries: (json['artifacts'] as List<dynamic>? ?? const [])
          .map((e) => QrWorklistEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: (json['total'] as num?)?.toInt() ?? 0,
      generated: (json['generated'] as num?)?.toInt() ?? 0,
      truncated: json['truncated'] as bool? ?? false,
    );
  }
}

/// Outcome of a batch generation.
class QrWorklistGeneration {
  const QrWorklistGeneration({
    this.generated = const [],
    this.missing = const [],
    this.skipped = false,
  });

  /// Slugs a code was generated for.
  final List<String> generated;

  /// Requested slugs that do not resolve — reported, not raised, so one stale
  /// row cannot discard the rest of the curator's batch.
  final List<String> missing;

  /// True when nothing was asked for and nothing was missing.
  final bool skipped;

  factory QrWorklistGeneration.fromJson(Map<String, dynamic> json) {
    return QrWorklistGeneration(
      generated: (json['generated'] as List<dynamic>? ?? const [])
          .map((e) => e as String)
          .toList(),
      missing:
          (json['missing'] as List<dynamic>? ?? const [])
              .map((e) => e as String)
              .toList(),
      skipped: json['skipped'] as bool? ?? false,
    );
  }
}