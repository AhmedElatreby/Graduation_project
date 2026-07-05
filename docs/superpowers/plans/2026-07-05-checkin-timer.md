# Check-in Timer ("Walk me home") Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a check-in timer to the Track page — start a countdown before
a trip, live location shares automatically, and if you don't cancel in
time a grace-period warning fires, then the same SMS+call alert as the SOS
button and shake-to-SOS.

**Architecture:** Two new pure-Dart, unit-tested pieces (`CheckInPrefs` for
persistence, `CheckInTimerCore` for the countdown/grace/send state machine)
plug into the existing `ShakeGuardService` foreground service (which already
keeps shake-to-SOS running in the background) as a second, independent state
machine sharing one persistent notification. `EmergencyAlert` gains an
optional note parameter. The Track page gets a new card with three visual
states (idle / running / grace) computed the same read-only way in both the
UI isolate and the service isolate, so there is exactly one place
(`CheckInTimerCore` inside the service) that ever decides to actually cancel
or send.

**Tech Stack:** Flutter/Dart, `shared_preferences` (persistence),
`flutter_foreground_task` (background survival, already a dependency),
`package:clock` (new dependency — makes `CheckInTimerCore`'s wall-clock reads
fake-able in tests the same way `Timer` already is via `fake_async`).

## Global Constraints

- Grace period is **60 seconds** by default (`CheckInTimerCore.graceSeconds`).
- Duration presets on the Track card are **10 / 20 / 30 / 60 minutes**, plus
  a custom option.
