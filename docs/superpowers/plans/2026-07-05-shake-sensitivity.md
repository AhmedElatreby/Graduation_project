# Shake Sensitivity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Low/Medium/High sensitivity picker for shake-to-SOS that tunes how hard a shake must be, applied live to both the foreground detector (all platforms) and the Android background service.

**Architecture:** A pure `thresholdFor(ShakeSensitivity)` mapping and a persisted `ShakePrefs.sensitivity` notifier are the single source of truth. The foreground detector (`NavBarPage`) already rebuilds itself from a `ValueNotifier` listener for the on/off toggle — sensitivity reuses that exact rebuild path. The background service picks up a live change over its existing `sendDataToTask` IPC channel, mirroring how `app_resumed`/`app_paused` already work. `ShakeGuardCore` (the countdown/dispatch state machine) is untouched — sensitivity only affects whether `ShakeDetector` calls back, never what happens after.

**Tech Stack:** Flutter 3.44 / Dart, `shake` package (`ShakeDetector.autoStart(shakeThresholdGravity:, minimumShakeCount:)`), `shared_preferences`, `flutter_foreground_task` (`sendDataToTask`/`onReceiveData`), Material 3 `SegmentedButton`.

**Spec:** `docs/superpowers/specs/2026-07-05-shake-sensitivity-design.md`

## Global Constraints

