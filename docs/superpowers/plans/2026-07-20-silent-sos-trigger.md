# Silent SOS Trigger Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A volume-down ×3 hardware gesture that silently arms and, after an 8s grace period, sends the existing `EmergencyAlert` alert — with zero on-screen UI, haptic-only feedback — per `docs/superpowers/specs/2026-07-20-silent-sos-trigger-design.md`.

**Architecture:** `SilentSosPrefs` (persisted on/off), `SilentSosController` (pure-Dart sliding-window pattern matcher + grace timer), `SilentSosChannel` (Dart wrapper over a new `MethodChannel`), a native `MainActivity.kt` override that intercepts and suppresses `KEYCODE_VOLUME_DOWN` only while enabled, and wiring in `NavBarPage` (app-wide, like shake detection) plus a new Track-page switch.

**Tech Stack:** Flutter/Dart, `clock` (already a dependency, used the same way `CheckInTimerCore` uses it), `fake_async` (dev dependency), Kotlin (`MainActivity.kt`), no new pub packages.

## Global Constraints

- Trigger pattern: volume-down ×3 within 1.5s. Cancel: the same pattern again within an 8s grace window after arming.
- Android only. The feature (including its Track-page toggle) is invisible/inert on iOS and web.
- No on-screen UI at any point — feedback is haptic only (`HapticFeedback`).
- Default `SilentSosPrefs.enabled` is `false` (opt-in).
- The native override must fail safe: if the Dart-set enabled flag is false (including before Flutter's engine is ready), volume buttons behave exactly as normal and the system volume popup is never suppressed.
- `EmergencyAlert.send()`/`hasGuardians()` are called exactly as the SOS button and shake-to-SOS already call them — no new alert logic.
- `flutter analyze --fatal-infos` must stay clean; `dart format` all new/changed files.
- Commit after every task; never add a Co-Authored-By trailer.

---

### Task 1: `SilentSosPrefs`

**Files:**
- Create: `lib/services/silent_sos_prefs.dart`
- Test: `test/services/silent_sos_prefs_test.dart`

**Interfaces:**
- Consumes: nothing new.
- Produces: `SilentSosPrefs.enabled` (`ValueNotifier<bool>`), `SilentSosPrefs.load()`, `SilentSosPrefs.setEnabled(bool)` — used by Tasks 4 and `main.dart`.

- [ ] **Step 1: Write the failing tests**

```dart
// test/services/silent_sos_prefs_test.dart
// Whether the silent SOS trigger is on — off by default, unlike ShakePrefs
// (this repurposes a hardware button while the app is open, so it's opt-in).
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safetyproject/services/silent_sos_prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('off by default', () async {
    SharedPreferences.setMockInitialValues({});
    await SilentSosPrefs.load();
    expect(SilentSosPrefs.enabled.value, isFalse);
  });

  test('setEnabled persists and survives a reload', () async {
    SharedPreferences.setMockInitialValues({});
    await SilentSosPrefs.load();

    await SilentSosPrefs.setEnabled(true);
    expect(SilentSosPrefs.enabled.value, isTrue);

    SilentSosPrefs.enabled.value = false; // scribble over the in-memory value
    await SilentSosPrefs.load();
    expect(SilentSosPrefs.enabled.value, isTrue);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/services/silent_sos_prefs_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'safetyproject/services/silent_sos_prefs.dart'` (file doesn't exist yet).

- [ ] **Step 3: Implement `SilentSosPrefs`**

```dart
// lib/services/silent_sos_prefs.dart
// ─────────────────────────────────────────────────────────────────────────────
//  Lumi · Silent SOS trigger preference
//  Whether volume-down ×3 is armed as a discreet SOS trigger. Off by
//  default: unlike shake-to-SOS this repurposes a hardware button (see
//  SilentSosChannel) while the app is open, so it's opt-in, not opt-out.
//  See docs/superpowers/specs/2026-07-20-silent-sos-trigger-design.md
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SilentSosPrefs {
  SilentSosPrefs._();

  static const _enabledKey = 'silent_sos_enabled';

  static final ValueNotifier<bool> enabled = ValueNotifier(false);

  /// Load the persisted value (call once at startup, before first listen).
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    enabled.value = prefs.getBool(_enabledKey) ?? false;
  }

  static Future<void> setEnabled(bool value) async {
    enabled.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/services/silent_sos_prefs_test.dart`
Expected: `All tests passed!` (2 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/services/silent_sos_prefs.dart test/services/silent_sos_prefs_test.dart
git commit -m "feat: SilentSosPrefs — persisted silent-trigger on/off"
```

---

### Task 2: `SilentSosController`

**Files:**
- Create: `lib/services/silent_sos_controller.dart`
- Test: `test/services/silent_sos_controller_test.dart`

**Interfaces:**
- Consumes: `package:clock/clock.dart` (already a dependency).
- Produces (used by Task 4):
  - `enum SilentSosPhase { idle, armed }`
  - `SilentSosController({required void Function() onArmed, required void Function() onCancelled, required void Function() onSend, int windowMs = SilentSosController.defaultWindowMs, int graceSeconds = SilentSosController.defaultGraceSeconds})`
  - `static const defaultWindowMs = 1500`, `static const defaultGraceSeconds = 8`
  - `ValueNotifier<SilentSosPhase> phase`
  - `void onVolumeDownPress()`
  - `void dispose()`

- [ ] **Step 1: Write the failing tests**

```dart
// test/services/silent_sos_controller_test.dart
// The silent-trigger pattern matcher: 3 volume-down presses within the
// window arms; the same pattern again during the grace period cancels;
// the grace period elapsing sends exactly once. Pure Dart, fake_async +
// clock so every timing rule is provable (same technique CheckInTimerCore
// uses).
import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safetyproject/services/silent_sos_controller.dart';

class _Probe {
  int armed = 0, cancelled = 0, sent = 0;
  late SilentSosController controller;

  _Probe({int graceSeconds = SilentSosController.defaultGraceSeconds}) {
    controller = SilentSosController(
      onArmed: () => armed++,
      onCancelled: () => cancelled++,
      onSend: () => sent++,
      graceSeconds: graceSeconds,
    );
  }
}

void main() {
  test('3 presses within the window arms', () {
    fakeAsync((async) {
      final p = _Probe();
      p.controller.onVolumeDownPress();
      async.elapse(const Duration(milliseconds: 200));
      p.controller.onVolumeDownPress();
      async.elapse(const Duration(milliseconds: 200));
      p.controller.onVolumeDownPress();

      expect(p.armed, 1);
      expect(p.controller.phase.value, SilentSosPhase.armed);
      p.controller.dispose();
    });
  });

  test('presses spread beyond the window do not arm', () {
    fakeAsync((async) {
      final p = _Probe();
      p.controller.onVolumeDownPress();
      async.elapse(const Duration(seconds: 1));
      p.controller.onVolumeDownPress();
      async.elapse(const Duration(seconds: 1)); // > 1.5s since the 1st press
      p.controller.onVolumeDownPress();

      expect(p.armed, 0);
      expect(p.controller.phase.value, SilentSosPhase.idle);
      p.controller.dispose();
    });
  });

  test('repeating the pattern during grace cancels and the grace timer '
      'does not still fire', () {
    fakeAsync((async) {
      final p = _Probe(graceSeconds: 8);
      for (var i = 0; i < 3; i++) {
        p.controller.onVolumeDownPress();
      }
      expect(p.armed, 1);

      async.elapse(const Duration(seconds: 2));
      for (var i = 0; i < 3; i++) {
        p.controller.onVolumeDownPress();
      }
      expect(p.cancelled, 1);
      expect(p.controller.phase.value, SilentSosPhase.idle);

      async.elapse(const Duration(seconds: 10));
      expect(p.sent, 0);
      p.controller.dispose();
    });
  });

  test('grace elapsing without a cancel sends exactly once', () {
    fakeAsync((async) {
      final p = _Probe(graceSeconds: 8);
      for (var i = 0; i < 3; i++) {
        p.controller.onVolumeDownPress();
      }
      async.elapse(const Duration(seconds: 8));

      expect(p.sent, 1);
      expect(p.controller.phase.value, SilentSosPhase.idle);

      async.elapse(const Duration(seconds: 30));
      expect(p.sent, 1); // still exactly once
      p.controller.dispose();
    });
  });

  test('6 rapid presses arm once then cancel once, not a double-arm', () {
    fakeAsync((async) {
      final p = _Probe();
      for (var i = 0; i < 6; i++) {
        p.controller.onVolumeDownPress();
      }
      expect(p.armed, 1);
      expect(p.cancelled, 1);
      expect(p.controller.phase.value, SilentSosPhase.idle);
      p.controller.dispose();
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/services/silent_sos_controller_test.dart`
Expected: FAIL — package resolve error (file doesn't exist yet).

- [ ] **Step 3: Implement `SilentSosController`**

```dart
// lib/services/silent_sos_controller.dart
// ─────────────────────────────────────────────────────────────────────────────
//  Lumi · Silent SOS trigger — pattern matcher + grace timer
//  Pure Dart so the 3-press window, arm/cancel toggle, and grace-period
//  send are unit-testable (mirrors CheckInTimerCore's use of `clock` for
//  fake_async-provable real-time logic). Never persisted: this is
//  in-session state only, same reasoning as FakeCallController.
//  See docs/superpowers/specs/2026-07-20-silent-sos-trigger-design.md
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

enum SilentSosPhase { idle, armed }

class SilentSosController {
  SilentSosController({
    required this.onArmed,
    required this.onCancelled,
    required this.onSend,
    this.windowMs = defaultWindowMs,
    this.graceSeconds = defaultGraceSeconds,
  });

  static const defaultWindowMs = 1500;
  static const defaultGraceSeconds = 8;

  final void Function() onArmed;
  final void Function() onCancelled;
  final void Function() onSend;
  final int windowMs;
  final int graceSeconds;

  final ValueNotifier<SilentSosPhase> phase = ValueNotifier(SilentSosPhase.idle);

  final List<DateTime> _presses = [];
  Timer? _graceTimer;

  /// Feed one consumed volume-down press. A run of 3 within [windowMs]
  /// toggles the phase: idle → armed (starts the grace timer), or
  /// armed → idle (cancels it). The press buffer clears on every match so
  /// a longer burst (e.g. 6 rapid presses) reads as arm-then-cancel, never
  /// a double-arm.
  void onVolumeDownPress() {
    final now = clock.now();
    _presses.add(now);
    _presses.removeWhere(
        (t) => now.difference(t) > Duration(milliseconds: windowMs));
    if (_presses.length < 3) return;
    _presses.clear();

    if (phase.value == SilentSosPhase.idle) {
      _arm();
    } else {
      _cancel();
    }
  }

  void _arm() {
    phase.value = SilentSosPhase.armed;
    _graceTimer?.cancel();
    _graceTimer = Timer(Duration(seconds: graceSeconds), _send);
    onArmed();
  }

  void _cancel() {
    _graceTimer?.cancel();
    _graceTimer = null;
    phase.value = SilentSosPhase.idle;
    onCancelled();
  }

  void _send() {
    _graceTimer = null;
    phase.value = SilentSosPhase.idle;
    onSend();
  }

  void dispose() {
    _graceTimer?.cancel();
    _graceTimer = null;
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/services/silent_sos_controller_test.dart`
Expected: `All tests passed!` (5 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/services/silent_sos_controller.dart test/services/silent_sos_controller_test.dart
git commit -m "feat: SilentSosController — volume-pattern matcher and grace timer"
```

---

### Task 3: `SilentSosChannel` + native volume-key interception

**Files:**
- Create: `lib/services/silent_sos_channel.dart`
- Test: `test/services/silent_sos_channel_test.dart`
- Modify: `android/app/src/main/kotlin/com/elatreby/safety/MainActivity.kt`

**Interfaces:**
- Consumes: nothing new (Flutter's `MethodChannel`/`services.dart`).
- Produces (used by Task 4): `SilentSosChannel.setEnabled(bool)` (`Future<void>`), `SilentSosChannel.listen(void Function() onPress)`. Channel name: `com.elatreby.safety/silent_sos`, method names `setEnabled` and `onVolumeDownPress` (must match the Kotlin side exactly).

- [ ] **Step 1: Write the failing tests**

```dart
// test/services/silent_sos_channel_test.dart
// The Dart side of the native volume-key bridge: setEnabled invokes the
// right method/argument on the channel, and listen() wires incoming
// native calls to the given callback. The native (Kotlin) half of this
// bridge is verified on-device — see the plan's final task.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safetyproject/services/silent_sos_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.elatreby.safety/silent_sos');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('setEnabled invokes the native method with the bool argument',
      () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return null;
    });

    await SilentSosChannel.setEnabled(true);
    expect(received?.method, 'setEnabled');
    expect(received?.arguments, true);
  });

  test('listen() fires the callback when native calls onVolumeDownPress',
      () async {
    var presses = 0;
    SilentSosChannel.listen(() => presses++);

    final message = channel.codec.encodeMethodCall(
        const MethodCall('onVolumeDownPress'));
    await messenger.handlePlatformMessage(
        channel.name, message, (_) {});

    expect(presses, 1);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/services/silent_sos_channel_test.dart`
Expected: FAIL — package resolve error (file doesn't exist yet).

- [ ] **Step 3: Implement `SilentSosChannel`**

```dart
// lib/services/silent_sos_channel.dart
// ─────────────────────────────────────────────────────────────────────────────
//  Lumi · Silent SOS platform bridge
//  Dart side of the native volume-key interception in MainActivity.kt.
//  setEnabled tells native whether to consume KEYCODE_VOLUME_DOWN and
//  suppress the system volume popup; listen() wires native's
//  onVolumeDownPress calls back to a Dart callback.
//  See docs/superpowers/specs/2026-07-20-silent-sos-trigger-design.md
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/services.dart';

class SilentSosChannel {
  SilentSosChannel._();

  static const _channel = MethodChannel('com.elatreby.safety/silent_sos');

  static Future<void> setEnabled(bool enabled) =>
      _channel.invokeMethod('setEnabled', enabled);

  /// Wires [onPress] to fire on every native-reported consumed press.
  /// Call once at startup; the handler stays registered for the app's
  /// lifetime (there's only ever one listener, matching how ShakeDetector
  /// is a single app-wide instance in NavBarPage).
  static void listen(void Function() onPress) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onVolumeDownPress') onPress();
    });
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/services/silent_sos_channel_test.dart`
Expected: `All tests passed!` (2 tests)

- [ ] **Step 5: Native volume-key interception**

Replace the full contents of `android/app/src/main/kotlin/com/elatreby/safety/MainActivity.kt`:

```kotlin
package com.elatreby.safety

import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Silent SOS trigger: while enabled, volume-down presses are consumed here
// (both ACTION_DOWN and ACTION_UP) instead of reaching the system — no
// volume change, no system volume popup — and forwarded to Dart, which
// runs the actual 3-press pattern matching (SilentSosController). Defaults
// to disabled so a channel that isn't ready yet, or any future exception
// here, fails safe to normal volume-button behavior.
class MainActivity : FlutterActivity() {
    private val silentSosChannelName = "com.elatreby.safety/silent_sos"
    private var silentSosEnabled = false
    private var silentSosChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // Must run first: this is what registers every other plugin
        // (Firebase, Maps, telephony, ...) via GeneratedPluginRegistrant.
        super.configureFlutterEngine(flutterEngine)

        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, silentSosChannelName)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "setEnabled" -> {
                    silentSosEnabled = call.arguments as? Boolean ?: false
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        silentSosChannel = channel
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (silentSosEnabled && event.keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) {
            if (event.action == KeyEvent.ACTION_DOWN) {
                silentSosChannel?.invokeMethod("onVolumeDownPress", null)
            }
            return true // consume DOWN and UP: no volume change, no popup
        }
        return super.dispatchKeyEvent(event)
    }
}
```

- [ ] **Step 6: Verify with static analysis**

Run: `dart format lib/services/silent_sos_channel.dart test/services/silent_sos_channel_test.dart && flutter analyze --fatal-infos`
Expected: clean. (The Kotlin file has no analyzer in this project's CI; it's verified by a successful `flutter build`/`flutter run` and the on-emulator checklist in the final task.)

Run: `flutter build apk --debug` (or `flutter run -d <android-device-id>` if a device/emulator is available) to confirm `MainActivity.kt` compiles.
Expected: build succeeds.

- [ ] **Step 7: Commit**

```bash
git add lib/services/silent_sos_channel.dart test/services/silent_sos_channel_test.dart android/app/src/main/kotlin/com/elatreby/safety/MainActivity.kt
git commit -m "feat: SilentSosChannel and native volume-key interception"
```

---

### Task 4: Wiring — `NavBarPage` and the Track-page switch

**Files:**
- Modify: `lib/navigation_bar/main_page.dart`
- Modify: `lib/pages/location_page.dart`

**Interfaces:**
- Consumes: `SilentSosPrefs.enabled`/`.setEnabled` (Task 1), `SilentSosController` + `SilentSosPhase` (Task 2), `SilentSosChannel.setEnabled`/`.listen` (Task 3), `EmergencyAlert.hasGuardians()`/`.send()` (existing).
- Produces: user-visible feature; nothing downstream.

No widget test for this task: `NavBarPage` is never constructed directly in this project's test suite (it pulls in Firebase, Google Maps, and SQLite — the existing shake-to-SOS wiring in this same file has no widget test either, only the on-emulator checklist covers it). This task is verified in Task 5's on-emulator checklist.

- [ ] **Step 1: `main_page.dart` — imports and the controller field**

Add to the import block (after the `dart:io` import, alongside the other `package:flutter` imports):

```dart
import 'package:flutter/services.dart';
```

Add to the `../services/...` import group (alphabetical position after `pending_call.dart`):

```dart
import '../services/silent_sos_channel.dart';
import '../services/silent_sos_controller.dart';
import '../services/silent_sos_prefs.dart';
```

Add a field to `_NavBarPageState`, next to the existing `_shakeDetector` field:

```dart
  // ── silent SOS trigger ──────────────────────────────────────────────────
  // Lives here (not in SosPage) so the volume-button pattern works on every
  // tab, same reasoning as shake-to-SOS above. Android-only; the channel is
  // simply never enabled on other platforms.
  late final SilentSosController _silentSos = SilentSosController(
    onArmed: _onSilentSosArmed,
    onCancelled: _onSilentSosCancelled,
    onSend: () => _onSilentSosSend(),
  );
```

- [ ] **Step 2: `main_page.dart` — sync/dispose and the handler methods**

In `initState`, after the existing `ShakePrefs.sensitivity.addListener(_syncShakeDetector);` / `CheckInPrefs.endTime.addListener(_syncShakeDetector);` lines, add:

```dart
    SilentSosPrefs.enabled.addListener(_syncSilentSos);
    if (!kIsWeb && Platform.isAndroid) {
      SilentSosChannel.listen(_silentSos.onVolumeDownPress);
    }
```

At the end of `initState`'s existing `WidgetsBinding.instance.addPostFrameCallback((_) => _armShakeToSos());` line, add a second post-frame callback right after it:

```dart
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncSilentSos());
```

In `dispose`, after the existing `CheckInPrefs.endTime.removeListener(_syncShakeDetector);` line, add:

```dart
    SilentSosPrefs.enabled.removeListener(_syncSilentSos);
    _silentSos.dispose();
    if (!kIsWeb && Platform.isAndroid) SilentSosChannel.setEnabled(false); // logout
```

Add these new methods to `_NavBarPageState` (a sensible spot is right after `_startGuardIfPermitted`, before `_onShake`):

```dart
  /// Tells native whether to intercept volume-down. Android-only — the
  /// channel has no native counterpart on other platforms.
  void _syncSilentSos() {
    if (!kIsWeb && Platform.isAndroid) {
      SilentSosChannel.setEnabled(SilentSosPrefs.enabled.value);
    }
  }

  // Haptic-only feedback throughout — the entire point of this trigger is
  // that nothing appears on screen. See the design spec's feedback table.
  void _onSilentSosArmed() {
    HapticFeedback.vibrate();
    Future.delayed(const Duration(milliseconds: 150), HapticFeedback.vibrate);
    Future.delayed(const Duration(milliseconds: 300), HapticFeedback.vibrate);
  }

  void _onSilentSosCancelled() => HapticFeedback.vibrate();

  Future<void> _onSilentSosSend() async {
    try {
      if (!await EmergencyAlert.hasGuardians()) {
        HapticFeedback.heavyImpact(); // one long buzz: nothing to send
        return;
      }
      final failures = await EmergencyAlert.send();
      if (failures.isEmpty) {
        HapticFeedback.vibrate();
        await Future.delayed(const Duration(milliseconds: 200));
        HapticFeedback.vibrate();
      } else {
        HapticFeedback.heavyImpact();
      }
    } catch (_) {
      HapticFeedback.heavyImpact();
    }
  }
```

- [ ] **Step 3: `location_page.dart` — the Track-page switch**

Add to the import block, alphabetical position after `siren.dart`:

```dart
import '../services/silent_sos_prefs.dart';
```

Insert a new card directly after the existing shake-to-SOS `LumiCard` block and its trailing `const SizedBox(height: 9);` (i.e. right before the `// check-in timer ("walk me home")` comment and `const CheckInCard(),` line), gated to Android only per the design spec's platform scope:

```dart
              if (!kIsWeb && Platform.isAndroid) ...[
                LumiCard(
                  child: Row(
                    children: [
                      _TileIcon(
                          icon: Icons.volume_down,
                          bg: LumiColors.blue.withValues(alpha: 0.14),
                          fg: LumiColors.blue),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Silent SOS trigger',
                                style: LumiText.body(14.5,
                                    weight: FontWeight.w700)),
                            Text(
                                'Press volume-down 3× to silently alert '
                                'your guardians — press 3× again to cancel',
                                style: LumiText.body(12,
                                    color: LumiColors.textSub)),
                          ],
                        ),
                      ),
                      ValueListenableBuilder<bool>(
                        valueListenable: SilentSosPrefs.enabled,
                        builder: (_, on, __) => Switch(
                          value: on,
                          activeThumbColor: Colors.white,
                          activeTrackColor: LumiColors.blue,
                          onChanged: SilentSosPrefs.setEnabled,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 9),
              ],
```

- [ ] **Step 4: Verify with static analysis and the full suite**

Run: `dart format lib/navigation_bar/main_page.dart lib/pages/location_page.dart && flutter analyze --fatal-infos && flutter test`
Expected: analyzer clean; full suite green (no existing test constructs `NavBarPage` or exercises this section of `location_page.dart`, so no regressions are expected — if any existing `location_page.dart`-hosting test's finders break because of the new conditional card, fix those finders minimally).

- [ ] **Step 5: Commit**

```bash
git add lib/navigation_bar/main_page.dart lib/pages/location_page.dart
git commit -m "feat: wire the silent SOS trigger into NavBarPage and the Track page"
```

---

### Task 5: Startup load, on-device verification, and docs

**Files:**
- Modify: `lib/main.dart`
- Modify: `README.md`

**Interfaces:** none — startup wiring, verification, and documentation only.

- [ ] **Step 1: Startup load**

In `lib/main.dart`, after the existing `await FakeCallPrefs.load();` line, add:

```dart
  await SilentSosPrefs.load();
```

with the matching import `import 'services/silent_sos_prefs.dart';` beside the other services imports.

Run: `flutter analyze --fatal-infos && flutter test`
Expected: clean; full suite green.

- [x] **Step 2: On-emulator verification**

On the Android emulator (`flutter emulators --launch Pixel9_API37_16k`, `flutter run -d emulator-5554`, `adb` at `~/Library/Android/sdk/platform-tools/adb`) — never the physical Samsung without explicit say-so, and seed a single safe placeholder guardian before triggering any send (per the project's physical-device safety rule, which applies to the emulator's SMS/call side effects too):

1. Track page shows the new "Silent SOS trigger" switch, off by default.
2. Turn it on. Rapidly send 3 volume-down key events: `adb -s emulator-5554 shell input keyevent 25` three times within ~1s (keycode 25 = `KEYCODE_VOLUME_DOWN`). Confirm via `adb -s emulator-5554 shell dumpsys media_session | grep -i volume` (or simply watch the emulator's screen) that **no system volume slider appears**.
3. Confirm the alert fires ~8s later: check `adb -s emulator-5554 shell content query --uri content://sms/sent --projection address,date,body` for a new row addressed to the seeded guardian, timestamped after the trigger.
4. Repeat the trigger, then send another 3× volume-down within the 8s grace window; confirm **no** new SMS row appears after the full 8s+ has elapsed (the cancel worked).
5. Turn the switch off. Confirm `adb -s emulator-5554 shell input keyevent 25` now shows the normal system volume slider again (interception is off).
6. With the switch on and zero guardians seeded, trigger the pattern and confirm no SMS is sent (the `hasGuardians()` no-op path) — remove the guardian first, or run this check before Step 3 seeds one.

Record the outcome of each numbered check.

- [x] **Step 3: README bullet**

In `README.md` under `### Alerting`, after the "Shake to SOS" bullet, add:

```markdown
- **Silent SOS trigger** — press volume-down three times quickly (Android,
  opt-in from the Track page) to arm a fully silent alert: no on-screen UI
  at any point, only haptic pulses confirm each step. An 8-second grace
  period follows arming; the same 3× pattern during that window cancels.
  Suppresses the system volume popup while enabled so the whole gesture
  stays invisible on screen.
```

- [x] **Step 4: Full suite green, commit, push, watch CI**

Run: `flutter analyze --fatal-infos && flutter test`
Expected: clean.

```bash
git add lib/main.dart README.md docs/superpowers/plans/2026-07-20-silent-sos-trigger.md
git commit -m "docs: README silent SOS trigger; tick plan; load SilentSosPrefs at startup"
git push origin master
gh run watch $(gh run list --repo AhmedElatreby/Graduation_project --limit 1 --json databaseId --jq '.[0].databaseId') --repo AhmedElatreby/Graduation_project --exit-status
```

Expected: CI green.

---

## Self-Review Notes

- **Spec coverage:** persisted off-by-default pref (Task 1), sliding-window pattern matcher + 8s grace + cancel-toggle (Task 2), native suppression + fail-safe-disabled default + Dart bridge (Task 3), app-wide wiring via `NavBarPage` + haptic feedback table (armed/cancelled/sent/no-guardians-or-failed) + Android-only Track-page switch (Task 4), startup load + on-emulator checklist covering the popup-suppression/send/cancel/toggle-off/no-guardians cases + README (Task 5). Out-of-scope items (background/screen-off, iOS, visible UI, test button) have no tasks — correct.
- **Type consistency:** `SilentSosPhase`, `SilentSosController`'s constructor params and `onVolumeDownPress()`/`dispose()`, and `SilentSosChannel.setEnabled`/`.listen` are used with identical signatures across Tasks 2–4. The native method names (`setEnabled`, `onVolumeDownPress`) match exactly between Task 3's Kotlin and Dart halves.
- **Known risk:** Task 3's Kotlin change has no automated test (no precedent for native unit tests in this repo — the existing foreground-service Kotlin code is verified the same way, via `flutter build`/on-emulator checks). Task 5's checklist is the only thing that proves `dispatchKeyEvent` actually suppresses the popup and forwards presses correctly; treat that step as load-bearing, not optional.
