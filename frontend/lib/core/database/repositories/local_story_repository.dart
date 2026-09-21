import 'package:sqflite/sqflite.dart';

import '../../../features/auth/models/user_model.dart';
import '../../../features/stories/models/story_model.dart';
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
    int? authorId,
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
      'estimated_read_time': _estimateReadTime(content),
      'status': 'published',
      'author_id': authorId,
      'published_at': DateTime.now().toIso8601String(),
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
        author = UserModel(
          id: u['id'] as int,
          username: u['username'] as String,
          firstName: (u['first_name'] as String?) ?? '',
          lastName: (u['last_name'] as String?) ?? '',
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
      viewCount: (row['view_count'] as int?) ?? 0,
      likeCount: (row['like_count'] as int?) ?? 0,
      bookmarkCount: (row['bookmark_count'] as int?) ?? 0,
      isBookmarked: (row['is_bookmarked'] as int?) == 1,
      isLiked: (row['is_liked'] as int?) == 1,
      createdAt: (row['created_at'] as String?) ?? '',
      publishedAt: row['published_at'] as String?,
    );
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