- A missed check-in sends the **exact same alert** as the SOS button and
  shake-to-SOS (`EmergencyAlert`'s SMS+call pipeline) — never a distinct
  "softer" message.
- Starting a timer is blocked (no service/timer state changes at all) if
  `EmergencyAlert.hasGuardians()` is false.
- No modal dialog for the grace period — it's an inline Track-card state,
  per `docs/superpowers/specs/2026-07-05-checkin-timer-design.md`'s
  "Why not a modal dialog" section. Do not reintroduce
  `showSosCountdown`-based UI for this feature.
- `ShakeGuardService` keeps its current name and file — do not rename it or
  split it into two services.

---

### Task 1: `CheckInPrefs` — persisted timer state

**Files:**
- Create: `lib/services/checkin_prefs.dart`
- Test: `test/services/checkin_prefs_test.dart`

**Interfaces:**
- Produces: `CheckInPrefs.endTime` (`ValueNotifier<DateTime?>`, null = no
  timer running), `CheckInPrefs.note` (`ValueNotifier<String?>`),
  `CheckInPrefs.load()` (`Future<void>`), `CheckInPrefs.start(Duration
  duration, {String? note})` (`Future<void>`), `CheckInPrefs.clear()`
  (`Future<void>`). Every later task that reads or writes timer state goes
  through these four names — no other task introduces its own persistence.

- [ ] **Step 1: Write the failing tests**

Create `test/services/checkin_prefs_test.dart`:

```dart
// CheckInPrefs: no timer by default, start()/clear() persist and survive a
// reload, note is optional and cleared independently of a missing endTime.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safetyproject/services/checkin_prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('no timer running by default', () async {
    SharedPreferences.setMockInitialValues({});
    await CheckInPrefs.load();
    expect(CheckInPrefs.endTime.value, isNull);
    expect(CheckInPrefs.note.value, isNull);
  });

  test('start persists the end time and survives a reload', () async {
    SharedPreferences.setMockInitialValues({});
    await CheckInPrefs.load();

    await CheckInPrefs.start(const Duration(minutes: 20));
    final started = CheckInPrefs.endTime.value;
    expect(started, isNotNull);

    // Simulate a fresh isolate reading the same store.
    CheckInPrefs.endTime.value = null; // scribble over the in-memory value
    await CheckInPrefs.load();
    expect(CheckInPrefs.endTime.value, started);
  });

  test('start persists an optional note', () async {
    SharedPreferences.setMockInitialValues({});
    await CheckInPrefs.load();

    await CheckInPrefs.start(const Duration(minutes: 10),
        note: 'walking home from the station');
    expect(CheckInPrefs.note.value, 'walking home from the station');

    CheckInPrefs.note.value = null;
    await CheckInPrefs.load();
    expect(CheckInPrefs.note.value, 'walking home from the station');
  });

  test('clear removes both the end time and the note', () async {
    SharedPreferences.setMockInitialValues({});
    await CheckInPrefs.load();
    await CheckInPrefs.start(const Duration(minutes: 10), note: 'test');

    await CheckInPrefs.clear();
    expect(CheckInPrefs.endTime.value, isNull);
    expect(CheckInPrefs.note.value, isNull);

    await CheckInPrefs.load();
    expect(CheckInPrefs.endTime.value, isNull);
    expect(CheckInPrefs.note.value, isNull);
  });

  test('starting again without a note clears any previous note', () async {
    SharedPreferences.setMockInitialValues({});
    await CheckInPrefs.load();
    await CheckInPrefs.start(const Duration(minutes: 10), note: 'first note');

    await CheckInPrefs.start(const Duration(minutes: 5));
    expect(CheckInPrefs.note.value, isNull);

    await CheckInPrefs.load();
    expect(CheckInPrefs.note.value, isNull);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/services/checkin_prefs_test.dart`
Expected: FAIL — `package:safetyproject/services/checkin_prefs.dart` doesn't
exist yet (import error).

- [ ] **Step 3: Implement `CheckInPrefs`**

Create `lib/services/checkin_prefs.dart`:

```dart
// ─────────────────────────────────────────────────────────────────────────────
//  Lumi · Check-in timer preferences
//  Persists a running timer's end time (and optional note) so it survives
//  app restart, device reboot, and the foreground service being killed and
//  restarted by Android — the timestamp is the single source of truth,
//  never a remaining-Duration counter that would need to keep ticking in
//  memory to stay correct.
//  See docs/superpowers/specs/2026-07-05-checkin-timer-design.md
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CheckInPrefs {
  CheckInPrefs._();

  static const _endTimeKey = 'checkin_end_time_millis';
  static const _noteKey = 'checkin_note';

  /// Null when no timer is running.
  static final ValueNotifier<DateTime?> endTime = ValueNotifier(null);
  static final ValueNotifier<String?> note = ValueNotifier(null);

  /// Load the persisted values (call once at startup/service-start, before
  /// first read — each isolate has its own SharedPreferences access and its
  /// own copy of these ValueNotifiers).
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final millis = prefs.getInt(_endTimeKey);
    endTime.value =
        millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
    note.value = prefs.getString(_noteKey);
  }

  static Future<void> start(Duration duration, {String? note}) async {
    final end = DateTime.now().add(duration);
    endTime.value = end;
    CheckInPrefs.note.value = note;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_endTimeKey, end.millisecondsSinceEpoch);
    if (note == null) {
      await prefs.remove(_noteKey);
    } else {
      await prefs.setString(_noteKey, note);
    }
  }

  /// Clears both keys. Called on cancel, and after a sent alert.
  static Future<void> clear() async {
    endTime.value = null;
    note.value = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_endTimeKey);
    await prefs.remove(_noteKey);
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/services/checkin_prefs_test.dart`
Expected: PASS (5/5)

- [ ] **Step 5: Commit**

```bash
git add lib/services/checkin_prefs.dart test/services/checkin_prefs_test.dart
git commit -m "feat: add CheckInPrefs for persisted check-in timer state"
```

---

### Task 2: `CheckInTimerCore` — countdown/grace/send state machine

**Files:**
- Modify: `pubspec.yaml` (add the `clock` dependency)
- Create: `lib/services/checkin_timer_core.dart`
- Test: `test/services/checkin_timer_core_test.dart`

**Interfaces:**
- Consumes: nothing from Task 1 — this is pure Dart with no persistence or
  plugin imports.
- Produces: `CheckInTimerCore` constructor taking `send` (`Future<void>
  Function()`), `onTick` (`void Function(Duration remaining)`),
  `onGraceTick` (`void Function(int secondsRemaining)`), `onCancelled`
  (`void Function()`), `onSent` (`void Function()`), `graceSeconds` (`int`,
  default `60`); methods `start(DateTime endTime)`, `cancel()`,
  `dispose()`. Task 4 constructs and wires exactly these callback names.

- [ ] **Step 1: Add the `clock` dependency**

In `pubspec.yaml`, under `dependencies:`, immediately after the
`flutter_foreground_task: ^8.17.0` line, add:

```yaml
  clock: ^1.1.1
```

`fake_async` (already a dev dependency) is built on `package:clock` — code
under test must read the current time via `clock.now()` rather than
`DateTime.now()` directly for `fakeAsync`'s virtual clock to actually affect
it. This is why this task needs the dependency and `ShakeGuardCore` (which
never reads wall-clock time, only counts an integer) never did.

Run: `flutter pub get`
Expected: resolves cleanly, `clock` added to `pubspec.lock`.

- [ ] **Step 2: Write the failing tests**

Create `test/services/checkin_timer_core_test.dart`:

```dart
// The check-in timer state machine: counts down, enters a grace period at
// zero, sends exactly once if the grace period also elapses, and cancel
// stops either phase without ever sending.
import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safetyproject/services/checkin_timer_core.dart';

class _Probe {
  int sends = 0, cancels = 0, sents = 0;
  final ticks = <Duration>[];
  final graceTicks = <int>[];

  late CheckInTimerCore core;

  _Probe({int graceSeconds = 3}) {
    core = CheckInTimerCore(
      send: () async => sends++,
      onTick: ticks.add,
      onGraceTick: graceTicks.add,
      onCancelled: () => cancels++,
      onSent: () => sents++,
      graceSeconds: graceSeconds,
    );
  }
}

void main() {
  test('counts down every second while above zero', () {
    fakeAsync((async) {
      final p = _Probe();
      p.core.start(clock.now().add(const Duration(seconds: 3)));
      expect(p.ticks, [const Duration(seconds: 3)]);

      async.elapse(const Duration(seconds: 1));
      expect(p.ticks.last, const Duration(seconds: 2));

      async.elapse(const Duration(seconds: 1));
      expect(p.ticks.last, const Duration(seconds: 1));

      expect(p.graceTicks, isEmpty);
      expect(p.sends, 0);
    });
  });

  test('reaching zero enters the grace period and sends once it also elapses',
      () {
    fakeAsync((async) {
      final p = _Probe(graceSeconds: 3);
      p.core.start(clock.now().add(const Duration(seconds: 2)));

      async.elapse(const Duration(seconds: 2));
      expect(p.graceTicks, [3]);
      expect(p.sends, 0);

      async.elapse(const Duration(seconds: 1));
      expect(p.graceTicks, [3, 2]);

      async.elapse(const Duration(seconds: 1));
      expect(p.graceTicks, [3, 2, 1]);
      expect(p.sends, 0);

      async.elapse(const Duration(seconds: 1));
      expect(p.sends, 1);
      expect(p.sents, 1);

      // Never double-fires even well past the deadline.
      async.elapse(const Duration(seconds: 10));
      expect(p.sends, 1);
    });
  });

  test('cancel during the main countdown stops it and never sends', () {
    fakeAsync((async) {
      final p = _Probe();
      p.core.start(clock.now().add(const Duration(seconds: 5)));
      async.elapse(const Duration(seconds: 2));

      p.core.cancel();
      expect(p.cancels, 1);

      async.elapse(const Duration(seconds: 10));
      expect(p.sends, 0);
      expect(p.graceTicks, isEmpty);
    });
  });

  test('cancel during the grace period stops it and never sends', () {
    fakeAsync((async) {
      final p = _Probe(graceSeconds: 3);
      p.core.start(clock.now().add(const Duration(seconds: 1)));
      async.elapse(const Duration(seconds: 1));
      expect(p.graceTicks, isNotEmpty);

      p.core.cancel();
      expect(p.cancels, 1);

      async.elapse(const Duration(seconds: 10));
      expect(p.sends, 0);
    });
  });

  test('cancel is a no-op once already sent', () {
    fakeAsync((async) {
      final p = _Probe(graceSeconds: 1);
      p.core.start(clock.now().add(const Duration(seconds: 1)));
      async.elapse(const Duration(seconds: 2));
      expect(p.sends, 1);

      p.core.cancel(); // must not call onCancelled after a send
      expect(p.cancels, 0);
    });
  });

  test(
      'starting with an endTime already past the main duration goes '
      'straight into the grace period', () {
    fakeAsync((async) {
      final p = _Probe(graceSeconds: 5);
      // 2 seconds already elapsed past the main deadline before start() is
      // even called (e.g. the service restarted late after an OS kill).
      p.core.start(clock.now().subtract(const Duration(seconds: 2)));

      expect(p.ticks, isEmpty); // never shows the main countdown
      expect(p.graceTicks, [3]); // 5s grace minus the 2s already elapsed

      async.elapse(const Duration(seconds: 3));
      expect(p.sends, 1);
    });
  });

  test(
      'starting with an endTime past both the duration and the grace '
      'period sends immediately', () {
    fakeAsync((async) {
      final p = _Probe(graceSeconds: 5);
      p.core.start(clock.now().subtract(const Duration(seconds: 10)));
      async.flushMicrotasks(); // let the fire-and-forget send()/onSent() run

      expect(p.sends, 1);
      expect(p.sents, 1);
      expect(p.ticks, isEmpty);
      expect(p.graceTicks, isEmpty);
    });
  });
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `flutter test test/services/checkin_timer_core_test.dart`
Expected: FAIL — `checkin_timer_core.dart` doesn't exist yet.

- [ ] **Step 4: Implement `CheckInTimerCore`**

Create `lib/services/checkin_timer_core.dart`:

```dart
// ─────────────────────────────────────────────────────────────────────────────
//  Lumi · Check-in timer state machine
//  Pure Dart so the countdown/grace/cancel/dispatch rules are unit-testable
//  (mirrors ShakeGuardCore's shape). Recomputes remaining time from a wall-
//  clock instant on every tick rather than an in-memory counter — that's
//  what makes recovering a timer after an app/service restart correct.
//  See docs/superpowers/specs/2026-07-05-checkin-timer-design.md
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';

import 'package:clock/clock.dart';

class CheckInTimerCore {
  /// Exposed so callers that need to know the grace window without
  /// constructing a core — e.g. the Track-page card computing which of the
  /// three UI states to show — use the same number instead of a duplicated
  /// magic constant that could drift out of sync.
  static const defaultGraceSeconds = 60;

  CheckInTimerCore({
    required this.send,
    required this.onTick,
    required this.onGraceTick,
    required this.onCancelled,
    required this.onSent,
    this.graceSeconds = defaultGraceSeconds,
  });

  final Future<void> Function() send;
  final void Function(Duration remaining) onTick;
  final void Function(int secondsRemaining) onGraceTick;
  final void Function() onCancelled;
  final void Function() onSent;
  final int graceSeconds;

  bool _running = false;
  Timer? _timer;
  DateTime? _endTime;

  bool get isRunning => _running;

  /// Starts (or resumes, after a restart) counting down to [endTime]. If
  /// [endTime] is already in the past, evaluates straight into the grace
  /// phase (or straight to sending, if the grace period has also already
  /// elapsed) instead of it being a special case — a Duration in the past
  /// behaves exactly like "zero remaining" to the phase logic below.
  void start(DateTime endTime) {
    _timer?.cancel();
    _endTime = endTime;
    _running = true;
    _evaluate();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _evaluate());
  }

  Future<void> _evaluate() async {
    if (!_running) return;
    final end = _endTime!;
    final now = clock.now();

    final mainRemaining = end.difference(now);
    if (mainRemaining > Duration.zero) {
      onTick(mainRemaining);
      return;
    }

    final graceDeadline = end.add(Duration(seconds: graceSeconds));
    final graceRemaining = graceDeadline.difference(now);
    if (graceRemaining > Duration.zero) {
      onGraceTick((graceRemaining.inMilliseconds / 1000).ceil());
      return;
    }

    _timer?.cancel();
    _running = false;
    try {
      await send();
    } catch (_) {
      // Swallow: still reset and call onSent to unblock the UI/notification.
    }
    onSent();
  }

  void cancel() {
    if (!_running) return;
    _timer?.cancel();
    _running = false;
    onCancelled();
  }

  void dispose() => _timer?.cancel();
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/services/checkin_timer_core_test.dart`
Expected: PASS (7/7)

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/services/checkin_timer_core.dart test/services/checkin_timer_core_test.dart
git commit -m "feat: add CheckInTimerCore countdown/grace/send state machine"
```

---

### Task 3: Extend `EmergencyAlert` with an optional note

**Files:**
- Modify: `lib/services/emergency_alert.dart`
- Test: `test/services/emergency_alert_test.dart`

**Interfaces:**
- Consumes: nothing from Tasks 1–2.
- Produces: `EmergencyAlert.buildAlertMessage(String? coords, {String?
  note})` and `EmergencyAlert.sendBackground({Future<String?>? coordsFuture,
  String? note})` — Task 4's `_sendAlert` helper passes `note:
  CheckInPrefs.note.value` through this exact parameter name.

- [ ] **Step 1: Write the failing test**

In `test/services/emergency_alert_test.dart`, add this test inside `main()`,
after the existing `buildAlertMessage includes the maps link...` test:

```dart
  test('buildAlertMessage appends a note on its own line when provided', () {
    expect(
      EmergencyAlert.buildAlertMessage('50.73,-1.85',
          note: 'walking home from the station'),
      'I need help, please find me: https://maps.google.com/?q=50.73,-1.85\n'
      'walking home from the station',
    );
    expect(
      EmergencyAlert.buildAlertMessage(null, note: 'test note'),
      'I need help! (My location is unavailable right now.)\ntest note',
    );
    // No note: byte-for-byte identical to today's message (SOS button and
    // shake-to-SOS pass no note and must see no change).
    expect(
      EmergencyAlert.buildAlertMessage('50.73,-1.85'),
      'I need help, please find me: https://maps.google.com/?q=50.73,-1.85',
    );
  });
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/services/emergency_alert_test.dart`
Expected: FAIL — `buildAlertMessage` doesn't accept a `note` named argument
yet (compile error).

- [ ] **Step 3: Implement the note parameter**

In `lib/services/emergency_alert.dart`, replace:

```dart
  /// The SMS body. Extracted so the foreground composer path and the
  /// background silent path can never drift apart.
  static String buildAlertMessage(String? coords) => coords == null
      ? 'I need help! (My location is unavailable right now.)'
      : 'I need help, please find me: https://maps.google.com/?q=$coords';
```

with:

```dart
  /// The SMS body. Extracted so the foreground composer path and the
  /// background silent path can never drift apart. [note] (e.g. a check-in
  /// timer's "walking home from the station") is appended on its own line
  /// when present; omitting it leaves the message byte-for-byte what it is
  /// today, so the SOS button and shake-to-SOS (which pass no note) see no
  /// change.
  static String buildAlertMessage(String? coords, {String? note}) {
    final base = coords == null
        ? 'I need help! (My location is unavailable right now.)'
        : 'I need help, please find me: https://maps.google.com/?q=$coords';
    return note == null ? base : '$base\n$note';
  }
```

Then update `sendBackground` to accept and thread the note through. Replace:

```dart
  static Future<BackgroundSendResult> sendBackground(
      {Future<String?>? coordsFuture}) async {
    final contacts = await DBHelper().getContacts();
    if (contacts.isEmpty) {
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
    final message = buildAlertMessage(coords);
```

with:

```dart
  static Future<BackgroundSendResult> sendBackground(
      {Future<String?>? coordsFuture, String? note}) async {
    final contacts = await DBHelper().getContacts();
    if (contacts.isEmpty) {
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
    final message = buildAlertMessage(coords, note: note);
```

(The rest of `sendBackground`'s body — the SMS loop and call attempt — is
unchanged; only the `buildAlertMessage(coords)` call site inside it gets the
new `note:` argument.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/services/emergency_alert_test.dart`
Expected: PASS (4/4)

- [ ] **Step 5: Run the full test suite to confirm nothing else broke**

Run: `flutter test`
Expected: all tests PASS (no other call site of `buildAlertMessage` or
`sendBackground` passes positional-only arguments that this change would
break — both are additive optional parameters).

- [ ] **Step 6: Commit**

```bash
git add lib/services/emergency_alert.dart test/services/emergency_alert_test.dart
git commit -m "feat: EmergencyAlert accepts an optional note for check-in alerts"
```

---

### Task 4: Wire `CheckInTimerCore` into `ShakeGuardService`

**Files:**
- Modify: `lib/services/shake_guard_service.dart`

**Interfaces:**
- Consumes: `CheckInPrefs.load/endTime/note/clear` (Task 1),
  `CheckInTimerCore` (Task 2), `EmergencyAlert.sendBackground(...,
  note: ...)` (Task 3).
- Produces: `ShakeGuardService.notifyCheckInStart()` and
  `ShakeGuardService.notifyCheckInCancel()` — Task 5's `NavBarPage` calls
  exactly these two names, mirroring the existing
  `ShakeGuardService.notifySensitivity(...)` call site.

This task is glue code wiring an already-tested state machine into an
already-tested notification/IPC shell — verified by `flutter analyze` plus
on-device testing in Task 6 (the card can't be exercised without the
service running), not a new unit test file, matching how the rest of
`shake_guard_service.dart` is verified today.

- [ ] **Step 1: Add imports and the second core**

In `lib/services/shake_guard_service.dart`, add to the imports:

```dart
import 'checkin_prefs.dart';
import 'checkin_timer_core.dart';
```

- [ ] **Step 2: Add `notifyCheckInStart`/`notifyCheckInCancel` to `ShakeGuardService`**

Add these two static methods to the `ShakeGuardService` class, directly
after the existing `notifySensitivity`:

```dart
  /// Tells the running service to (re)start its check-in countdown from
  /// whatever CheckInPrefs currently holds on disk (no-op if the service
  /// isn't running). The note's free text travels via CheckInPrefs, not
  /// this message, the same way ShakePrefs already does for `onStart`.
  static void notifyCheckInStart() =>
      FlutterForegroundTask.sendDataToTask('checkin_start');

  static void notifyCheckInCancel() =>
      FlutterForegroundTask.sendDataToTask('checkin_cancel');
```

- [ ] **Step 3: Add the `_checkIn` field and construct it in `onStart`**

In `_ShakeGuardTaskHandler`, add a field alongside the existing `_core`:

```dart
  CheckInTimerCore? _checkIn;
```

Add a second cancel-button id near the existing `_cancelButtonId`:

```dart
  static const _cancelCheckInButtonId = 'cancel_checkin';
  static const _cancelCheckInButton = NotificationButton(
      id: _cancelCheckInButtonId, text: "I'm safe — cancel");
```

Replace the existing `onStart` body:

```dart
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _core = ShakeGuardCore(
      hasGuardians: EmergencyAlert.hasGuardians,
      send: _sendAlert,
      onTick: (remaining) {
        _coordsPrefetch ??= EmergencyAlert.currentCoordinates();
        FlutterForegroundTask.updateService(
          notificationTitle: 'Shake detected',
          notificationText: 'Alerting your guardians in $remaining…',
          notificationButtons: const [_cancelButton],
        );
      },
      onCancelled: () {
        _coordsPrefetch = null;
        _idleNotification();
      },
      onSent: () {}, // _sendAlert wrote the result notification already
      onNoGuardians: () => FlutterForegroundTask.updateService(
        notificationTitle: 'Add guardians first',
        notificationText:
            'Open Lumi and add a guardian so an SOS can reach someone.',
        notificationButtons: const [],
      ),
    );
    await ShakePrefs.load(); // this isolate has its own SharedPreferences access
    _startDetector(thresholdFor(ShakePrefs.sensitivity.value));
    // The core assumes "app foregrounded" because WE normally start it from
    // the running app. An OS restart of the service is the opposite case —
    // the app is gone; treat it as paused so background shakes are handled.
    if (starter != TaskStarter.developer) _core?.appPaused();
  }
```

with:

```dart
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _core = ShakeGuardCore(
      hasGuardians: EmergencyAlert.hasGuardians,
      send: _sendAlert,
      onTick: (remaining) {
        _coordsPrefetch ??= EmergencyAlert.currentCoordinates();
        FlutterForegroundTask.updateService(
          notificationTitle: 'Shake detected',
          notificationText: 'Alerting your guardians in $remaining…',
          notificationButtons: const [_cancelButton],
        );
      },
      onCancelled: () {
        _coordsPrefetch = null;
        _idleNotification();
      },
      onSent: () {}, // _sendAlert wrote the result notification already
      onNoGuardians: () => FlutterForegroundTask.updateService(
        notificationTitle: 'Add guardians first',
        notificationText:
            'Open Lumi and add a guardian so an SOS can reach someone.',
        notificationButtons: const [],
      ),
    );
    _checkIn = CheckInTimerCore(
      send: () => _sendAlert(note: CheckInPrefs.note.value),
      onTick: (remaining) => FlutterForegroundTask.updateService(
        notificationTitle: 'Checking in',
        notificationText:
            'Alerting your guardians in ${_fmtDuration(remaining)} unless you check in.',
        notificationButtons: const [_cancelCheckInButton],
      ),
      onGraceTick: (secondsRemaining) => FlutterForegroundTask.updateService(
        notificationTitle: 'Check-in missed',
        notificationText: 'Alerting your guardians in ${secondsRemaining}s…',
        notificationButtons: const [_cancelCheckInButton],
      ),
      onCancelled: () async {
        await CheckInPrefs.clear();
        _idleNotification();
      },
      onSent: () {}, // _sendAlert wrote the result notification already
    );
    await ShakePrefs.load(); // this isolate has its own SharedPreferences access
    if (ShakePrefs.enabled.value) {
      _startDetector(thresholdFor(ShakePrefs.sensitivity.value));
    }
    // The core assumes "app foregrounded" because WE normally start it from
    // the running app. An OS restart of the service is the opposite case —
    // the app is gone; treat it as paused so background shakes are handled.
    if (starter != TaskStarter.developer) _core?.appPaused();

    // A running check-in timer must resume exactly where CheckInPrefs says
    // it is — including after an OS-initiated restart of this service.
    await CheckInPrefs.load();
    final end = CheckInPrefs.endTime.value;
    if (end != null) _checkIn?.start(end);
  }

  static String _fmtDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
```

Note the `if (ShakePrefs.enabled.value)` guard added around
`_startDetector(...)`: today the detector always starts unconditionally
because the service itself only ever ran when shake-to-SOS was enabled.
Task 5 changes that start condition to include "a check-in timer is
running," so a service running *only* for a check-in timer (shake toggled
off) must not silently arm shake detection anyway.

- [ ] **Step 4: Handle the new IPC messages and notification button**

Replace the existing `onReceiveData`:

```dart
  @override
  void onReceiveData(Object data) {
    if (data == 'app_resumed') _core?.appResumed();
    if (data == 'app_paused') _core?.appPaused();
    if (data is String && data.startsWith('sensitivity:')) {
      final level = ShakeSensitivity.values.byName(data.substring(12));
      _detector?.stopListening();
      _startDetector(thresholdFor(level));
    }
  }
```

with:

```dart
  @override
  void onReceiveData(Object data) {
    if (data == 'app_resumed') _core?.appResumed();
    if (data == 'app_paused') _core?.appPaused();
    if (data is String && data.startsWith('sensitivity:')) {
      final level = ShakeSensitivity.values.byName(data.substring(12));
      _detector?.stopListening();
      _startDetector(thresholdFor(level));
    }
    if (data == 'checkin_start') _startCheckIn();
    if (data == 'checkin_cancel') _checkIn?.cancel();
  }

  Future<void> _startCheckIn() async {
    await CheckInPrefs.load(); // pick up the endTime/note just persisted
    final end = CheckInPrefs.endTime.value;
    if (end != null) _checkIn?.start(end);
  }
```

Replace the existing `onNotificationButtonPressed`:

```dart
  @override
  void onNotificationButtonPressed(String id) {
    if (id == _cancelButtonId) _core?.cancel();
  }
```

with:

```dart
  @override
  void onNotificationButtonPressed(String id) {
    if (id == _cancelButtonId) _core?.cancel();
    if (id == _cancelCheckInButtonId) _checkIn?.cancel();
  }
```

- [ ] **Step 5: Extend `_sendAlert` with an optional note and dispose `_checkIn`**

Replace the existing `_sendAlert`:

```dart
  Future<void> _sendAlert() async {
    try {
      final coords = _coordsPrefetch;
      _coordsPrefetch = null;
      final result = await EmergencyAlert.sendBackground(coordsFuture: coords);
```

with:

```dart
  Future<void> _sendAlert({String? note}) async {
    try {
      final coords = _coordsPrefetch;
      _coordsPrefetch = null;
      final result = await EmergencyAlert.sendBackground(
          coordsFuture: coords, note: note);
```

(The rest of `_sendAlert`'s body — the result-notification update and the
catch block — is unchanged.)

Replace the existing `onDestroy`:

```dart
  @override
  Future<void> onDestroy(DateTime timestamp) async {
    _detector?.stopListening();
    _core?.dispose();
  }
```

with:

```dart
  @override
  Future<void> onDestroy(DateTime timestamp) async {
    _detector?.stopListening();
    _core?.dispose();
    _checkIn?.dispose();
  }
```

- [ ] **Step 6: Verify with static analysis**

Run: `flutter analyze lib/services/shake_guard_service.dart`
Expected: no new errors or warnings (pre-existing `deprecated_member_use`
infos elsewhere in the file, if any, are unrelated and unaffected).

- [ ] **Step 7: Run the full test suite**

Run: `flutter test`
Expected: all tests PASS — this task doesn't change `ShakeGuardCore`'s
behavior, only adds a second, independent state machine alongside it.

- [ ] **Step 8: Commit**

```bash
git add lib/services/shake_guard_service.dart
git commit -m "feat: wire CheckInTimerCore into ShakeGuardService"
```

---

### Task 5: `NavBarPage` — service start/stop condition and IPC calls

**Files:**
- Modify: `lib/navigation_bar/main_page.dart`

**Interfaces:**
- Consumes: `CheckInPrefs.endTime` (Task 1),
  `ShakeGuardService.notifyCheckInStart/notifyCheckInCancel` (Task 4).
- Produces: a `_syncGuardService()` method that Task 6's Track-page Start
  button calls (via `CheckInPrefs.endTime`'s listener, added here) after
  persisting a new timer — no new public method name beyond what's already
  in `ShakeGuardService`, since starting/stopping the service itself stays
  triggered by listening to `CheckInPrefs.endTime` the same way it already
  listens to `ShakePrefs.enabled`/`ShakePrefs.sensitivity`.

Glue code — verified by `flutter analyze` and on-device testing in Task 6
(there's no user-visible behavior to assert until the Track card exists),
matching Task 4.

- [ ] **Step 1: Listen to `CheckInPrefs.endTime` and replace the start/stop condition**

In `lib/navigation_bar/main_page.dart`, add the import:

```dart
import '../services/checkin_prefs.dart';
```

In `_NavBarPageState.initState`, add a listener alongside the existing two:

```dart
    ShakePrefs.enabled.addListener(_syncShakeDetector);
    ShakePrefs.sensitivity.addListener(_syncShakeDetector);
    CheckInPrefs.endTime.addListener(_syncShakeDetector);
```

(Reusing `_syncShakeDetector` as the single place that re-evaluates
"should the service be running" — despite the name, it already is the
method responsible for the service's start/stop decision, not just the
detector's.)

Remove the matching listener in `dispose` too:

```dart
    ShakePrefs.enabled.removeListener(_syncShakeDetector);
    ShakePrefs.sensitivity.removeListener(_syncShakeDetector);
```

becomes:

```dart
    ShakePrefs.enabled.removeListener(_syncShakeDetector);
    ShakePrefs.sensitivity.removeListener(_syncShakeDetector);
    CheckInPrefs.endTime.removeListener(_syncShakeDetector);
```

- [ ] **Step 2: Update `_syncShakeDetector`'s start/stop condition**

Replace the existing method:

```dart
  void _syncShakeDetector() {
    final android = !kIsWeb && Platform.isAndroid;
    if (ShakePrefs.enabled.value) {
      // ShakeDetector's fields are final, so a sensitivity change tears down
      // the old instance and builds a fresh one at the new threshold.
      _shakeDetector?.stopListening();
      _shakeDetector = ShakeDetector.autoStart(
        onPhoneShake: (_) => _onShake(),
        // Two distinct shakes required — cuts down pocket/bag false alarms.
        minimumShakeCount: 2,
        shakeThresholdGravity: thresholdFor(ShakePrefs.sensitivity.value),
      );
      if (android) {
        _startGuardIfPermitted();
        ShakeGuardService.notifySensitivity(ShakePrefs.sensitivity.value);
      }
    } else {
      _shakeDetector?.stopListening();
      _shakeDetector = null;
      if (android) ShakeGuardService.stop();
    }
  }
```

with:

```dart
  void _syncShakeDetector() {
    final android = !kIsWeb && Platform.isAndroid;
    if (ShakePrefs.enabled.value) {
      // ShakeDetector's fields are final, so a sensitivity change tears down
      // the old instance and builds a fresh one at the new threshold.
      _shakeDetector?.stopListening();
      _shakeDetector = ShakeDetector.autoStart(
        onPhoneShake: (_) => _onShake(),
        // Two distinct shakes required — cuts down pocket/bag false alarms.
        minimumShakeCount: 2,
        shakeThresholdGravity: thresholdFor(ShakePrefs.sensitivity.value),
      );
    } else {
      _shakeDetector?.stopListening();
      _shakeDetector = null;
    }
    if (!android) return;
    // The service now backs two independent features — keep it alive if
    // either wants it, stop it only when neither does.
    final checkInRunning = CheckInPrefs.endTime.value != null;
    if (ShakePrefs.enabled.value || checkInRunning) {
      _startGuardIfPermitted();
      if (ShakePrefs.enabled.value) {
        ShakeGuardService.notifySensitivity(ShakePrefs.sensitivity.value);
      }
      if (checkInRunning) ShakeGuardService.notifyCheckInStart();
    } else {
      ShakeGuardService.stop();
    }
  }
```

- [ ] **Step 3: Verify with static analysis**

Run: `flutter analyze lib/navigation_bar/main_page.dart`
Expected: no new errors or warnings.

- [ ] **Step 4: Run the full test suite**

Run: `flutter test`
Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/navigation_bar/main_page.dart
git commit -m "feat: keep the guard service alive for an active check-in timer"
```

---

### Task 6: Track-page check-in timer card

**Files:**
- Modify: `lib/pages/location_page.dart`

**Interfaces:**
- Consumes: `CheckInPrefs.endTime/note/start/clear` (Task 1),
  `EmergencyAlert.hasGuardians()` (existing), `ShakeGuardService
  .notifyCheckInCancel()` (Task 4) — cancelling from the card goes through
  the service, the same single authority the notification's cancel button
  already uses; the card itself never calls `CheckInTimerCore` directly.

No new automated test file — this is page-level UI wiring in the same
category as the sensitivity picker added to this same file, which was also
verified on-device rather than with a widget test (see this repo's
shake-sensitivity plan). Verify with `flutter analyze`, then on-device per
Step 5 below.

- [ ] **Step 1: Add imports and a small local widget-state helper**

In `lib/pages/location_page.dart`, add the imports:

```dart
import '../services/checkin_prefs.dart';
import '../services/checkin_timer_core.dart' show CheckInTimerCore;
import '../services/emergency_alert.dart';
import '../services/shake_guard_service.dart';
```

(`checkin_prefs.dart` for the card's state, `checkin_timer_core.dart` only
for its `defaultGraceSeconds` constant — the card never constructs a
`CheckInTimerCore` itself — `emergency_alert.dart` for the `hasGuardians()`
guard, `shake_guard_service.dart` for the cancel action. None of these four
were previously imported by this file, but all are existing modules used
elsewhere in the app, so this adds no new dependency.)

Add these two fields to `_LocationPageState`, alongside the existing
`location`/`_sub` fields:

```dart
  Timer? _checkInDisplayTimer; // purely a 1x/sec UI refresh, see below
```

In `initState`, start the display-refresh timer:

```dart
    _checkInDisplayTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
```

In `dispose`, cancel it:

```dart
    _checkInDisplayTimer?.cancel();
```

- [ ] **Step 2: Add the check-in card**

In the `Column`'s `children`, insert this new card immediately after the
existing shake-to-SOS `LumiCard` (after its closing `const SizedBox(height:
9),` — the one directly before `const SizedBox(height: 14),` and the
"RECENT PINGS" header) and before that spacing:

```dart
              LumiCard(
                child: ListenableBuilder(
                  listenable: CheckInPrefs.endTime,
                  builder: (_, __) => _buildCheckInCard(),
                ),
              ),
              const SizedBox(height: 9),
```

Add the builder and its three states as new methods on `_LocationPageState`:

```dart
  Widget _buildCheckInCard() {
    final end = CheckInPrefs.endTime.value;
    if (end == null) return _checkInIdle();

    final remaining = end.difference(DateTime.now());
    if (remaining > Duration.zero) return _checkInRunning(remaining);

    final graceRemaining = end
        .add(const Duration(seconds: CheckInTimerCore.defaultGraceSeconds))
        .difference(DateTime.now());
    if (graceRemaining > Duration.zero) {
      return _checkInGrace((graceRemaining.inMilliseconds / 1000).ceil());
    }
    // The service hasn't yet cleared CheckInPrefs for a run that already
    // sent — show grace-expired briefly rather than a stale running state.
    return _checkInGrace(0);
  }

  Widget _checkInIdle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _TileIcon(
                icon: Icons.timer_outlined,
                bg: LumiColors.green.withOpacity(0.14),
                fg: LumiColors.green),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Check-in timer',
                      style: LumiText.body(14.5, weight: FontWeight.w700)),
                  Text("Alert your guardians if you don't check in",
                      style: LumiText.body(12, color: LumiColors.textSub)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in [10, 20, 30, 60])
              _DurationChip(
                label: '$m min',
                onTap: () => _startCheckIn(Duration(minutes: m)),
              ),
            _DurationChip(label: 'Custom…', onTap: _showCustomDurationSheet),
          ],
        ),
      ],
    );
  }

  Future<void> _showCustomDurationSheet() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final minutes = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: LumiColors.bgTop,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 22,
          bottom: MediaQuery.of(ctx).viewInsets.bottom +
              MediaQuery.of(ctx).padding.bottom +
              28,
        ),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Custom check-in duration', style: LumiText.display(18)),
              const SizedBox(height: 14),
              LumiField(
                hint: 'Minutes',
                icon: Icons.timer_outlined,
                controller: controller,
                keyboardType: TextInputType.number,
                validator: (v) {
                  final n = int.tryParse(v?.trim() ?? '');
                  if (n == null || n <= 0) return 'Enter a whole number of minutes';
                  return null;
                },
              ),
              const SizedBox(height: 18),
              LumiPrimaryButton(
                label: 'Start',
                onPressed: () {
                  if (formKey.currentState?.validate() != true) return;
                  Navigator.pop(ctx, int.parse(controller.text.trim()));
                },
              ),
            ],
          ),
        ),
      ),
    );
    if (minutes != null) await _startCheckIn(Duration(minutes: minutes));
  }

  Widget _checkInRunning(Duration remaining) {
    final m = remaining.inMinutes;
    final s = remaining.inSeconds % 60;
    return _checkInActiveCard(
      icon: Icons.timer_outlined,
      color: LumiColors.green,
      title: 'Checking in in $m:${s.toString().padLeft(2, '0')}',
      subtitle: CheckInPrefs.note.value,
    );
  }

  Widget _checkInGrace(int secondsRemaining) {
    return _checkInActiveCard(
      icon: Icons.warning_amber_rounded,
      color: LumiColors.accent,
      title: 'Check-in missed',
      subtitle: 'Alerting your guardians in ${secondsRemaining}s',
    );
  }

  Widget _checkInActiveCard({
    required IconData icon,
    required Color color,
    required String title,
    String? subtitle,
  }) {
    return Row(
      children: [
        _TileIcon(icon: icon, bg: color.withOpacity(0.14), fg: color),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: LumiText.body(14.5, weight: FontWeight.w700)),
              if (subtitle != null)
                Text(subtitle, style: LumiText.body(12, color: LumiColors.textSub)),
            ],
          ),
        ),
        GestureDetector(
          onTap: _cancelCheckIn,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.16),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text("I'm safe",
                style: LumiText.body(13, weight: FontWeight.w700, color: color)),
          ),
        ),
      ],
    );
  }

  Future<void> _startCheckIn(Duration duration) async {
    if (!await EmergencyAlert.hasGuardians()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add emergency contacts first.')),
      );
      return;
    }
    await CheckInPrefs.start(duration);
    // Sharing is a bonus, not a precondition — a location-permission failure
    // here must not stop the timer that was already persisted above.
    try {
      if (_uid != null) await _listenLocation();
    } catch (_) {/* Live Location's own switch/snackbar covers this normally */}
    if (!kIsWeb && Platform.isAndroid) ShakeGuardService.notifyCheckInStart();
  }

  Future<void> _cancelCheckIn() async {
    if (!kIsWeb && Platform.isAndroid) {
      ShakeGuardService.notifyCheckInCancel();
    } else {
      // No background service off-Android — clear locally.
      await CheckInPrefs.clear();
    }
  }
