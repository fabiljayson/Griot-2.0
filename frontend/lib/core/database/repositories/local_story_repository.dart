import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../features/auth/models/user_model.dart';
import '../../../features/stories/models/story_model.dart';
import '../../security/pii_cipher.dart';
import '../app_database.dart';

/// Repository for local story CRUD against the SQLite database.
///
/// All story operations — listing, searching, filtering, creating, updating,
/// deleting — happen locally with no network requests.
class LocalStoryRepository {
  LocalStoryRepository({AppDatabase? database})
      : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  Future<Database> get _db async => _database.database;

  // ── Read ──

  /// Get stories with optional filters, search, and pagination.
  Future<List<StoryModel>> getStories({
    String? search,
    String? language,
    String? category,
    String? region,
    String sort = '-created_at',
    int page = 1,
    int pageSize = 20,
  }) async {
    final db = await _db;

    final where = <String>[];
    final args = <dynamic>[];

    if (search != null && search.isNotEmpty) {
      where.add('(s.title LIKE ? OR s.summary LIKE ? OR s.tags LIKE ?)');
      final q = '%$search%';
      args.addAll([q, q, q]);
    }
    if (language != null && language.isNotEmpty) {
      where.add('s.language = ?');
      args.add(language);
    }
    if (region != null && region.isNotEmpty) {
      where.add('s.region = ?');
      args.add(region);
    }
    if (category != null && category.isNotEmpty) {
      where.add('s.id IN (SELECT lsc.story_id FROM local_story_categories lsc '
          'JOIN local_categories lc ON lc.id = lsc.category_id WHERE lc.slug = ?)');
      args.add(category);
    }

    where.add("s.status = 'published'");

    final whereClause = where.isNotEmpty ? where.join(' AND ') : '';

    // Sort
    final orderBy = _sortToSql(sort);

    final offset = (page - 1) * pageSize;

    final rows = await db.rawQuery(
      'SELECT s.* FROM local_stories s '
      '${whereClause.isNotEmpty ? "WHERE $whereClause" : ""} '
      'ORDER BY $orderBy '
      'LIMIT ? OFFSET ?',
      [...args, pageSize, offset],
    );

    return Future.wait(rows.map(_rowToStory));
  }

  /// Get a single story by slug.
  Future<StoryModel> getStory(String slug) async {
    final db = await _db;
    final rows = await db.query(
      'local_stories',
      where: 'slug = ?',
      whereArgs: [slug],
      limit: 1,
    );
    if (rows.isEmpty) throw Exception('Story not found: $slug');
    return _rowToStory(rows.first);
  }

  /// Get stories by the current user.
  Future<List<StoryModel>> getMyStories(int userId) async {
    final db = await _db;
    final rows = await db.query(
      'local_stories',
      where: 'author_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at DESC',
    );
    return Future.wait(rows.map(_rowToStory));
  }

  /// Get bookmarked stories.
  Future<List<StoryModel>> getBookmarks() async {
    final db = await _db;
    final rows = await db.query(
      'local_stories',
      where: 'is_bookmarked = 1',
      orderBy: 'created_at DESC',
    );
    return Future.wait(rows.map(_rowToStory));
  }

  /// Published story counts grouped by the raw `region` value on each story.
  ///
  /// Used to enrich the curated region catalogue with real counts (the webapp
  /// renders `{{ region.count }} stories` on each region card).
  Future<Map<String, int>> regionCounts() async {
    final db = await _db;
    final rows = await db.rawQuery(
      "SELECT region, COUNT(*) AS total FROM local_stories "
      "WHERE status = 'published' AND region IS NOT NULL AND region != '' "
      'GROUP BY region',
    );
    return {
      for (final row in rows)
        (row['region'] as String): (row['total'] as int? ?? 0),
    };
  }

  /// Stories published in any of [regions] (exact, case-insensitive match).
  Future<List<StoryModel>> getStoriesForRegions(
    List<String> regions, {
    int limit = 60,
    String sort = '-view_count',
  }) async {
    if (regions.isEmpty) return const [];
    final db = await _db;

    final placeholders = List.filled(regions.length, '?').join(', ');
    final rows = await db.rawQuery(
      'SELECT s.* FROM local_stories s '
      "WHERE s.status = 'published' AND LOWER(s.region) IN ($placeholders) "
      'ORDER BY ${_sortToSql(sort)} LIMIT ?',
      [...regions.map((r) => r.toLowerCase()), limit],
    );

    return Future.wait(rows.map(_rowToStory));
  }

