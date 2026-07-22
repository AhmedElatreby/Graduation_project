// ─────────────────────────────────────────────────────────────────────────────
//  Lumi · Alert history
//  One row per completed EmergencyAlert.send()/sendBackground() call — the
//  timeline shown on the History tab. Bounded to the 50 most recent entries;
//  written from both the main isolate and the shake-guard's background
//  isolate, the same way DBHelper's contacts table already is — SQLite
//  works cross-isolate here, unlike Firestore (see emergency_alert.dart's
//  sendBackground, which never has a Firebase app to talk to).
//  See docs/superpowers/specs/2026-07-22-sos-history-design.md
// ─────────────────────────────────────────────────────────────────────────────

import 'package:path/path.dart' show join;
import 'package:path_provider/path_provider.dart'
    show getApplicationDocumentsDirectory;
import 'package:sqflite/sqflite.dart';

class AlertHistoryEntry {
  const AlertHistoryEntry({
    required this.id,
    required this.timestamp,
    required this.trigger,
    required this.outcome,
    this.detail,
  });

  final int id;
  final DateTime timestamp;
  final String trigger;
  final String outcome;
  final String? detail;

  factory AlertHistoryEntry.fromMap(Map<String, Object?> map) =>
      AlertHistoryEntry(
        id: map['id'] as int,
        timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
        trigger: map['trigger'] as String,
        outcome: map['outcome'] as String,
        detail: map['detail'] as String?,
      );
}

class AlertHistoryDb {
  static Database? _db;
  static const _maxEntries = 50;

  Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    final documentDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentDirectory.path, 'AlertHistory.db');
    return openDatabase(path, version: 1, onCreate: _onCreate);
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute(
        'CREATE TABLE alert_history (id INTEGER PRIMARY KEY AUTOINCREMENT, '
        'timestamp INTEGER, trigger TEXT, outcome TEXT, detail TEXT)');
  }

  /// Writes one entry, then prunes anything beyond the most recent
  /// [_maxEntries] rows (ties broken by id, since two inserts can land in
  /// the same millisecond) so the log never grows unbounded.
  Future<void> insert(
      {required String trigger,
      required String outcome,
      String? detail}) async {
    final dbClient = await db;
    await dbClient.insert('alert_history', {
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'trigger': trigger,
      'outcome': outcome,
      'detail': detail,
    });
    await dbClient.rawDelete(
      'DELETE FROM alert_history WHERE id NOT IN '
      '(SELECT id FROM alert_history ORDER BY timestamp DESC, id DESC LIMIT ?)',
      [_maxEntries],
    );
  }

  Future<List<AlertHistoryEntry>> getEntries() async {
    final dbClient = await db;
    final maps = await dbClient.query('alert_history',
        orderBy: 'timestamp DESC, id DESC');
    return maps.map(AlertHistoryEntry.fromMap).toList();
  }

  Future<void> clear() async {
    final dbClient = await db;
    await dbClient.delete('alert_history');
  }
}
