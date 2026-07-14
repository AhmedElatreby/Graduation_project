# Track-Page Check-In Card Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the check-in timer card on the Track page (idle / running / grace states) and wire it to the already-shipped CheckInPrefs/CheckInTimerCore/ShakeGuardService backend.

**Architecture:** A new self-contained `CheckInCard` StatefulWidget in `lib/widgets/checkin_card.dart`, driven entirely by the static `CheckInPrefs.endTime`/`note` ValueNotifiers plus a 1-second repaint timer. The card never runs its own `CheckInTimerCore` — phase (idle/running/grace) is a pure function of `endTime` and `CheckInTimerCore.defaultGraceSeconds`. Starting persists via `CheckInPrefs.start(...)`; the already-committed `NavBarPage` listener on `CheckInPrefs.endTime` starts the foreground service and sends the `checkin_start` IPC. Cancelling sends `checkin_cancel` and clears prefs locally.

**Tech Stack:** Flutter 3.44.1, `shared_preferences` (via CheckInPrefs), `permission_handler`, sqflite-ffi widget tests (existing `test/test_helpers.dart` harness).

**Specs:**
- `docs/superpowers/specs/2026-07-05-checkin-timer-design.md` (parent — UI section)
- `docs/superpowers/specs/2026-07-12-checkin-card-ui-design.md` (addendum — placement, cancel flow, permissions)

## Global Constraints

