// AlertHistoryDb: newest-first ordering, the 50-entry cap prunes the oldest
// row, and clear() wipes everything.
import 'package:flutter_test/flutter_test.dart';

import 'package:safetyproject/database/alert_history_db.dart';

import '../test_helpers.dart';

void main() {
  configureTestEnvironment();

  setUp(() async {
    await AlertHistoryDb().clear();
  });

  test('getEntries returns newest first', () async {
    final db = AlertHistoryDb();
    await db.insert(trigger: 'SOS button', outcome: 'Sent');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await db.insert(
        trigger: 'Shake to SOS', outcome: 'Failed', detail: 'SMS failed: x');

    final entries = await db.getEntries();
    expect(entries.length, 2);
    expect(entries.first.trigger, 'Shake to SOS');
    expect(entries.first.outcome, 'Failed');
    expect(entries.first.detail, 'SMS failed: x');
    expect(entries.last.trigger, 'SOS button');
    expect(entries.last.detail, isNull);
  });

  test('inserting a 51st entry prunes the oldest row', () async {
    final db = AlertHistoryDb();
    for (var i = 0; i < 51; i++) {
      await db.insert(trigger: 'SOS button $i', outcome: 'Sent');
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }

    final entries = await db.getEntries();
    expect(entries.length, 50);
    // The very first inserted is the oldest and must be gone.
    expect(entries.any((e) => e.trigger == 'SOS button 0'), isFalse);
    // The most recent one must survive.
    expect(entries.first.trigger, 'SOS button 50');
  });

  test('clear removes every entry', () async {
    final db = AlertHistoryDb();
    await db.insert(trigger: 'SOS button', outcome: 'Sent');
    await db.insert(trigger: 'Shake to SOS', outcome: 'Sent');

    await db.clear();
    expect(await db.getEntries(), isEmpty);
  });
}