```

Add the small chip helper widget near this file's other private widgets
(`_TileIcon`, `_Marker`):

```dart
class _DurationChip extends StatelessWidget {
  const _DurationChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: LumiColors.hairline),
        ),
        child: Text(label, style: LumiText.body(13, weight: FontWeight.w600)),
      ),
    );
  }
}
```

- [ ] **Step 3: Add the `dart:async` `Timer` import if not already present**

Check the top of `lib/pages/location_page.dart` — it already has
`import 'dart:async';` for `StreamSubscription`, so `Timer` needs no new
import.

- [ ] **Step 4: Verify with `dart format` and `flutter analyze`**

Run: `dart format lib/pages/location_page.dart`
Run: `flutter analyze lib/pages/location_page.dart`
Expected: no new errors (pre-existing `deprecated_member_use`/
`prefer_const_*` infos already in this file are unrelated).

- [ ] **Step 5: On-device verification**

Build and install a debug APK, sign in with a safe placeholder guardian
(never a real contact — see the mandatory physical-device testing
precautions), then on the Track page:

1. Tap "10 min" — card flips to the running state with a live countdown
   and an "I'm safe" button; Live Location switch (further up the same
   page) flips to "Sharing now".
2. Tap "I'm safe" — card returns to the idle chip row; confirm (via
   `adb shell dumpsys notification` or just watching the phone) no alert
   fired.
3. Start a new short timer (temporarily lower `graceSeconds`/use a very
   short custom duration for this manual pass only, then revert — do not
   ship a shortened default), background the app, wait for it to expire:
   confirm the persistent notification shows "Check-in missed" with a
   cancel action, and reopening the app shows the same grace state on the
   card.
4. Let it run all the way through: confirm exactly one SMS reaches the
   placeholder guardian and the note (if set) appears in it, and the app
   doesn't crash.
5. Repeat step 4 with the app in the *foreground* the whole time (don't
   background it) — confirms the service (not any foreground-only path)
   is what's actually driving the send, per this feature's architecture.

- [ ] **Step 6: Commit**

```bash
git add lib/pages/location_page.dart
git commit -m "feat: add check-in timer card to the Track page"
```