  /// Get all categories.
  Future<List<StoryCategory>> getCategories() async {
    final db = await _db;
    final rows = await db.query('local_categories', orderBy: 'name ASC');
    return rows.map(_rowToCategory).toList();
  }

  // ── Write ──

  /// Create a new story.
  Future<StoryModel> createStory({
    required String title,
    required String content,
    String? summary,
    List<int>? categoryIds,
    String language = 'en',
    String? region,
    String? tags,
    String? coverImage,
    String? audioUrl,
    String? videoUrl,
    String? culturalContext,
    String? moralLesson,
    String? source,
    String? origin,
    String? provenanceNotes,
    String? rightsHolder,
    String? licence,
    int? authorId,
    String status = 'draft',
  }) async {
    final db = await _db;
    final slug = _slugify(title);

    final id = await db.insert('local_stories', {
      'title': title,
      'slug': slug,
      'content': content,
      'summary': summary ?? '',
      'language': language,
      'region': region ?? '',
      'tags': tags ?? '',
      'cover_image': coverImage,
      'audio_url': audioUrl ?? '',
      'video_url': videoUrl ?? '',
      'cultural_context': culturalContext ?? '',
      'moral_lesson': moralLesson ?? '',
      'source': source ?? '',
      // Provenance travels with the local copy: a draft written offline must
      // not lose its declared origin when it syncs. `consent_status` is left at
      // the column default because only a moderator records it.
      'origin': origin ?? 'contributor_original',
      'provenance_notes': provenanceNotes ?? '',
      'rights_holder': rightsHolder ?? '',
      'licence': licence ?? 'undetermined',
      'estimated_read_time': _estimateReadTime(content),
      // Never default to `published`: a locally created story is a
      // contributor submission, and the public offline feed only ever reads
      // `status = 'published'`. Publishing is the reviewer's decision.
      'status': status,
      'author_id': authorId,
      'published_at': status == 'published' ? DateTime.now().toIso8601String() : null,
    });

    // Link categories.
    if (categoryIds != null) {
      for (final catId in categoryIds) {
        await db.insert('local_story_categories', {
          'story_id': id,
          'category_id': catId,
        });
      }
    }

    return getStory(slug);
  }

  /// Update an existing story.
  Future<StoryModel> updateStory(
    String slug, {
    String? title,
    String? content,
    String? summary,
    List<int>? categoryIds,
    String? language,
    String? region,
    String? tags,
    String? status,
    String? origin,
    String? provenanceNotes,
    String? rightsHolder,
    String? licence,
  }) async {
    final db = await _db;
    final updates = <String, dynamic>{};
    if (title != null) updates['title'] = title;
    if (content != null) {
      updates['content'] = content;
      updates['estimated_read_time'] = _estimateReadTime(content);
    }
    if (summary != null) updates['summary'] = summary;
    if (language != null) updates['language'] = language;
    if (region != null) updates['region'] = region;
    if (tags != null) updates['tags'] = tags;
    if (status != null) updates['status'] = status;
    if (origin != null) {
      updates['origin'] = origin;
      // Keep the derived flag in step with the source of truth, so a story
      // relabelled as seeded immediately loses its "verified" presentation.
      updates['is_synthetic_origin'] = origin == 'seeded' ? 1 : 0;
    }
    if (provenanceNotes != null) updates['provenance_notes'] = provenanceNotes;
    if (rightsHolder != null) updates['rights_holder'] = rightsHolder;
    if (licence != null) updates['licence'] = licence;

    if (updates.isNotEmpty) {
      await db.update(
        'local_stories',
        updates,
        where: 'slug = ?',
        whereArgs: [slug],
      );
    }

    if (categoryIds != null) {
      final storyRow = await db.query(
        'local_stories',
        where: 'slug = ?',
        whereArgs: [slug],
        limit: 1,
      );
      if (storyRow.isNotEmpty) {
        final storyId = storyRow.first['id'] as int;
        await db.delete(
          'local_story_categories',
          where: 'story_id = ?',
          whereArgs: [storyId],
        );
        for (final catId in categoryIds) {
          await db.insert('local_story_categories', {
            'story_id': storyId,
            'category_id': catId,
          });
        }
      }
    }

    return getStory(slug);
  }

  /// Delete a story.
  Future<void> deleteStory(String slug) async {
    final db = await _db;
    await db.delete('local_stories', where: 'slug = ?', whereArgs: [slug]);
  }

