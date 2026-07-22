# SOS History Log Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A local, bounded timeline of every real alert dispatch (SOS button, shake, check-in timer, silent trigger) — trigger, timestamp, and outcome — shown on a new History tab, per `docs/superpowers/specs/2026-07-22-sos-history-design.md`.

**Architecture:** `AlertHistoryDb` (new SQLite-backed helper, proven to work from the background service isolate the same way `DBHelper` already does) is written to from exactly two places — `EmergencyAlert.send()` and `EmergencyAlert.sendBackground()` — so every current and future trigger is covered without per-trigger wiring. `AlertHistoryPage` reads it for a new 5th nav-bar tab.

**Tech Stack:** Flutter/Dart, `sqflite` (already a dependency, same as the contacts DB), no new pub packages.

## Global Constraints

- Only actual sends are logged — no cancelled countdowns from any trigger.
- One row per entry: `timestamp`, `trigger`, `outcome` (`"Sent"` / `"Failed"`), `detail` (nullable — the failure reason).
- `trigger` values, exact strings: `"SOS button"`, `"Shake to SOS"` (used by both foreground and background shake), `"Check-in timer"`, `"Silent SOS trigger"`.
- Storage is SQLite, not Firestore — the background service isolate never runs `Firebase.initializeApp()`, so Firestore is not usable there (this is why background alerts already carry no live-share link).
- Bounded retention: keep the 50 most recent entries, prune older ones on every insert.
- A zero-guardians attempt still logs one `"Failed"` entry with detail `"Add emergency contacts first."`.
- Logging is fire-and-forget from the alert's perspective: a logging failure must never block or fail the SMS/call attempt itself (same degrade-silently pattern already used in `emergency_alert.dart` for `LiveLocationService.start()` and `GuardianShare.createShareLink()`).
- `flutter analyze --fatal-infos` must stay clean; `dart format` all new/changed files.
- Commit after every task; never add a Co-Authored-By trailer.

---

### Task 1: `AlertHistoryDb`

**Files:**
- Create: `lib/database/alert_history_db.dart`
- Test: `test/database/alert_history_db_test.dart`

**Interfaces:**
- Consumes: nothing new (`sqflite`, `path`, `path_provider` — all already dependencies).
- Produces (used by Task 2 and Task 3):
  - `class AlertHistoryEntry { final int id; final DateTime timestamp; final String trigger; final String outcome; final String? detail; }`
  - `class AlertHistoryDb { Future<void> insert({required String trigger, required String outcome, String? detail}); Future<List<AlertHistoryEntry>> getEntries(); Future<void> clear(); }`

- [ ] **Step 1: Write the failing tests**