- Three presets only, force-threshold-only: Low = `3.5`g, Medium = `2.7`g (the `shake` package's own default — existing installs must see zero behavior change), High = `2.0`g.
- `minimumShakeCount` stays fixed at `2` everywhere — never exposed as a control.
- Persisted key: `shake_sensitivity`, values `'low' | 'medium' | 'high'`; missing or unrecognized stored value falls back to `medium`, never throws.
- IPC message format to the running service: the string `'sensitivity:${level.name}'` (i.e. `'sensitivity:low'`, `'sensitivity:medium'`, `'sensitivity:high'`) over the existing `sendDataToTask` channel.
- Android-only service calls stay guarded by `!kIsWeb && Platform.isAndroid`, exactly like every existing `ShakeGuardService` call site.
- Never add a Co-Authored-By trailer to commits.

---

### Task 1: `ShakeSensitivity` enum, threshold mapping, and persistence

**Files:**
- Modify: `lib/services/shake_prefs.dart`
- Test: `test/services/shake_prefs_test.dart`

**Interfaces:**
- Consumes: nothing new (extends the existing `ShakePrefs` class).
- Produces (Tasks 2–3 rely on these exact names):
  - `enum ShakeSensitivity { low, medium, high }`
  - `double thresholdFor(ShakeSensitivity level)` — top-level function in `lib/services/shake_prefs.dart`
  - `ShakePrefs.sensitivity` — `ValueNotifier<ShakeSensitivity>`, default `ShakeSensitivity.medium`
  - `ShakePrefs.setSensitivity(ShakeSensitivity level)` — `Future<void>`, persists and updates the notifier
  - `ShakePrefs.load()` — unchanged signature, now also loads `sensitivity`

- [ ] **Step 1: Write the failing tests**

Append to `test/services/shake_prefs_test.dart` (inside `main()`, after the existing three tests, before the closing `}`):

```dart
  test('thresholdFor returns the three documented gravity values', () {
    expect(thresholdFor(ShakeSensitivity.low), 3.5);
    expect(thresholdFor(ShakeSensitivity.medium), 2.7);
    expect(thresholdFor(ShakeSensitivity.high), 2.0);
  });

  test('sensitivity defaults to medium when nothing is stored', () async {
    SharedPreferences.setMockInitialValues({});
    await ShakePrefs.load();
    expect(ShakePrefs.sensitivity.value, ShakeSensitivity.medium);
  });

  test('setSensitivity persists and survives a reload', () async {
    SharedPreferences.setMockInitialValues({});
    await ShakePrefs.load();

    await ShakePrefs.setSensitivity(ShakeSensitivity.high);
    expect(ShakePrefs.sensitivity.value, ShakeSensitivity.high);

    // Simulate a fresh app start reading the same store.
    ShakePrefs.sensitivity.value = ShakeSensitivity.medium; // scribble over memory
    await ShakePrefs.load();
    expect(ShakePrefs.sensitivity.value, ShakeSensitivity.high);
  });

  test('an unrecognized stored sensitivity string falls back to medium',
      () async {
    SharedPreferences.setMockInitialValues({'shake_sensitivity': 'bogus'});
    await ShakePrefs.load();
    expect(ShakePrefs.sensitivity.value, ShakeSensitivity.medium);
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/services/shake_prefs_test.dart`
Expected: FAIL — `Error: Undefined name 'ShakeSensitivity'` / `Undefined name 'thresholdFor'` (the symbols don't exist yet).

- [ ] **Step 3: Write the implementation**

Replace the full contents of `lib/services/shake_prefs.dart` with:

```dart
// ─────────────────────────────────────────────────────────────────────────────
//  Lumi · Shake-to-SOS preferences
//  Two persisted values: whether shake-to-SOS is on, and how hard a shake
//  must be (sensitivity). Default ON / Medium — users who get false triggers
//  while running/cycling can turn it off or make it harder to trigger from
//  the Track tab.
//  See docs/superpowers/specs/2026-07-05-shake-sensitivity-design.md
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ShakeSensitivity { low, medium, high }

/// Force threshold — 2.0g (High) is easier to trigger than 3.5g (Low).
/// Shake *count* stays fixed at 2 everywhere; this only tunes force.
double thresholdFor(ShakeSensitivity level) => switch (level) {
      ShakeSensitivity.low => 3.5,
      ShakeSensitivity.medium => 2.7, // the shake package's own default
      ShakeSensitivity.high => 2.0,
    };

class ShakePrefs {
  ShakePrefs._();

  static const _enabledKey = 'shake_to_sos_enabled';
  static const _sensitivityKey = 'shake_sensitivity';

  /// Listen to this to start/stop the detector; toggle via [setEnabled].
  static final ValueNotifier<bool> enabled = ValueNotifier(true);

  /// Listen to this to rebuild the detector at a new threshold; set via
  /// [setSensitivity].
  static final ValueNotifier<ShakeSensitivity> sensitivity =
      ValueNotifier(ShakeSensitivity.medium);

  /// Load the persisted values (call once at startup, before first listen).
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    enabled.value = prefs.getBool(_enabledKey) ?? true;
    sensitivity.value = _decode(prefs.getString(_sensitivityKey));
  }

  static Future<void> setEnabled(bool value) async {
    enabled.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
  }

  static Future<void> setSensitivity(ShakeSensitivity level) async {
    sensitivity.value = level;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sensitivityKey, level.name);
  }

  static ShakeSensitivity _decode(String? stored) => switch (stored) {
        'low' => ShakeSensitivity.low,
        'high' => ShakeSensitivity.high,
        _ => ShakeSensitivity.medium, // covers 'medium', null, and garbage
      };
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/services/shake_prefs_test.dart`
Expected: `+7: All tests passed!` (3 existing + 4 new).

- [ ] **Step 5: Full suite green, commit**

Run: `flutter test` — expected `All tests passed!` (31 + 4 = 35 total).

```bash
git add lib/services/shake_prefs.dart test/services/shake_prefs_test.dart
git commit -m "feat: ShakeSensitivity enum, threshold mapping, and persistence"
```

---

### Task 2: Foreground detector reacts to sensitivity

**Files:**
- Modify: `lib/navigation_bar/main_page.dart:60,83,121-135`

**Interfaces:**
- Consumes: `ShakePrefs.sensitivity` (`ValueNotifier<ShakeSensitivity>`), `thresholdFor(ShakeSensitivity)` (Task 1).
- Produces: nothing new for later tasks — `_syncShakeDetector` keeps its existing name/signature (`void _syncShakeDetector()`), which Task 3's UI change does not touch.

- [ ] **Step 1: Add the sensitivity listener alongside the existing one**

In `lib/navigation_bar/main_page.dart`, in `initState` (around line 60), change:

```dart
    ShakePrefs.enabled.addListener(_syncShakeDetector);
```

to:

```dart
    ShakePrefs.enabled.addListener(_syncShakeDetector);
    ShakePrefs.sensitivity.addListener(_syncShakeDetector);
```

- [ ] **Step 2: Remove the listener in dispose**

In `dispose` (around line 83), change:

```dart
    ShakePrefs.enabled.removeListener(_syncShakeDetector);
```

to:

```dart
    ShakePrefs.enabled.removeListener(_syncShakeDetector);
    ShakePrefs.sensitivity.removeListener(_syncShakeDetector);
```

- [ ] **Step 3: Pass the threshold into the detector and notify the service on change**

Replace the current `_syncShakeDetector` (lines 121-135):

```dart
  void _syncShakeDetector() {
    final android = !kIsWeb && Platform.isAndroid;
    if (ShakePrefs.enabled.value) {
      _shakeDetector ??= ShakeDetector.autoStart(
        onPhoneShake: (_) => _onShake(),
        // Two distinct shakes required — cuts down pocket/bag false alarms.
        minimumShakeCount: 2,
      );
      if (android) _startGuardIfPermitted();
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

(Note: this changes `_shakeDetector ??=` to an unconditional rebuild — required so a sensitivity-only change, which does not touch `ShakePrefs.enabled`, actually reconstructs the detector at the new threshold. `ShakeGuardService.notifySensitivity` is defined in Task 3; this task will not compile standalone until Task 3 lands, which is expected for this pair of tightly-coupled tasks — see the note in Task 3.)

- [ ] **Step 4: Full suite green (after Task 3's service change compiles), commit**

This task and Task 3 must land together to compile — see Task 3 Step 4 for the combined test run and commit. Do not commit Task 2 alone.

---

### Task 3: Background service reacts to a live sensitivity change

**Files:**
- Modify: `lib/services/shake_guard_service.dart`

**Interfaces:**
- Consumes: `ShakePrefs.sensitivity`, `thresholdFor(ShakeSensitivity)` (Task 1); called by Task 2's `_syncShakeDetector`.
- Produces: `ShakeGuardService.notifySensitivity(ShakeSensitivity level)` — `void`, Task 2 relies on this exact name and signature.

- [ ] **Step 1: Add the import**

In `lib/services/shake_guard_service.dart`, add to the imports:

```dart
import 'shake_prefs.dart';
```

- [ ] **Step 2: Add `notifySensitivity` next to `notifyLifecycle`**

After the existing `notifyLifecycle` method (currently lines 77-81):

```dart
  /// The service must not react to shakes while the app is foregrounded —
  /// the in-app detector owns those. NavBarPage pings us on every change.
  static void notifyLifecycle({required bool resumed}) =>
      FlutterForegroundTask.sendDataToTask(
          resumed ? 'app_resumed' : 'app_paused');
```

add:

```dart

  /// Pushes a live sensitivity change to the running service (no-op if it
  /// isn't running). NavBarPage calls this from the same place it reacts to
  /// ShakePrefs.sensitivity changes for the in-app detector.
  static void notifySensitivity(ShakeSensitivity level) =>
      FlutterForegroundTask.sendDataToTask('sensitivity:${level.name}');
```

- [ ] **Step 3: Read the initial threshold at start, and handle the live-change message**

Replace the `onStart` method (currently lines 128-161):

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

  void _startDetector(double threshold) {
    _detector = ShakeDetector.autoStart(
      minimumShakeCount: 2,
      shakeThresholdGravity: threshold,
      onPhoneShake: (_) => _core?.shakeDetected(),
    );
  }
```

- [ ] **Step 4: Handle the `sensitivity:*` message in `onReceiveData`**

Replace the current `onReceiveData` (lines 163-167):

```dart
  @override
  void onReceiveData(Object data) {
    if (data == 'app_resumed') _core?.appResumed();
    if (data == 'app_paused') _core?.appPaused();
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
  }
```

- [ ] **Step 5: Analyze, full suite green, build apk, commit**

Run: `flutter analyze` — no new issues in `lib/navigation_bar/main_page.dart` or `lib/services/shake_guard_service.dart`.
Run: `flutter test` — expected `All tests passed!` (35 total — this task adds no new unit tests per the spec's testing section; the wiring is glue, verified in Task 4's emulator e2e).
Run: `flutter build apk --debug` — expected `✓ Built build/app/outputs/flutter-apk/app-debug.apk` (proves the Android-side compiles; this task and Task 2 are interdependent and must be committed together).

```bash
git add lib/navigation_bar/main_page.dart lib/services/shake_guard_service.dart
git commit -m "feat: propagate shake sensitivity to the foreground detector and background service"
```

---

### Task 4: Sensitivity picker on the Track page

**Files:**
- Modify: `lib/pages/location_page.dart`

**Interfaces:**
- Consumes: `ShakePrefs.sensitivity`, `ShakePrefs.setSensitivity`, `ShakeSensitivity` (Task 1).
- Produces: nothing for later tasks.

- [ ] **Step 1: Add the segmented control under the existing switch row**

In `lib/pages/location_page.dart`, the shake-to-SOS `LumiCard` currently ends with (around lines 142-171):

```dart
          // shake-to-SOS
          LumiCard(
            child: Row(
              children: [
                _TileIcon(
                    icon: Icons.vibration,
                    bg: LumiColors.blue.withOpacity(0.14),
                    fg: LumiColors.blue),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Shake to SOS',
                          style: LumiText.body(14.5, weight: FontWeight.w700)),
                      Text('Shake your phone to trigger an alert',
                          style: LumiText.body(12, color: LumiColors.textSub)),
                    ],
                  ),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: ShakePrefs.enabled,
                  builder: (_, on, __) => Switch(
                    value: on,
                    activeColor: Colors.white,
                    activeTrackColor: LumiColors.blue,
                    onChanged: _setShakeEnabled,
                  ),
                ),
              ],
            ),
          ),
```

Replace it with (adds the sensitivity row inside the same card, below the switch row):

```dart
          // shake-to-SOS
          LumiCard(
            child: Column(
              children: [
                Row(
                  children: [
                    _TileIcon(
                        icon: Icons.vibration,
                        bg: LumiColors.blue.withOpacity(0.14),
                        fg: LumiColors.blue),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Shake to SOS',
                              style:
                                  LumiText.body(14.5, weight: FontWeight.w700)),
                          Text('Shake your phone to trigger an alert',
                              style:
                                  LumiText.body(12, color: LumiColors.textSub)),
                        ],
                      ),
                    ),
                    ValueListenableBuilder<bool>(
                      valueListenable: ShakePrefs.enabled,
                      builder: (_, on, __) => Switch(
                        value: on,
                        activeColor: Colors.white,
                        activeTrackColor: LumiColors.blue,
                        onChanged: _setShakeEnabled,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ListenableBuilder(
                  listenable: Listenable.merge(
                      [ShakePrefs.enabled, ShakePrefs.sensitivity]),
                  builder: (_, __) => IgnorePointer(
                    ignoring: !ShakePrefs.enabled.value,
                    child: Opacity(
                      opacity: ShakePrefs.enabled.value ? 1 : 0.4,
                      child: SegmentedButton<ShakeSensitivity>(
                        segments: const [
                          ButtonSegment(
                              value: ShakeSensitivity.low,
                              label: Text('Low')),
                          ButtonSegment(
                              value: ShakeSensitivity.medium,
                              label: Text('Medium')),
                          ButtonSegment(
                              value: ShakeSensitivity.high,
                              label: Text('High')),
                        ],
                        selected: {ShakePrefs.sensitivity.value},
                        onSelectionChanged: (s) =>
                            ShakePrefs.setSensitivity(s.first),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
```

- [ ] **Step 2: Analyze and full suite**

Run: `flutter analyze` — no new issues in `lib/pages/location_page.dart`.
Run: `flutter test` — expected `All tests passed!` (35 total; no new tests here — this is UI wiring over already-tested `ShakePrefs`, per the spec's testing section).

- [ ] **Step 3: Commit**

```bash
git add lib/pages/location_page.dart
git commit -m "feat: shake sensitivity picker on the Track page"
```

---

### Task 5: Android emulator end-to-end verification

No code — runtime evidence per the spec's testing section, exercising both the foreground and background paths at each sensitivity level.

- [ ] **Step 1: Launch and sign in**

```bash
flutter emulators --launch Pixel9_API37_16k
flutter run -d emulator-5554
```

Sign in (a@a.com / 123456), ensure a guardian exists (Contacts tab), open the Track tab.

- [ ] **Step 2: Confirm the picker and default**

Confirm the new Low/Medium/High control appears under "Shake to SOS", defaults to **Medium** selected, and greys out (via `Opacity`/`IgnorePointer`) when the switch above it is toggled OFF, re-enabling when toggled back ON.

- [ ] **Step 3: Foreground — High catches a soft shake that Medium should miss**

With the app in the foreground and sensitivity set to **High**, synthesize a soft shake burst:

```bash
adb -s emulator-5554 emu sensor set acceleration 6:9.81:0
sleep 0.15
adb -s emulator-5554 emu sensor set acceleration -6:9.81:0
sleep 0.15
adb -s emulator-5554 emu sensor set acceleration 6:9.81:0
sleep 0.15
adb -s emulator-5554 emu sensor set acceleration 0:9.81:0
```
(repeat once more ~0.6s later for the two-shake threshold)

Expected: the in-app "Shake detected" countdown appears. Set sensitivity back to **Medium**, repeat the identical soft burst: expected no countdown (the burst is below Medium's 2.7g threshold — confirms the rebuild actually changed the live threshold, not just the stored pref).

- [ ] **Step 4: Background — Low ignores a shake that High catches, at the same force**

Toggle sensitivity to **Low**, background the app (`adb -s emulator-5554 shell input keyevent KEYCODE_HOME`), and synthesize a *moderate* burst (e.g. `±15:9.81:0`, same timing pattern as Step 3): expected no notification countdown (moderate force is under Low's 3.5g). Reopen the app, switch sensitivity to **High**, background again, repeat the identical moderate burst: expected the "Shake detected" heads-up notification countdown appears this time — confirming the live-push IPC (`notifySensitivity` → `onReceiveData` → detector rebuilt) actually took effect in the running service without restarting it.

- [ ] **Step 5: Record what you saw**

Report PASS/FAIL per step with screenshots/notification dumps (`adb shell dumpsys notification --noredact`). Any deviation is a finding, not something to route around.

---

## Self-review notes (done at planning time)

- Spec coverage: enum + threshold mapping + persistence ✓ (T1), foreground propagation with live rebuild ✓ (T2), background propagation with live IPC push ✓ (T3), UI picker disabled-when-off ✓ (T4), emulator e2e proving both paths at differing thresholds ✓ (T5). `ShakeGuardCore` correctly untouched — no task modifies it.
- Type consistency: `ShakeSensitivity`/`thresholdFor` (T1) match every consumer exactly — `main_page.dart` (T2), `shake_guard_service.dart` (T3), `location_page.dart` (T4). `ShakeGuardService.notifySensitivity(ShakeSensitivity)` (T3) matches the call in T2's `_syncShakeDetector`. The `'sensitivity:${level.name}'` wire format (T3 send side) matches the `data.substring(12)` / `ShakeSensitivity.values.byName(...)` parse (T3 receive side) — `'sensitivity:'` is exactly 12 characters.
- Noted explicitly in T2/T3: those two tasks are compile-interdependent (T2 calls `ShakeGuardService.notifySensitivity`, which T3 defines) and must be committed together — flagged in both tasks' steps so an implementer working one at a time doesn't get stuck on a red build partway through.