  /// Toggle bookmark.
  Future<bool> toggleBookmark(String slug) async {
    final db = await _db;
    final rows = await db.query(
      'local_stories',
      columns: ['id', 'is_bookmarked', 'bookmark_count'],
      where: 'slug = ?',
      whereArgs: [slug],
      limit: 1,
    );
    if (rows.isEmpty) return false;

    final current = rows.first['is_bookmarked'] as int;
    final count = rows.first['bookmark_count'] as int;
    final newBookmarked = current == 0 ? 1 : 0;
    final newCount = current == 0 ? count + 1 : count - 1;

    await db.update(
      'local_stories',
      {
        'is_bookmarked': newBookmarked,
        'bookmark_count': newCount,
      },
      where: 'slug = ?',
      whereArgs: [slug],
    );

    return newBookmarked == 1;
  }

  /// Toggle like.
  Future<bool> toggleLike(String slug) async {
    final db = await _db;
    final rows = await db.query(
      'local_stories',
      columns: ['id', 'is_liked', 'like_count'],
      where: 'slug = ?',
      whereArgs: [slug],
      limit: 1,
    );
    if (rows.isEmpty) return false;

    final current = rows.first['is_liked'] as int;
    final count = rows.first['like_count'] as int;
    final newLiked = current == 0 ? 1 : 0;
    final newCount = current == 0 ? count + 1 : count - 1;

    await db.update(
      'local_stories',
      {
        'is_liked': newLiked,
        'like_count': newCount,
      },
      where: 'slug = ?',
      whereArgs: [slug],
    );

    return newLiked == 1;
  }