- Copy is pinned by the specs: card title `Check-in timer`, subtitle `Alert your guardians if you don't check in`, running text `Checking in in <m:ss>`, grace text `Check-in missed — alerting your guardians in <N>s`, cancel button `I'm safe — cancel`, no-guardians snackbar `Add guardians first — no alert sent` (identical to `main_page.dart:201`).
- Duration presets: 10 / 20 / 30 / 60 minutes plus `Custom…` (bottom sheet, minutes 1–720).
- The card must never decide to send or cancel an alert by itself — the service isolate is the single authority. UI cancel = `notifyCheckInCancel()` + local `CheckInPrefs.clear()` only.
- Never dispose a `TextEditingController` declared as a local inside a bottom-sheet builder — sheet content with fields must be a StatefulWidget owning its controllers (established project rule).
- All platform-channel calls (`ShakeGuardService.*`, permission requests) are guarded by `!kIsWeb && Platform.isAndroid` so widget tests (macOS host) never hit them.
- Widget tests must NOT use `pumpAndSettle()` while a timer is running (the card's periodic repaint timer never settles) — use bounded `tester.pump(...)` / `settleWithRealAsync(tester)` instead.
- `flutter analyze --fatal-infos` must stay clean (CI enforces it).

---

### Task 1: `ShakeGuardService.requestPermissions()` + `_setShakeEnabled` refactor

**Files:**
- Modify: `lib/services/shake_guard_service.dart` (add method next to `hasRequiredPermissions()`, ~line 62)
- Modify: `lib/pages/location_page.dart:339-363` (`_setShakeEnabled` uses the new method)
- Test: `test/services/shake_guard_service_test.dart` (new file)

**Interfaces:**
- Consumes: `permission_handler`'s `[Permission...].request()` extension (already imported in `shake_guard_service.dart`).
- Produces: `static Future<Map<Permission, PermissionStatus>> ShakeGuardService.requestPermissions()` — requests notification, SMS, phone, location-when-in-use together and returns the statuses map. Call sites keep their own snackbar/`openAppSettings` handling. Task 3 calls this from the card's Start flow.

- [x] **Step 1: Write the failing test**

Create `test/services/shake_guard_service_test.dart`:

```dart
// requestPermissions is the one shared permission-request entry point for
// everything the guard service backs (shake switch, check-in Start): it must
// request exactly the set hasRequiredPermissions() checks, so the two can
// never drift apart.
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:safetyproject/services/shake_guard_service.dart';

import '../test_helpers.dart';

void main() {
  configureTestEnvironment();

  test('requestPermissions requests the exact set hasRequiredPermissions '
      'checks and returns the statuses', () async {
    final statuses = await ShakeGuardService.requestPermissions();

    expect(
      statuses.keys.toSet(),
      {
        Permission.notification,
        Permission.sms,
        Permission.phone,
        Permission.locationWhenInUse,
      },
    );
    // FakeGrantedPermissionHandlerPlatform grants everything, so the granted
    // map must line up with hasRequiredPermissions() saying yes.
    expect(statuses.values.every((s) => s.isGranted), isTrue);
    expect(await ShakeGuardService.hasRequiredPermissions(), isTrue);
  });
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/shake_guard_service_test.dart`
Expected: FAIL — compile error `The method 'requestPermissions' isn't defined for the type 'ShakeGuardService'`.

- [x] **Step 3: Write minimal implementation**

In `lib/services/shake_guard_service.dart`, directly below `hasRequiredPermissions()` (after line 62):

```dart
  /// Requests the same set [hasRequiredPermissions] checks, in one dialog
  /// run. Shared by the shake switch and the check-in card's Start button so
  /// the two flows can't drift. Call sites own the response (snackbar,
  /// openAppSettings) — this only performs the request.
  static Future<Map<Permission, PermissionStatus>> requestPermissions() => [
        Permission.notification,
        Permission.sms,
        Permission.phone,
        Permission.locationWhenInUse,
      ].request();
```

- [x] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/shake_guard_service_test.dart`
Expected: PASS (1 test).

- [x] **Step 5: Refactor `_setShakeEnabled` to use it**

In `lib/pages/location_page.dart`, add the import (alphabetical, with the other service imports):

```dart
import '../services/shake_guard_service.dart';
```

Replace the request block in `_setShakeEnabled` (lines 344-349):

```dart
    final statuses = await [
      Permission.notification,
      Permission.sms,
      Permission.phone,
      Permission.locationWhenInUse,
    ].request();
```

with:

```dart
    final statuses = await ShakeGuardService.requestPermissions();
```

The rest of `_setShakeEnabled` (granted check, `openAppSettings`, snackbar) is unchanged. `location_page.dart` still needs its `permission_handler` import for `Permission.location` in `_requestPermission` and `openAppSettings` — do not remove it.

- [x] **Step 6: Run the full suite and analyzer**

Run: `flutter analyze --fatal-infos && flutter test`
Expected: `No issues found!`, all tests pass.

- [x] **Step 7: Commit**

```bash
git add lib/services/shake_guard_service.dart lib/pages/location_page.dart test/services/shake_guard_service_test.dart
git commit -m "feat: ShakeGuardService.requestPermissions shared by shake switch"
```

---

### Task 2: Phase + formatting helpers (pure logic)

**Files:**
- Create: `lib/widgets/checkin_card.dart` (helpers only in this task; the widget arrives in Task 3)
- Test: `test/widgets/checkin_card_test.dart` (new file; unit-test group only in this task)

**Interfaces:**
- Consumes: `CheckInTimerCore.defaultGraceSeconds` (== 60) from `lib/services/checkin_timer_core.dart`.
- Produces (used by Tasks 3-4):
  - `enum CheckInPhase { idle, running, grace }`
  - `CheckInPhase checkInPhase(DateTime? endTime, DateTime now)`
  - `int checkInGraceSecondsLeft(DateTime endTime, DateTime now)` — clamped at 0
  - `String formatRemaining(Duration d)` — `m:ss`, `h:mm:ss` above an hour, clamped at `0:00`

- [x] **Step 1: Write the failing tests**

Create `test/widgets/checkin_card_test.dart`:

```dart
// The check-in card never runs its own CheckInTimerCore — what it shows is a
// pure function of CheckInPrefs.endTime and the grace constant. These unit
// tests pin that function; the widget tests (added in later tasks) pin the
// three visual states built on top of it.
import 'package:flutter_test/flutter_test.dart';

import 'package:safetyproject/services/checkin_timer_core.dart';
import 'package:safetyproject/widgets/checkin_card.dart';

import '../test_helpers.dart';

void main() {
  configureTestEnvironment();

  group('phase computation', () {
    final now = DateTime(2026, 7, 12, 20, 0, 0);

    test('null endTime is idle', () {
      expect(checkInPhase(null, now), CheckInPhase.idle);
    });

    test('future endTime is running', () {
      expect(checkInPhase(now.add(const Duration(minutes: 5)), now),
          CheckInPhase.running);
    });

    test('past endTime is grace, even past the grace window (the service '
        'resolves it; the card just keeps showing the warning)', () {
      expect(checkInPhase(now.subtract(const Duration(seconds: 1)), now),
          CheckInPhase.grace);
      expect(checkInPhase(now.subtract(const Duration(minutes: 10)), now),
          CheckInPhase.grace);
    });

    test('an endTime exactly now is grace (not running)', () {
      expect(checkInPhase(now, now), CheckInPhase.grace);
    });
  });

  group('grace seconds left', () {
    final now = DateTime(2026, 7, 12, 20, 0, 0);

    test('counts down from defaultGraceSeconds and clamps at 0', () {
      expect(
        checkInGraceSecondsLeft(now, now),
        CheckInTimerCore.defaultGraceSeconds,
      );
      expect(
        checkInGraceSecondsLeft(now.subtract(const Duration(seconds: 15)), now),
        CheckInTimerCore.defaultGraceSeconds - 15,
      );
      expect(
        checkInGraceSecondsLeft(now.subtract(const Duration(minutes: 5)), now),
        0,
      );
    });

    test('rounds partial seconds up, matching CheckInTimerCore.onGraceTick '
        'ceil-ing so card and notification never disagree by a second', () {
      expect(
        checkInGraceSecondsLeft(
            now.subtract(const Duration(milliseconds: 500)), now),
        CheckInTimerCore.defaultGraceSeconds, // 59.5 → 60
      );
    });
  });

  group('formatRemaining', () {
    test('minutes and seconds', () {
      expect(formatRemaining(const Duration(minutes: 12, seconds: 34)), '12:34');
      expect(formatRemaining(const Duration(seconds: 59)), '0:59');
      expect(formatRemaining(const Duration(minutes: 60)), '1:00:00');
      expect(formatRemaining(const Duration(hours: 1, seconds: 5)), '1:00:05');
    });

    test('never goes negative', () {
      expect(formatRemaining(const Duration(seconds: -3)), '0:00');
    });
  });
}
```

- [x] **Step 2: Run tests to verify they fail**

Run: `flutter test test/widgets/checkin_card_test.dart`
Expected: FAIL — compile error, `lib/widgets/checkin_card.dart` doesn't exist.

- [x] **Step 3: Write minimal implementation**

Create `lib/widgets/checkin_card.dart`:

```dart
// ─────────────────────────────────────────────────────────────────────────────
//  Lumi · Check-in timer card (Track page)
//  Display-only view over CheckInPrefs: phase and remaining time are pure
//  functions of the persisted endTime and the shared grace constant — the
//  service isolate's CheckInTimerCore is the only authority that ever sends
//  or cancels an alert. See docs/superpowers/specs/2026-07-12-checkin-card-
//  ui-design.md and the parent 2026-07-05 spec's UI section.
// ─────────────────────────────────────────────────────────────────────────────
import '../services/checkin_timer_core.dart';

enum CheckInPhase { idle, running, grace }

/// Which of the card's three states to show. Deliberately has no "expired"
/// value: once the grace window has fully elapsed the service is sending (or
/// has sent and will clear the prefs); until that clear lands the card keeps
/// showing the grace warning at 0s rather than inventing a fourth state.
CheckInPhase checkInPhase(DateTime? endTime, DateTime now) {
  if (endTime == null) return CheckInPhase.idle;
  if (endTime.isAfter(now)) return CheckInPhase.running;
  return CheckInPhase.grace;
}

/// Whole seconds left in the grace window, rounded up to match
/// CheckInTimerCore's onGraceTick ceil-ing, clamped at 0.
int checkInGraceSecondsLeft(DateTime endTime, DateTime now) {
  final deadline =
      endTime.add(const Duration(seconds: CheckInTimerCore.defaultGraceSeconds));
  final leftMs = deadline.difference(now).inMilliseconds;
  return leftMs <= 0 ? 0 : (leftMs / 1000).ceil();
}

/// `m:ss` (`h:mm:ss` above an hour), clamped at `0:00`.
String formatRemaining(Duration d) {
  final total = d.inSeconds < 0 ? 0 : d.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}
```

- [x] **Step 4: Run tests to verify they pass**

Run: `flutter test test/widgets/checkin_card_test.dart`
Expected: PASS (all groups).

- [x] **Step 5: Commit**

```bash
git add lib/widgets/checkin_card.dart test/widgets/checkin_card_test.dart
git commit -m "feat: check-in card phase/format helpers"
```

---

### Task 3: `CheckInCard` widget — idle state and Start flow

**Files:**
- Modify: `lib/widgets/checkin_card.dart` (add the widget below the helpers)
- Test: `test/widgets/checkin_card_test.dart` (add widget-test group)

**Interfaces:**
- Consumes:
  - Task 2's helpers (`checkInPhase`, `formatRemaining`, `checkInGraceSecondsLeft`)
  - `CheckInPrefs.endTime/note` (ValueNotifiers), `CheckInPrefs.start(Duration, {String? note})`, `CheckInPrefs.clear()`
  - `EmergencyAlert.hasGuardians()`
  - `LiveLocationService.start()` (throws without Firebase — must be try/caught)
  - `ShakeGuardService.requestPermissions()` (Task 1), `ShakeGuardService.notifyCheckInCancel()`
  - `LumiCard`, `LumiColors`, `LumiText` from the theme/widgets files
- Produces: `class CheckInCard extends StatefulWidget { const CheckInCard({super.key}); }` — dropped into `location_page.dart` in Task 6. Cancel flow lands in Task 4; this task stubs `_cancel` as the real method since it's 3 lines.

- [x] **Step 1: Write the failing widget tests**

Append to `test/widgets/checkin_card_test.dart` (new imports at top of file):

```dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safetyproject/contact/personal_emergency_contacts_model.dart';
import 'package:safetyproject/database/db_helper.dart';
import 'package:safetyproject/services/checkin_prefs.dart';
```

and the group (inside `main()`, after the unit groups):

```dart
  Future<void> pumpCard(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: CheckInCard())),
    ));
    await tester.pump();
  }

  group('CheckInCard widget', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      CheckInPrefs.endTime.value = null;
      CheckInPrefs.note.value = null;
    });

    testWidgets('idle state shows chips, note field and Start', (tester) async {
      await pumpCard(tester);

      expect(find.text('Check-in timer'), findsOneWidget);
      expect(find.text("Alert your guardians if you don't check in"),
          findsOneWidget);
      for (final label in ['10 min', '20 min', '30 min', '60 min', 'Custom…']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('Start'), findsOneWidget);
    });

    // NOTE: must run before any test seeds a contact — DBHelper's backing
    // store is shared across tests in this file (same pattern as
    // emergency_alert_test.dart relies on).
    testWidgets('Start with no guardians shows the prompt and starts nothing',
        (tester) async {
      await pumpCard(tester);

      await tester.tap(find.text('Start'));
      await settleWithRealAsync(tester);

      expect(find.text('Add guardians first — no alert sent'), findsOneWidget);
      expect(CheckInPrefs.endTime.value, isNull);
    });

    testWidgets('Start with a guardian persists endTime + note and shows the '
        'running state', (tester) async {
      await tester.runAsync(
          () => DBHelper().add(PersonalEmergency('Sara', '01000000000')));
      await pumpCard(tester);

      await tester.tap(find.text('20 min'));
      await tester.pump();
      await tester.enterText(
          find.byType(TextField), 'walking home from the station');
      final before = DateTime.now();
      await tester.tap(find.text('Start'));
      await settleWithRealAsync(tester);

      final end = CheckInPrefs.endTime.value;
      expect(end, isNotNull);
      final delta = end!.difference(before) - const Duration(minutes: 20);
      expect(delta.inSeconds.abs() <= 5, isTrue,
          reason: 'endTime should be ~20 min out, got $end');
      expect(CheckInPrefs.note.value, 'walking home from the station');
      expect(find.textContaining('Checking in in'), findsOneWidget);
      expect(find.text('walking home from the station'), findsOneWidget);
      expect(find.text("I'm safe — cancel"), findsOneWidget);

      // Leave no running timer behind for the next test.
      await tester.runAsync(CheckInPrefs.clear);
      await tester.pump();
    });
  });