```dart
// test/database/alert_history_db_test.dart
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/database/alert_history_db_test.dart`
Expected: FAIL — package resolve error (`lib/database/alert_history_db.dart` doesn't exist yet).

- [ ] **Step 3: Implement `AlertHistoryDb`**

```dart
// lib/database/alert_history_db.dart
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
import 'dart:io' as io;

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
        timestamp:
            DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
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
```

Note: the `dart:io` import is unused in this file as written — remove it if `flutter analyze` flags it (it was carried over from `DBHelper`'s pattern but this file has no direct `io.Directory` usage since `getApplicationDocumentsDirectory()` already returns one).

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/database/alert_history_db_test.dart`
Expected: `All tests passed!` (3 tests)

- [ ] **Step 5: Verify with static analysis**

Run: `dart format lib/database/alert_history_db.dart test/database/alert_history_db_test.dart && flutter analyze --fatal-infos`
Expected: clean. If the unused `dart:io` import is flagged, delete that import line.

- [ ] **Step 6: Commit**

```bash
git add lib/database/alert_history_db.dart test/database/alert_history_db_test.dart
git commit -m "feat: AlertHistoryDb — local, bounded log of alert dispatches"
```

---

### Task 2: Instrument `EmergencyAlert` and update every call site

**Files:**
- Modify: `lib/services/emergency_alert.dart`
- Modify: `lib/pages/sos.dart`
- Modify: `lib/navigation_bar/main_page.dart`
- Modify: `lib/services/shake_guard_service.dart`
- Modify: `test/services/emergency_alert_test.dart`

**Interfaces:**
- Consumes: `AlertHistoryDb` (Task 1).
- Produces: `EmergencyAlert.send({required String trigger})` and `EmergencyAlert.sendBackground({required String trigger, Future<String?>? coordsFuture, String? note})` — both now require a `trigger` label. Every existing and future caller must supply one; this task updates every current caller.

- [ ] **Step 1: Write the failing tests**

Add to `test/services/emergency_alert_test.dart`, right after the existing `'send() is not aborted by a live-location startup failure'` test:

```dart
  test('send() logs a Failed entry with "Add emergency contacts first." '
      'when there are no guardians', () async {
    await AlertHistoryDb().clear();
    final failures = await EmergencyAlert.send(trigger: 'Silent SOS trigger');
    expect(failures, ['Add emergency contacts first.']);

    final entries = await AlertHistoryDb().getEntries();
    expect(entries.first.trigger, 'Silent SOS trigger');
    expect(entries.first.outcome, 'Failed');
    expect(entries.first.detail, 'Add emergency contacts first.');
  });

  test('send() logs an entry with the right trigger label when guardians '
      'exist', () async {
    // The unmocked telephony/caller platform channels in this suite make
    // the actual SMS/call outcome nondeterministic (see the existing
    // "not aborted by a live-location startup failure" test's own comment
    // on this) — this test only proves an entry gets logged with the
    // caller's trigger label, not which outcome resulted.
    await AlertHistoryDb().clear();
    PermissionHandlerPlatform.instance = FakeGrantedPermissionHandlerPlatform();
    await DBHelper().add(PersonalEmergency('Sara', '01000000000'));

    await EmergencyAlert.send(trigger: 'SOS button');

    final entries = await AlertHistoryDb().getEntries();
    expect(entries, isNotEmpty);
    expect(entries.first.trigger, 'SOS button');
  });
```

Add the import, alphabetical position after the `cloud_firestore`/`firebase_auth_mocks` group with the other `safetyproject` imports:

```dart
import 'package:safetyproject/database/alert_history_db.dart';
```

Also fix the two now-broken existing calls in this file (they call `EmergencyAlert.send()` with no arguments, which will no longer compile once Step 3 lands):

- `'send() is not aborted by a live-location startup failure'` test: change `await EmergencyAlert.send();` to `await EmergencyAlert.send(trigger: 'test');`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/services/emergency_alert_test.dart`
Expected: FAIL — compile errors (`send()` doesn't accept `trigger:` yet; `AlertHistoryDb` symbol not found in this context is fine since Task 1 already created it, but `send(trigger: ...)` won't match the current signature).

- [ ] **Step 3: Implement the instrumentation**

In `lib/services/emergency_alert.dart`, add the import (alphabetical position after `'../database/db_helper.dart'`):

```dart
import '../database/alert_history_db.dart';
```

Replace the full `send()` method:

```dart
  /// Sends the full alert: SMS to every guardian, then a call to the first.
  /// SMS and call are attempted independently so one failing doesn't block
  /// the other. Returns human-readable failure messages (empty = success).
  /// Returns ['Add emergency contacts first.'] if there are no guardians.
  /// [trigger] identifies which UI trigger fired this (e.g. "SOS button",
  /// "Shake to SOS") — logged to AlertHistoryDb, nothing else.
  static Future<List<String>> send({required String trigger}) async {
    final contacts = await DBHelper().getContacts();
    if (contacts.isEmpty) {
      await _logHistory(
          trigger: trigger,
          outcome: 'Failed',
          detail: 'Add emergency contacts first.');
      return ['Add emergency contacts first.'];
    }

    // Foreground-only: this is what lets the guardian's shared page keep
    // moving instead of showing one static point. A background/killed-app
    // alert (sendBackground) has no widget tree to stream GPS from, so it
    // isn't attempted there — see this plan's Global Constraints.
    try {
      await LiveLocationService.start();
    } catch (_) {
      // Live-location startup must never block the alert itself.
    }

    final failures = <String>[];
    try {
      await sendTexts(contacts: contacts);
    } catch (e) {
      failures.add('SMS failed: $e');
    }
    try {
      await callFirstContact(contacts: contacts);
    } catch (e) {
      failures.add('Call failed: $e');
    }
    await _logHistory(
        trigger: trigger,
        outcome: failures.isEmpty ? 'Sent' : 'Failed',
        detail: failures.isEmpty ? null : failures.first);
    return failures;
  }

  /// Logs one history entry. Wrapped so a logging failure can never affect
  /// the alert itself — same degrade-silently pattern as every other
  /// bonus step on this path (live location, share link).
  static Future<void> _logHistory(
      {required String trigger,
      required String outcome,
      String? detail}) async {
    try {
      await AlertHistoryDb()
          .insert(trigger: trigger, outcome: outcome, detail: detail);
    } catch (_) {
      // degrade silently
    }
  }
```

Replace the full `sendBackground()` method:

```dart
  /// Background variant used by the Android shake-guard service: silent SMS
  /// per guardian (no composer UI), then a best-effort call. Android 10+
  /// usually blocks the dialer launch from the background — then we set
  /// [PendingCall] and report callBlocked so the notification can say
  /// "tap to call". Pass [coordsFuture] to reuse a fix already being
  /// acquired (the countdown doubles as GPS warm-up time). Pass [note] to
  /// carry a check-in timer's note through to the SMS body. [trigger]
  /// identifies which background trigger fired this (e.g. "Shake to SOS",
  /// "Check-in timer") — logged to AlertHistoryDb, nothing else.
  static Future<BackgroundSendResult> sendBackground(
      {required String trigger,
      Future<String?>? coordsFuture,
      String? note}) async {
    final contacts = await DBHelper().getContacts();
    if (contacts.isEmpty) {
      await _logHistory(
          trigger: trigger,
          outcome: 'Failed',
          detail: 'Add emergency contacts first.');
      return const BackgroundSendResult(
          smsFailures: ['Add emergency contacts first.'], callBlocked: false);
    }

    String? coords;
    try {
      coords = await (coordsFuture ?? currentCoordinates())
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      coords = null; // background GPS may be denied/slow — degrade, don't die
    }
    String? shareLink;
    try {
      shareLink = await GuardianShare.createShareLink(coords: coords);
    } catch (_) {
      // a share-link failure must never block the alert. In this background
      // isolate this currently ALWAYS degrades to null: the shake-guard
      // service never calls Firebase.initializeApp, so the FirebaseAuth
      // access above throws core/no-app every time. Background SMSes today
      // carry the static pin only — see the design doc's "Live Location
      // auto-enable, and its real limit" section.
      shareLink = null;
    }
    final message =
        buildAlertMessage(coords, shareLink: shareLink, note: note);

    final smsFailures = <String>[];
    try {
      await _requireGranted(Permission.sms, 'SMS');
      final telephony = Telephony.backgroundInstance;
      for (final c in contacts) {
        try {
          await telephony.sendSms(to: c.contactNo, message: message);
        } catch (e) {
          smsFailures.add('SMS to ${c.name} failed: $e');
        }
      }
    } catch (e) {
      smsFailures.add('SMS failed: $e');
    }

    var callBlocked = false;
    try {
      // This runs in the shake-guard's own isolate, which never runs
      // main.dart's startup code — PrimaryContactPrefs.id would otherwise
      // stay null here forever, making the call always fall back to
      // contacts.first. Reload fresh right before the call (not once at
      // service startup) since this foreground service can run for a long
      // time and the user could change the primary while it's running.
      await PrimaryContactPrefs.load();
      final ok = await callFirstContact(contacts: contacts);
      if (ok != true) callBlocked = true;
    } catch (_) {
      callBlocked = true;
    }
    if (callBlocked) await PendingCall.set();
    await _logHistory(
        trigger: trigger,
        outcome: smsFailures.isEmpty ? 'Sent' : 'Failed',
        detail: smsFailures.isEmpty ? null : smsFailures.first);
    return BackgroundSendResult(
        smsFailures: smsFailures, callBlocked: callBlocked);
  }
```

- [ ] **Step 4: Update every call site**

In `lib/pages/sos.dart`, in `_triggerFullAlert()`:

```dart
  Future<void> _triggerFullAlert() async {
    final failures = await EmergencyAlert.send(trigger: 'SOS button');
```

In `lib/navigation_bar/main_page.dart`, inside `_onShake()`'s `showSosCountdown(context, onSend: () async { ... })` callback:

```dart
      final sent = await showSosCountdown(context, onSend: () async {
        final failures = await EmergencyAlert.send(trigger: 'Shake to SOS');
```

In the same file, inside `_onSilentSosSend()`:

```dart
      final failures = await EmergencyAlert.send(trigger: 'Silent SOS trigger');
```

In `lib/services/shake_guard_service.dart`, change `_sendAlert`'s signature and its internal call:

```dart
  Future<void> _sendAlert({required String trigger, String? note}) async {
    try {
      final coords = _coordsPrefetch;
      _coordsPrefetch = null;
      final result = await EmergencyAlert.sendBackground(
          trigger: trigger, coordsFuture: coords, note: note);
```

And its two callers in `onStart`:

```dart
    _core = ShakeGuardCore(
      hasGuardians: EmergencyAlert.hasGuardians,
      send: () => _sendAlert(trigger: 'Shake to SOS'),
```

```dart
    _checkIn = CheckInTimerCore(
      send: () => _sendAlert(trigger: 'Check-in timer', note: CheckInPrefs.note.value),
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/services/emergency_alert_test.dart`
Expected: `All tests passed!`

- [ ] **Step 6: Verify with static analysis and the full suite**

Run: `dart format lib/services/emergency_alert.dart lib/pages/sos.dart lib/navigation_bar/main_page.dart lib/services/shake_guard_service.dart test/services/emergency_alert_test.dart && flutter analyze --fatal-infos && flutter test`
Expected: analyzer clean; full suite green. If any other existing test calls `EmergencyAlert.send()`/`sendBackground()` without a `trigger` argument, it will fail to compile — search for it (`grep -rn "EmergencyAlert.send\|EmergencyAlert.sendBackground" test/`) and add a `trigger: 'test'` argument there too.

- [ ] **Step 7: Commit**

```bash
git add lib/services/emergency_alert.dart lib/pages/sos.dart lib/navigation_bar/main_page.dart lib/services/shake_guard_service.dart test/services/emergency_alert_test.dart
git commit -m "feat: log every alert dispatch to AlertHistoryDb, tagged by trigger"
```

---

### Task 3: `AlertHistoryPage`

**Files:**
- Create: `lib/pages/alert_history_page.dart`
- Test: `test/pages/alert_history_page_test.dart`

**Interfaces:**
- Consumes: `AlertHistoryDb`/`AlertHistoryEntry` (Task 1), `LumiColors`/`LumiText` (`lib/theme/lumi_theme.dart`), `LumiCard`/`LumiStatusPill` (`lib/widgets/lumi_widgets.dart`).
- Produces (used by Task 4): `AlertHistoryPage` — a content-only widget (no `Scaffold`), same shape as `SosPage`/`LocationPage`/`PersonalEmergencyContacts`.

- [ ] **Step 1: Write the failing tests**

```dart
// test/pages/alert_history_page_test.dart
// AlertHistoryPage: renders seeded entries newest first, the empty state
// with none, pull-to-refresh re-queries, and Clear history empties both the
// list and the underlying table.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safetyproject/database/alert_history_db.dart';
import 'package:safetyproject/pages/alert_history_page.dart';

import '../test_helpers.dart';

void main() {
  configureTestEnvironment();

  setUp(() async {
    await AlertHistoryDb().clear();
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: AlertHistoryPage()),
    ));
    await settleWithRealAsync(tester);
  }

  testWidgets('shows the empty state with no entries', (tester) async {
    await pumpPage(tester);
    expect(find.text('No alerts yet'), findsOneWidget);
  });

  testWidgets('renders seeded entries newest first with trigger, outcome '
      'and detail', (tester) async {
    await tester.runAsync(() async {
      await AlertHistoryDb().insert(trigger: 'SOS button', outcome: 'Sent');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await AlertHistoryDb().insert(
          trigger: 'Shake to SOS',
          outcome: 'Failed',
          detail: 'Add emergency contacts first.');
    });
    await pumpPage(tester);

    expect(find.text('SOS button'), findsOneWidget);
    expect(find.text('Shake to SOS'), findsOneWidget);
    expect(find.text('Sent'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('Add emergency contacts first.'), findsOneWidget);

    // Newest first: Shake to SOS (inserted second) appears above SOS button.
    final shakeY = tester.getTopLeft(find.text('Shake to SOS')).dy;
    final sosY = tester.getTopLeft(find.text('SOS button')).dy;
    expect(shakeY, lessThan(sosY));
  });

  testWidgets('pull-to-refresh re-queries and shows a newly inserted entry',
      (tester) async {
    await pumpPage(tester);
    expect(find.text('No alerts yet'), findsOneWidget);

    await tester.runAsync(() => AlertHistoryDb()
        .insert(trigger: 'SOS button', outcome: 'Sent'));

    await tester.fling(
        find.byType(RefreshIndicator), const Offset(0, 300), 1000);
    await tester.pump();
    await settleWithRealAsync(tester);
    await tester.pumpAndSettle();

    expect(find.text('SOS button'), findsOneWidget);
  });

  testWidgets('Clear history confirms then empties the list and the table',
      (tester) async {
    await tester.runAsync(() => AlertHistoryDb()
        .insert(trigger: 'SOS button', outcome: 'Sent'));
    await pumpPage(tester);
    expect(find.text('SOS button'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.text('Clear alert history'), findsOneWidget);

    await tester.tap(find.text('Clear'));
    await settleWithRealAsync(tester);

    expect(find.text('No alerts yet'), findsOneWidget);
    expect(await AlertHistoryDb().getEntries(), isEmpty);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/pages/alert_history_page_test.dart`
Expected: FAIL — package resolve error (`lib/pages/alert_history_page.dart` doesn't exist yet).

- [ ] **Step 3: Implement `AlertHistoryPage`**

```dart
// lib/pages/alert_history_page.dart
// ─────────────────────────────────────────────────────────────────────────────
//  Lumi · Alert history (History tab)
//  Returns CONTENT only (no Scaffold) — LumiMainNav/NavBarPage provides the
//  gradient + bar, matching every other tab page.
//  See docs/superpowers/specs/2026-07-22-sos-history-design.md
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';

import '../database/alert_history_db.dart';
import '../theme/lumi_theme.dart';
import '../widgets/lumi_widgets.dart';

const _triggerIcons = {
  'SOS button': Icons.warning_amber_rounded,
  'Shake to SOS': Icons.vibration,
  'Check-in timer': Icons.timer_outlined,
  'Silent SOS trigger': Icons.volume_down,
};

class AlertHistoryPage extends StatefulWidget {
  const AlertHistoryPage({super.key});

  @override
  State<AlertHistoryPage> createState() => _AlertHistoryPageState();
}

class _AlertHistoryPageState extends State<AlertHistoryPage> {
  final _db = AlertHistoryDb();
  late Future<List<AlertHistoryEntry>> _entriesFuture;

  @override
  void initState() {
    super.initState();
    _entriesFuture = _db.getEntries();
  }

  Future<void> _refresh() async {
    final future = _db.getEntries();
    setState(() => _entriesFuture = future);
    await future;
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: LumiColors.surface,
        title: Text('Clear alert history', style: LumiText.display(18)),
        content: Text("This can't be undone.",
            style: LumiText.body(14, color: LumiColors.textSub)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel',
                  style: LumiText.body(14, color: LumiColors.textSub))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Clear',
                  style: LumiText.body(14,
                      weight: FontWeight.w700, color: LumiColors.accent))),
        ],
      ),
    );
    if (ok == true) {
      await _db.clear();
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Text('History', style: LumiText.display(24)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      color: LumiColors.textSub),
                  onPressed: _confirmClear,
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('Every alert Lumi has sent, on this device.',
                style: LumiText.body(13, color: LumiColors.textSub)),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              color: LumiColors.accent,
              child: FutureBuilder<List<AlertHistoryEntry>>(
                future: _entriesFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                        child: CircularProgressIndicator(
                            color: LumiColors.accent));
                  }
                  final entries = snapshot.data ?? [];
                  if (entries.isEmpty) {
                    return ListView(
                      // Scrollable even when empty, so pull-to-refresh
                      // still works with nothing on screen.
                      children: [
                        SizedBox(
                          height: 300,
                          child: Center(
                            child: Text('No alerts yet',
                                style: LumiText.body(13,
                                    color: LumiColors.textSub)),
                          ),
                        ),
                      ],
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.only(bottom: 100),
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 11),
                    itemBuilder: (context, i) => _EntryTile(entry: entries[i]),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry});
  final AlertHistoryEntry entry;

  String _formatTimestamp(DateTime t) {
    final now = DateTime.now();
    final isToday =
        t.year == now.year && t.month == now.month && t.day == now.day;
    final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final minute = t.minute.toString().padLeft(2, '0');
    final ampm = t.hour >= 12 ? 'PM' : 'AM';
    final time = '$hour:$minute $ampm';
    if (isToday) return 'Today $time';
    return '${t.month}/${t.day}/${t.year} $time';
  }

  @override
  Widget build(BuildContext context) {
    final sent = entry.outcome == 'Sent';
    return LumiCard(
      child: Row(
        children: [
          Icon(_triggerIcons[entry.trigger] ?? Icons.notifications_outlined,
              color: LumiColors.blue, size: 22),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.trigger,
                    style: LumiText.body(14.5, weight: FontWeight.w700)),
                Text(_formatTimestamp(entry.timestamp),
                    style: LumiText.body(12, color: LumiColors.textSub)),
                if (entry.detail != null) ...[
                  const SizedBox(height: 2),
                  Text(entry.detail!,
                      style: LumiText.body(11.5, color: LumiColors.textSub)),
                ],
              ],
            ),
          ),
          LumiStatusPill(
              label: entry.outcome,
              color: sent ? LumiColors.green : LumiColors.accent),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/pages/alert_history_page_test.dart`
Expected: `All tests passed!` (4 tests). If the pull-to-refresh test is flaky about pump timing, add an extra `await tester.pump(const Duration(milliseconds: 500));` before the final assertion rather than changing the widget's logic.

- [ ] **Step 5: Verify with static analysis**

Run: `dart format lib/pages/alert_history_page.dart test/pages/alert_history_page_test.dart && flutter analyze --fatal-infos`
Expected: clean.

- [ ] **Step 6: Commit**

```bash
git add lib/pages/alert_history_page.dart test/pages/alert_history_page_test.dart
git commit -m "feat: AlertHistoryPage — the History tab's list, empty state, and clear action"
```

---

### Task 4: Nav bar wiring, on-device verification, and docs

**Files:**
- Modify: `lib/navigation_bar/main_page.dart`
- Modify: `README.md`

**Interfaces:**
- Consumes: `AlertHistoryPage` (Task 3).
- Produces: user-visible feature; nothing downstream.

No widget test for this task: `NavBarPage` is never constructed directly in this project's test suite (matches the same precedent noted in the fake-call and silent-SOS-trigger plans' final wiring tasks). Verified via the on-emulator checklist below.

- [ ] **Step 1: Add the import and the 5th tab**

In `lib/navigation_bar/main_page.dart`, add to the import block, alphabetical position after `'../pages/location_page.dart'`:

```dart
import '../pages/alert_history_page.dart';
```

In `_NavBarPageState`, add a 5th entry to `_pages`:

```dart
  late final List<Widget> _pages = [
    const LocationPage(),
    SosPage(userName: _nameFromEmail(widget.email)),
    const PersonalEmergencyContacts(),
    const GoogleMapPage(), // your existing map (keeps its own Scaffold)
    const AlertHistoryPage(),
  ];
```

In `_LumiTabBar.build()`, add a 5th tab after the Map tab:

```dart
            children: [
              _tab(0, Icons.location_on_outlined, Icons.location_on, 'Track'),
              _sosTab(1),
              _tab(2, Icons.people_outline, Icons.people, 'Contacts'),
              _tab(3, Icons.map_outlined, Icons.map, 'Map'),
              _tab(4, Icons.history_outlined, Icons.history, 'History'),
            ],
```

- [ ] **Step 2: Run the full suite and analyzer**

Run: `dart format lib/navigation_bar/main_page.dart && flutter analyze --fatal-infos && flutter test`
Expected: analyzer clean; full suite green.

- [ ] **Step 3: Commit and push**

```bash
git add lib/navigation_bar/main_page.dart
git commit -m "feat: add the History tab to the nav bar"
git push origin master
```

Watch CI: `gh run watch $(gh run list --repo AhmedElatreby/Graduation_project --limit 1 --json databaseId --jq '.[0].databaseId') --repo AhmedElatreby/Graduation_project --exit-status` — must go green.

- [ ] **Step 4: On-emulator verification**

On the Android emulator (`flutter emulators --launch Pixel9_API37_16k`, `flutter run -d emulator-5554`, `adb` at `~/Library/Android/sdk/platform-tools/adb`) — never the physical Samsung without explicit say-so. Confirm `dumpsys window | grep mCurrentFocus` shows Lumi foregrounded before any alert-triggering step, and seed exactly one safe placeholder guardian (obviously-fake number, confirmed via `adb shell run-as com.elatreby.safety cat app_flutter/EmergencyContacts.db` + `sqlite3` — never trust the in-app count) before any test that completes a real send:

1. Open the new History tab (5th icon) with a fresh install / cleared history → confirm "No alerts yet".
2. Trigger a real send with the seeded guardian present (SOS hold button is simplest and needs no extra setup) → open History → confirm one new entry: trigger "SOS button", outcome "Sent" (or "Failed" with a plausible detail, if the emulator's SMS/telephony state is degraded — note either way; the plan's job is to prove an entry appears with the right trigger, not to fight emulator SMS flakiness already documented in this project's memory).
3. Remove the guardian, trigger again → confirm a new entry: outcome "Failed", detail "Add emergency contacts first.".
4. Pull down on the History list → confirm it doesn't error and (if a send happened in the background meanwhile) picks up new entries.
5. Tap the trash icon → confirm the "Clear alert history" dialog appears; Cancel → list unchanged. Tap trash again → Clear → confirm the list empties immediately.
6. Force-stop and cold-relaunch the app (`am force-stop` then `am start`, not just backgrounding) → open History tab → confirm it's still empty (the clear persisted, not just an in-memory reset).

Record the outcome of each numbered check.

- [ ] **Step 5: README bullet**

In `README.md`, add a new bullet to the `### Alerting` section, after the "Silent SOS trigger" bullet:

```markdown
- **Alert history** — every real alert dispatch (SOS button, shake, check-in
  timer, silent trigger) is logged locally with a timestamp and outcome,
  viewable on the History tab. Local-only, capped at the 50 most recent
  entries, with a one-tap Clear action.
```

- [ ] **Step 6: Full suite green, commit, push, watch CI**

Run: `flutter analyze --fatal-infos && flutter test`
Expected: clean.

```bash
git add README.md docs/superpowers/plans/2026-07-22-sos-history.md
git commit -m "docs: README alert history; tick sos-history plan"
git push origin master
gh run watch $(gh run list --repo AhmedElatreby/Graduation_project --limit 1 --json databaseId --jq '.[0].databaseId') --repo AhmedElatreby/Graduation_project --exit-status
```

Expected: CI green.

---

## Self-Review Notes

- **Spec coverage:** SQLite storage + 50-cap + entry shape (Task 1), single instrumentation point in `send()`/`sendBackground()` with the exact 4 trigger labels covering all 5 call sites (SOS button, foreground shake, background shake, check-in timer, silent trigger) + no-guardians logging (Task 2), History tab UI with empty state/pull-to-refresh/Clear (Task 3), 5th nav-bar tab + on-emulator checklist covering the send/no-guardians/refresh/clear/persistence cases + README (Task 4). Out-of-scope items (cancelled countdowns, per-guardian breakdown, note/location storage, cloud sync) have no tasks — correct.
- **Type consistency:** `AlertHistoryEntry`'s fields and `AlertHistoryDb`'s three methods are used identically across Tasks 2 and 3. The `trigger`/`outcome`/`detail` string values match exactly between the spec's decision table, Task 2's instrumentation, and Task 3's `_triggerIcons` map keys — a typo in any of the 4 trigger strings would silently fall through to the generic `Icons.notifications_outlined` fallback rather than crash, which is why Task 2's call-site edits are given verbatim rather than described.
- **Known risk:** Task 2 touches 4 non-test files across 3 different trigger mechanisms (foreground UI, background service) in one task — this is intentionally one task because `send()`/`sendBackground()` gaining a required parameter doesn't compile until every caller is updated together; there is no meaningful smaller increment. Double-check `grep -rn "EmergencyAlert.send(" lib/ test/` and `grep -rn "EmergencyAlert.sendBackground(" lib/ test/` after Step 4 turn up zero call sites still missing a `trigger:` argument before moving to Step 5.