  /// Update reading progress (stored locally).
  Future<void> updateReadingProgress(
    String slug, {
    required int percent,
    int? lastPosition,
    bool? completed,
  }) async {
    final db = await _db;
    // Use the existing reading_progress table.
    final storyRow = await db.query(
      'local_stories',
      columns: ['id'],
      where: 'slug = ?',
      whereArgs: [slug],
      limit: 1,
    );
    if (storyRow.isEmpty) return;
    final storyId = storyRow.first['id'] as int;

    await db.insert(
      'reading_progress',
      {
        'story_id': storyId,
        'scroll_fraction': percent / 100.0,
        'audio_resume_seconds': lastPosition ?? 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Force the stored bookmark state for a slug mirrored from the API.
  ///
  /// Created on demand when the story is not stored locally yet (a guest can
  /// bookmark an API-sourced story before it was ever mirrored).
  Future<void> setBookmarked(String slug, bool value) async {
    final db = await _db;
    final rows = await db.query(
      'local_stories',
      columns: ['id'],
      where: 'slug = ?',
      whereArgs: [slug],
      limit: 1,
    );
    if (rows.isEmpty) {
      await db.insert('local_stories', {
        'title': slug,
        'slug': slug,
        'status': 'published',
        'is_bookmarked': value ? 1 : 0,
      });
      return;
    }
    await db.update(
      'local_stories',
      {'is_bookmarked': value ? 1 : 0},
      where: 'slug = ?',
      whereArgs: [slug],
    );
  }

  /// Force the stored like state for a slug mirrored from the API.
  Future<void> setLiked(String slug, bool value) async {
    final db = await _db;
    final rows = await db.query(
      'local_stories',
      columns: ['id'],
      where: 'slug = ?',
      whereArgs: [slug],
      limit: 1,
    );
    if (rows.isEmpty) {
      await db.insert('local_stories', {
        'title': slug,
        'slug': slug,
        'status': 'published',
        'is_liked': value ? 1 : 0,
      });
      return;
    }
    await db.update(
      'local_stories',
      {'is_liked': value ? 1 : 0},
      where: 'slug = ?',
      whereArgs: [slug],
    );
  }

  // ── API mirror ──

  /// Upsert API-sourced stories into `local_stories` (slug is the stable key).
  ///
  /// Used by the offline mirror in [StoryRepository]: after a successful API
  /// fetch the payload is copied here so a later offline launch still shows
  /// the backend collection — with its real `cover_image` paths — instead of
  /// an empty screen.
  ///
  /// Conflict updates refresh content fields but deliberately preserve the
  /// locally-owned interaction columns (`is_bookmarked`, `is_liked`) and the
  /// local `author_id`, and never overwrite a stored cover with an empty
  /// value. Local ids are left to AUTOINCREMENT so they cannot collide with
  /// backend story ids; the slug is the identity everywhere in the app.
  Future<void> mirrorStories(List<StoryModel> stories) async {
    if (stories.isEmpty) return;
    final db = await _db;

    await db.transaction((txn) async {
      for (final s in stories) {
        await txn.rawInsert(
          '''
          INSERT INTO local_stories (
            title, slug, content, summary, author_id, language, region, tags,
            cover_image, audio_url, video_url, cultural_context, moral_lesson,
            source, estimated_read_time, status, view_count, like_count,
            bookmark_count, is_bookmarked, is_liked, created_at, published_at,
            trust_score, trust_level, sources_json, verification_json
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(slug) DO UPDATE SET
            title = excluded.title,
            content = CASE WHEN excluded.content != '' THEN excluded.content ELSE local_stories.content END,
            summary = excluded.summary,
            language = excluded.language,
            region = excluded.region,
            tags = excluded.tags,
            cover_image = COALESCE(NULLIF(excluded.cover_image, ''), local_stories.cover_image),
            audio_url = excluded.audio_url,
            video_url = excluded.video_url,
            cultural_context = excluded.cultural_context,
            moral_lesson = excluded.moral_lesson,
            source = excluded.source,
            estimated_read_time = excluded.estimated_read_time,
            status = excluded.status,
            view_count = excluded.view_count,
            like_count = excluded.like_count,
            bookmark_count = excluded.bookmark_count,
            created_at = excluded.created_at,
            published_at = excluded.published_at,
            trust_score = excluded.trust_score,
            trust_level = excluded.trust_level,
            sources_json = excluded.sources_json,
            verification_json = excluded.verification_json
          ''',
          [
            s.title,
            s.slug,
            s.content,
            s.summary,
            null, // author_id stays local — backend authors are not mirrored.
            s.language,
            s.region,
            s.tags,
            s.coverImage,
            s.audioUrl,
            s.videoUrl,
            s.culturalContext,
            s.moralLesson,
            s.source,
            s.estimatedReadTime,
            s.status,
            s.viewCount,
            s.likeCount,
            s.bookmarkCount,
            s.isBookmarked ? 1 : 0,
            s.isLiked ? 1 : 0,
            s.createdAt.isNotEmpty
                ? s.createdAt
                : DateTime.now().toIso8601String(),
            s.publishedAt,
            // Trust evidence rides along with the mirror so a story read
            // offline still shows its review — and never fakes one.
            s.trustScore,
            s.trustLevel,
            jsonEncode(s.sources.map((source) => source.toJson()).toList()),
            s.verification == null
                ? null
                : jsonEncode(s.verification!.toJson()),
          ],
        );
      }
    });
  }

  /// Make sure [story] exists locally so per-story interaction columns can be
  /// toggled offline (guest bookmark/like on an API-sourced story).
  ///
  /// A no-op when the slug is already mirrored. Content is stored as-is; the
  /// cover image is kept so the card still renders its art offline.
  Future<void> ensureStory(StoryModel story) async {
    final db = await _db;
    final rows = await db.query(
      'local_stories',
      columns: ['id'],
      where: 'slug = ?',
      whereArgs: [story.slug],
      limit: 1,
    );
    if (rows.isNotEmpty) return;

    await db.insert('local_stories', {
      'title': story.title,
      'slug': story.slug,
      'content': story.content,
      'summary': story.summary,
      'language': story.language,
      'region': story.region,
      'tags': story.tags,
      'cover_image': story.coverImage,
      'audio_url': story.audioUrl,
      'video_url': story.videoUrl,
      'cultural_context': story.culturalContext,
      'moral_lesson': story.moralLesson,
      'source': story.source,
      'estimated_read_time': story.estimatedReadTime,
      'status': story.status,
      // Provenance is stored with the cached copy so a story read offline
      // still says where it came from — an offline reader cannot check.
      'origin': story.origin,
      'provenance_notes': story.provenanceNotes,
      'consent_status': story.consentStatus,
      'rights_holder': story.rightsHolder,
      'licence': story.licence,
      'recorded_at': story.recordedAt,
      'attribution': story.attribution,
      'is_synthetic_origin': story.isSyntheticOrigin ? 1 : 0,
      'view_count': story.viewCount,
      'like_count': story.likeCount,
      'bookmark_count': story.bookmarkCount,
      'trust_score': story.trustScore,
      'trust_level': story.trustLevel,
      'sources_json': jsonEncode(
        story.sources.map((source) => source.toJson()).toList(),
      ),
      'verification_json': story.verification == null
          ? null
          : jsonEncode(story.verification!.toJson()),
      'created_at': story.createdAt.isNotEmpty
          ? story.createdAt
          : DateTime.now().toIso8601String(),
      'published_at': story.publishedAt,
    });
  }

  // ── Helpers ──

  Future<StoryModel> _rowToStory(Map<String, dynamic> row) async {
    final db = await _db;
    final storyId = row['id'] as int;

    // Fetch categories.
    final catRows = await db.rawQuery(
      'SELECT lc.* FROM local_categories lc '
      'JOIN local_story_categories lsc ON lc.id = lsc.category_id '
      'WHERE lsc.story_id = ?',
      [storyId],
    );
    final categories = catRows.map(_rowToCategory).toList();

    // Fetch author.
    final authorId = row['author_id'] as int?;
    UserModel author = const UserModel(id: 0, username: 'offline');
    if (authorId != null) {
      final userRows = await db.query(
        'local_users',
        where: 'id = ?',
        whereArgs: [authorId],
        limit: 1,
      );
      if (userRows.isNotEmpty) {
        final u = userRows.first;
        final pii = PiiCipher.instance;
        author = UserModel(
          id: u['id'] as int,
          username: u['username'] as String,
          firstName: await pii.decrypt((u['first_name'] as String?) ?? ''),
          lastName: await pii.decrypt((u['last_name'] as String?) ?? ''),
          role: UserRole.fromString((u['role'] as String?) ?? 'visitor'),
        );
      }
    }

    return StoryModel(
      id: storyId,
      title: row['title'] as String,
      slug: row['slug'] as String,
      content: (row['content'] as String?) ?? '',
      summary: (row['summary'] as String?) ?? '',
      author: author,
      categories: categories,
      language: (row['language'] as String?) ?? 'en',
      region: (row['region'] as String?) ?? '',
      tags: (row['tags'] as String?) ?? '',
      coverImage: row['cover_image'] as String?,
      audioUrl: (row['audio_url'] as String?) ?? '',
      videoUrl: (row['video_url'] as String?) ?? '',
      culturalContext: (row['cultural_context'] as String?) ?? '',
      moralLesson: (row['moral_lesson'] as String?) ?? '',
      source: (row['source'] as String?) ?? '',
      estimatedReadTime: (row['estimated_read_time'] as int?) ?? 0,
      status: (row['status'] as String?) ?? 'published',
      origin: (row['origin'] as String?) ?? 'unknown',
      provenanceNotes: (row['provenance_notes'] as String?) ?? '',
      consentStatus: (row['consent_status'] as String?) ?? 'not_requested',
      rightsHolder: (row['rights_holder'] as String?) ?? '',
      licence: (row['licence'] as String?) ?? 'undetermined',
      recordedAt: row['recorded_at'] as String?,
      attribution: (row['attribution'] as String?) ?? '',
      isSyntheticOrigin: (row['is_synthetic_origin'] as int?) == 1,
      viewCount: (row['view_count'] as int?) ?? 0,
      likeCount: (row['like_count'] as int?) ?? 0,
      bookmarkCount: (row['bookmark_count'] as int?) ?? 0,
      isBookmarked: (row['is_bookmarked'] as int?) == 1,
      isLiked: (row['is_liked'] as int?) == 1,
      createdAt: (row['created_at'] as String?) ?? '',
      publishedAt: row['published_at'] as String?,
      trustScore: (row['trust_score'] as int?) ?? 0,
      trustLevel: (row['trust_level'] as String?) ?? 'unverified',
      sources: _decodeSources(row['sources_json'] as String?),
      verification: _decodeVerification(
        row['verification_json'] as String?,
      ),
    );
  }

  /// Decode the mirrored sources blob; unreadable JSON yields no sources
  /// rather than a crash — the story itself still renders.
  List<StorySourceModel> _decodeSources(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<dynamic, dynamic>>()
          .map(
            (source) =>
                StorySourceModel.fromJson(Map<String, dynamic>.from(source)),
          )
          .toList();
    } on FormatException {
      return const [];
    }
  }

  /// Decode the mirrored verification blob; unreadable JSON means "no
  /// review recorded", never a fabricated score.
  StoryVerificationModel? _decodeVerification(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return StoryVerificationModel.fromJson(
        Map<String, dynamic>.from(decoded),
      );
    } on FormatException {
      return null;
    }
  }

  StoryCategory _rowToCategory(Map<String, dynamic> row) {
    return StoryCategory(
      id: row['id'] as int,
      name: row['name'] as String,
      slug: row['slug'] as String,
      description: (row['description'] as String?) ?? '',
      icon: (row['icon'] as String?) ?? '📖',
      color: (row['color'] as String?) ?? '#8B4513',
    );
  }

  String _sortToSql(String sort) {
    // API-style sort: "-created_at" means descending, "created_at" ascending.
    if (sort.startsWith('-')) {
      final field = sort.substring(1);
      return '$field DESC';
    }
    return '$sort ASC';
  }

  String _slugify(String title) {
    return title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }

  int _estimateReadTime(String content) {
    // Rough estimate: 200 words per minute.
    final words = content.split(RegExp(r'\s+')).length;
    return (words / 200).ceil().clamp(1, 60);
  }
}