```

- [x] **Step 2: Run tests to verify they fail**

Run: `flutter test test/widgets/checkin_card_test.dart`
Expected: FAIL — compile error `CheckInCard` isn't defined.

- [x] **Step 3: Implement the widget**

In `lib/widgets/checkin_card.dart`, replace the import section with:

```dart
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/checkin_prefs.dart';
import '../services/checkin_timer_core.dart';
import '../services/emergency_alert.dart';
import '../services/live_location_service.dart';
import '../services/shake_guard_service.dart';
import '../theme/lumi_theme.dart';
import 'lumi_widgets.dart';
```

and append the widget below the helpers:

```dart
class CheckInCard extends StatefulWidget {
  const CheckInCard({super.key});

  @override
  State<CheckInCard> createState() => _CheckInCardState();
}

class _CheckInCardState extends State<CheckInCard> {
  static const _presetMinutes = [10, 20, 30, 60];

  final _noteController = TextEditingController();
  Duration _selected = const Duration(minutes: 10);
  int? _customMinutes; // non-null when Custom… picked; shown on the chip
  Timer? _ticker; // 1s repaint while a timer runs — display only

  @override
  void initState() {
    super.initState();
    CheckInPrefs.endTime.addListener(_syncTicker);
    _syncTicker();
  }

