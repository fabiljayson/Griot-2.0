import 'package:sqflite/sqflite.dart';

import '../app_database.dart';

/// Data-access layer over the `search_history` table.
///
/// Powers the search bar's local history suggestions (Phase 3.2).
class SearchHistoryRepository {
  SearchHistoryRepository({AppDatabase? database})
      : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  /// Cap on how many history entries we keep to bound storage growth.
  static const int maxEntries = 30;

  Future<Database> get _db async => _database.database;

  /// Record a search query (deduplicates recent identical queries).
  Future<void> addQuery(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    final db = await _db;
    await db.delete(
      'search_history',
      where: 'query = ? COLLATE NOCASE',
      whereArgs: [trimmed],
    );
    await db.insert('search_history', {'query': trimmed});

    // Trim the table to the most recent N entries.
    final excess = await db.rawQuery(
      'SELECT id FROM search_history ORDER BY id DESC LIMIT -1 OFFSET ?',
      [maxEntries],
    );
    for (final row in excess) {
      await db.delete('search_history', where: 'id = ?', whereArgs: [row['id']]);
    }
  }

  /// Most recent queries, newest first.
  Future<List<String>> recentQueries({int limit = 10}) async {
    final db = await _db;
    final rows = await db.query(
      'search_history',
      columns: ['query'],
      orderBy: 'id DESC',
      limit: limit,
    );
    return rows.map((r) => r['query'] as String).toList();
  }

  /// Clear the entire search history.
  Future<void> clear() async {
    final db = await _db;
    await db.delete('search_history');
  }
}