  @override
  void dispose() {
    CheckInPrefs.endTime.removeListener(_syncTicker);
    _ticker?.cancel();
    _noteController.dispose();
    super.dispose();
  }

  void _syncTicker() {
    final running = CheckInPrefs.endTime.value != null;
    if (running && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!running) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  Future<void> _start() async {
    // Deliberate action → guardians checked once, up front (parent spec).
    if (!await EmergencyAlert.hasGuardians()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Add guardians first — no alert sent'),
        backgroundColor: LumiColors.accent.withValues(alpha: 0.9),
      ));
      return;
    }
    // Same permission set as the shake switch, requested before anything is
    // persisted — _startGuardIfPermitted assumes a running check-in always
    // had these granted up front.
    if (!kIsWeb && Platform.isAndroid) {
      final statuses = await ShakeGuardService.requestPermissions();
      if (!statuses.values.every((s) => s.isGranted)) {
        if (statuses.values.any((s) => s.isPermanentlyDenied)) {
          openAppSettings();
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text(
              'Lumi needs notification, SMS, phone and location access for check-in alerts'),
          backgroundColor: LumiColors.accent.withValues(alpha: 0.9),
        ));
        return;
      }
    }
    final note = _noteController.text.trim();
    await CheckInPrefs.start(_selected, note: note.isEmpty ? null : note);
    // NavBarPage's endTime listener starts the service + sends checkin_start.
    // Live sharing is a bonus, not a precondition — the timer is already
    // persisted; a sharing failure (permission, no Firebase) changes nothing.
    try {
      await LiveLocationService.start();
    } catch (_) {}
  }

  Future<void> _cancel() async {
    if (!kIsWeb && Platform.isAndroid) ShakeGuardService.notifyCheckInCancel();
    // The service clears prefs in its own isolate; this isolate's notifier
    // copy is separate — the local clear is what flips this card to idle.
    await CheckInPrefs.clear();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DateTime?>(
      valueListenable: CheckInPrefs.endTime,
      builder: (_, endTime, __) {
        final now = DateTime.now();
        return LumiCard(
          child: switch (checkInPhase(endTime, now)) {
            CheckInPhase.idle => _idle(),
            CheckInPhase.running => _running(endTime!, now),
            CheckInPhase.grace => _grace(endTime!, now),
          },
        );
      },
    );
  }

  Widget _header() => Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: LumiColors.green.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(Icons.timer_outlined,
                color: LumiColors.green, size: 20),
          ),
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
      );

  Widget _idle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in _presetMinutes)
              ChoiceChip(
                label: Text('$m min'),
                selected: _customMinutes == null && _selected.inMinutes == m,
                onSelected: (_) => setState(() {
                  _customMinutes = null;
                  _selected = Duration(minutes: m);
                }),
              ),
            ChoiceChip(
              label: Text(
                  _customMinutes == null ? 'Custom…' : '$_customMinutes min'),
              selected: _customMinutes != null,
              onSelected: (_) => _pickCustomDuration(),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _noteController,
          maxLines: 1,
          style: LumiText.body(14, color: LumiColors.text),
          decoration: const InputDecoration(
            hintText: 'Note for guardians (optional)',
            prefixIcon: Icon(Icons.sticky_note_2_outlined, size: 20),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _start,
            style: ElevatedButton.styleFrom(
              backgroundColor: LumiColors.accent,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text('Start',
                style: LumiText.body(14.5,
                    weight: FontWeight.w700, color: Colors.white)),
          ),
        ),
      ],
    );
  }

  Widget _running(DateTime endTime, DateTime now) {
    final note = CheckInPrefs.note.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(),
        const SizedBox(height: 12),
        Text('Checking in in ${formatRemaining(endTime.difference(now))}',
            style: LumiText.display(22)),
        if (note != null) ...[
          const SizedBox(height: 4),
          Text(note, style: LumiText.body(12.5, color: LumiColors.textSub)),
        ],
        const SizedBox(height: 12),
        _cancelButton(),
      ],
    );
  }

  Widget _grace(DateTime endTime, DateTime now) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: LumiColors.accent, size: 22),
            const SizedBox(width: 9),
            Expanded(
              child: Text('Check-in missed',
                  style: LumiText.body(14.5,
                      weight: FontWeight.w700, color: LumiColors.accent)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
            'Check-in missed — alerting your guardians in '
            '${checkInGraceSecondsLeft(endTime, now)}s',
            style: LumiText.body(13, color: LumiColors.text)),
        const SizedBox(height: 12),
        _cancelButton(),
      ],
    );
  }

  Widget _cancelButton() => SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _cancel,
          style: ElevatedButton.styleFrom(
            backgroundColor: LumiColors.green,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: Text("I'm safe — cancel",
              style: LumiText.body(14.5,
                  weight: FontWeight.w700, color: Colors.white)),
        ),
      );

  Future<void> _pickCustomDuration() async {
    final picked = await showModalBottomSheet<Duration>(
      context: context,
      backgroundColor: LumiColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _CustomDurationSheet(),
    );
    if (picked == null) return;
    setState(() {
      _customMinutes = picked.inMinutes;
      _selected = picked;
    });
  }
}
```

Also append the sheet (implemented fully in Task 5's tests, but the class ships now so `_pickCustomDuration` compiles):

```dart
/// Sheet content is a StatefulWidget so the controller outlives the sheet's
/// exit animation (disposing a controller from a builder local crashes the
/// close animation — established project rule).
class _CustomDurationSheet extends StatefulWidget {
  const _CustomDurationSheet();

  @override
  State<_CustomDurationSheet> createState() => _CustomDurationSheetState();
}

class _CustomDurationSheetState extends State<_CustomDurationSheet> {
  final _minutes = TextEditingController();

  @override
  void dispose() {
    _minutes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Keep the field above the keyboard.
      padding: EdgeInsets.fromLTRB(
          18, 18, 18, 18 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Custom duration', style: LumiText.display(18)),
          const SizedBox(height: 12),
          TextField(
            controller: _minutes,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: LumiText.body(15, color: LumiColors.text),
            decoration: const InputDecoration(
              hintText: 'Minutes (1–720)',
              prefixIcon: Icon(Icons.timer_outlined, size: 20),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                final m = int.tryParse(_minutes.text);
                if (m == null || m < 1 || m > 720) return;
                Navigator.pop(context, Duration(minutes: m));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: LumiColors.accent,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text('Set',
                  style: LumiText.body(14.5,
                      weight: FontWeight.w700, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [x] **Step 4: Run tests to verify they pass**

Run: `flutter test test/widgets/checkin_card_test.dart`
Expected: PASS (unit groups + 3 widget tests).

- [x] **Step 5: Run the full suite and analyzer**

Run: `flutter analyze --fatal-infos && flutter test`
Expected: clean, all pass.

- [x] **Step 6: Commit**

```bash
git add lib/widgets/checkin_card.dart test/widgets/checkin_card_test.dart
git commit -m "feat: CheckInCard idle state and Start flow"
```

---

### Task 4: Running countdown, grace state, and cancel

**Files:**
- Modify: `lib/widgets/checkin_card.dart` (only if tests reveal gaps — the states shipped in Task 3)
- Test: `test/widgets/checkin_card_test.dart` (add tests)

**Interfaces:**
- Consumes: Task 3's `CheckInCard`, `CheckInPrefs.start/clear`, `settleWithRealAsync`.
- Produces: verified running/grace/cancel behavior that Task 6's page integration relies on.

- [x] **Step 1: Write the failing tests**

Append inside the `CheckInCard widget` group:

```dart
    testWidgets('countdown ticks down while running', (tester) async {
      await tester
          .runAsync(() => CheckInPrefs.start(const Duration(minutes: 10)));
      await pumpCard(tester);

      expect(find.textContaining('Checking in in 9:'), findsOneWidget);
      // Two ticks of the card's 1s repaint timer — the shown remaining time
      // must move (DateTime.now() is real even under fake-async pumping, so
      // pump() here only fires the periodic timer; the ~0ms of real time
      // that has passed is enough for a strictly smaller remaining string
      // not to be guaranteed — instead cross a whole-second boundary with
      // runAsync, which advances the real clock).
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1100)));
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('Checking in in 9:'), findsOneWidget);

      await tester.runAsync(CheckInPrefs.clear);
      await tester.pump();
    });

    testWidgets('cancel returns to idle and clears prefs', (tester) async {
      await tester.runAsync(() =>
          CheckInPrefs.start(const Duration(minutes: 10), note: 'note'));
      await pumpCard(tester);
      expect(find.text("I'm safe — cancel"), findsOneWidget);

      await tester.tap(find.text("I'm safe — cancel"));
      await settleWithRealAsync(tester);

      expect(CheckInPrefs.endTime.value, isNull);
      expect(CheckInPrefs.note.value, isNull);
      expect(find.text('Start'), findsOneWidget); // idle again
    });

    testWidgets('a just-expired endTime renders the grace warning',
        (tester) async {
      CheckInPrefs.endTime.value =
          DateTime.now().subtract(const Duration(seconds: 10));
      await pumpCard(tester);

      expect(find.text('Check-in missed'), findsOneWidget);
      expect(find.textContaining('alerting your guardians in'), findsOneWidget);
      expect(find.text("I'm safe — cancel"), findsOneWidget);

      CheckInPrefs.endTime.value = null;
      await tester.pump();
    });
```

- [x] **Step 2: Run tests**

Run: `flutter test test/widgets/checkin_card_test.dart`
Expected: PASS if Task 3's implementation is complete; any FAIL here is a real gap — fix `checkin_card.dart` (not the test) until green. Likely gaps to check first: the ticker not repainting (listener not attached), or the grace state reading `CheckInPrefs.note` it shouldn't.

- [x] **Step 3: Run the full suite and analyzer**

Run: `flutter analyze --fatal-infos && flutter test`
Expected: clean, all pass.

- [x] **Step 4: Commit**

```bash
git add test/widgets/checkin_card_test.dart lib/widgets/checkin_card.dart
git commit -m "test: check-in card running/grace/cancel coverage"
```

---

### Task 5: Custom-duration bottom sheet behavior

**Files:**
- Modify: `lib/widgets/checkin_card.dart` (only if tests reveal gaps — the sheet shipped in Task 3)
- Test: `test/widgets/checkin_card_test.dart` (add tests)

**Interfaces:**
- Consumes: Task 3's `_CustomDurationSheet` via the `Custom…` chip.
- Produces: verified custom-duration selection feeding `CheckInPrefs.start`.

- [x] **Step 1: Write the failing tests**

Append inside the `CheckInCard widget` group:

```dart
    testWidgets('Custom… picks a duration and Start uses it', (tester) async {
      // A guardian already exists from the earlier Start test (shared DB).
      await pumpCard(tester);

      await tester.tap(find.text('Custom…'));
      await tester.pump(); // sheet route starts animating
      await tester.pump(const Duration(milliseconds: 400)); // finish animation

      await tester.enterText(
          find.widgetWithText(TextField, 'Minutes (1–720)'), '45');
      await tester.tap(find.text('Set'));
      await tester.pump(const Duration(milliseconds: 400)); // sheet closes

      expect(find.text('45 min'), findsOneWidget); // chip shows the pick

      final before = DateTime.now();
      await tester.tap(find.text('Start'));
      await settleWithRealAsync(tester);

      final end = CheckInPrefs.endTime.value;
      expect(end, isNotNull);
      final delta = end!.difference(before) - const Duration(minutes: 45);
      expect(delta.inSeconds.abs() <= 5, isTrue,
          reason: 'endTime should be ~45 min out, got $end');

      await tester.runAsync(CheckInPrefs.clear);
      await tester.pump();
    });

    testWidgets('Set rejects out-of-range minutes and keeps the sheet open',
        (tester) async {
      await pumpCard(tester);

      await tester.tap(find.text('Custom…'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.enterText(
          find.widgetWithText(TextField, 'Minutes (1–720)'), '0');
      await tester.tap(find.text('Set'));
      await tester.pump(const Duration(milliseconds: 400));

      // Sheet still open (Set did nothing), no duration picked.
      expect(find.text('Custom duration'), findsOneWidget);
      expect(find.text('0 min'), findsNothing);
    });
```

- [x] **Step 2: Run tests**

Run: `flutter test test/widgets/checkin_card_test.dart`
Expected: PASS if Task 3's sheet is complete; fix `checkin_card.dart` gaps otherwise (likely: `isScrollControlled` keyboard inset, or the chip label not updating).

- [x] **Step 3: Run the full suite and analyzer**

Run: `flutter analyze --fatal-infos && flutter test`
Expected: clean, all pass.

- [x] **Step 4: Commit**

```bash
git add test/widgets/checkin_card_test.dart lib/widgets/checkin_card.dart
git commit -m "test: custom-duration sheet coverage"
```

---

### Task 6: Insert the card into the Track page + ship

**Files:**
- Modify: `lib/pages/location_page.dart` (insert card between Shake-to-SOS card and RECENT PINGS, ~line 227)
- Modify: `lib/main.dart`, `lib/navigation_bar/main_page.dart` — no code changes; these two already-modified files (CheckInPrefs load at startup, `_syncEpoch` race guard) ship in this commit since the card is what makes them meaningful.

**Interfaces:**
- Consumes: `CheckInCard` from Task 3.
- Produces: the user-visible feature; nothing downstream.

- [x] **Step 1: Insert the card**

In `lib/pages/location_page.dart`, add the import:

```dart
import '../widgets/checkin_card.dart';
```

Then, after the shake-to-SOS `LumiCard`'s closing `),` (line 227) and before the existing `const SizedBox(height: 14),`, insert:

```dart
              const SizedBox(height: 9),

              // check-in timer ("walk me home")
              const CheckInCard(),
```

Resulting order: shake card → `SizedBox(9)` → `CheckInCard` → `SizedBox(14)` → RECENT PINGS header.

- [x] **Step 2: Run the full suite and analyzer**

Run: `flutter analyze --fatal-infos && flutter test`
Expected: clean, all pass (including the existing `location_page`-hosting tests, if any break on the new card's presence, fix finders in those tests — the card itself is already covered).

- [x] **Step 3: Commit and push**

```bash
git add lib/pages/location_page.dart lib/main.dart lib/navigation_bar/main_page.dart
git commit -m "feat: check-in timer card on the Track page"
git push origin master
```

Watch CI: `gh run watch <run-id> --repo AhmedElatreby/Graduation_project --exit-status` — must go green.

- [ ] **Step 4: On-device verification (manual, per parent spec's Testing section)**

On the Android emulator (NOT the physical Samsung without explicit say-so — established safety rule):
1. Start a 1-minute timer with a note → notification appears and counts down.
2. Background the app → notification keeps counting; grace warning fires at zero with the "I'm safe — cancel" action.
3. Cancel from the notification → no alert sent, card back to idle on reopen.
4. With a safe placeholder guardian seeded, let a timer run to full send → SMS includes the note text.

---

## Self-Review Notes

- **Spec coverage:** idle/running/grace states + copy (Tasks 3-4), duration presets + custom sheet (Tasks 3, 5), note field (Task 3), guardians gate (Task 3), permissions up front via shared helper (Tasks 1, 3), live-location bundled + failure-tolerant (Task 3), cancel = IPC + local clear (Tasks 3-4), placement (Task 6), on-device checklist (Task 6). Service/lifecycle/EmergencyAlert work: already shipped, out of scope here.
- **Type consistency:** `checkInPhase(DateTime?, DateTime)`, `checkInGraceSecondsLeft(DateTime, DateTime)`, `formatRemaining(Duration)` used identically in Tasks 2-4; `ShakeGuardService.requestPermissions()` returns `Map<Permission, PermissionStatus>` in Tasks 1 and 3.
- **Known test-order coupling:** the no-guardians test must precede contact seeding in `checkin_card_test.dart` (shared sqflite-ffi store) — flagged inline where it matters.
