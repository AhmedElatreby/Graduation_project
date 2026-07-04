# Background Shake-to-SOS (Android) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On Android, shake detection keeps working while the app is backgrounded — a shake shows a heads-up notification countdown with "I'm safe — cancel", and at zero sends silent SMS to every guardian plus a best-effort call to the first.

**Architecture:** An Android foreground service (`flutter_foreground_task`) hosts a Dart isolate running the same `shake` detector and the existing `EmergencyAlert` service. A pure-Dart state machine (`ShakeGuardCore`) owns the countdown/cancel/dispatch logic so it is unit-testable; the `TaskHandler` is thin glue that maps core callbacks to notification updates. The existing Track-page toggle is the master switch.

**Tech Stack:** Flutter 3.44, `flutter_foreground_task`, `shake` (existing), `telephony` (existing, silent SMS), `flutter_phone_direct_caller` (existing), `shared_preferences` (existing), `sqflite` via existing `DBHelper`.

**Spec:** `docs/superpowers/specs/2026-07-04-background-shake-to-sos-design.md`

## Global Constraints

- Android-only. Every service start/stop and lifecycle ping is guarded by `Platform.isAndroid`. iOS behaviour must not change.
- Exact user-facing copy (from spec + existing app): persistent notification title **"Lumi is protecting you"**; countdown title **"Shake detected"**, text **"Alerting your guardians in N…"**; cancel button **"I'm safe — cancel"**; success **"Alert sent to your guardians"**; no-guardians **"Add guardians first"**.
- Shake threshold identical to foreground: `minimumShakeCount: 2`.
- No reboot persistence (`autoRunOnBoot` stays false). No `ACCESS_BACKGROUND_LOCATION` — if GPS fails in the background the SMS uses the existing "(My location is unavailable right now.)" wording.
- The foreground no-guardians guard from the spec is **already implemented** (commit b781c46, `EmergencyAlert.hasGuardians()`); tasks below reuse it.
- Git commits: never add a Co-Authored-By trailer.
- TDD for every task that has testable logic; `flutter test` must be fully green before every commit.

---

### Task 1: `ShakeGuardCore` — the countdown/dispatch state machine

Pure Dart, no plugins. This is the unit the spec's test list targets: cancel never sends; zero sends exactly once; shakes while the app is resumed are ignored; no-guardians short-circuits.

**Files:**
- Create: `lib/services/shake_guard_core.dart`
- Test: `test/services/shake_guard_core_test.dart`
- Modify: `pubspec.yaml` (add `fake_async` to dev_dependencies)

**Interfaces:**
- Consumes: nothing (pure Dart).
- Produces (Task 3 relies on these exact members):
  - `ShakeGuardCore({required Future<bool> Function() hasGuardians, required Future<void> Function() send, required void Function(int remaining) onTick, required void Function() onCancelled, required void Function() onSent, required void Function() onNoGuardians, int seconds = 5})`
  - `Future<void> shakeDetected()`, `void cancel()`, `void appResumed()`, `void appPaused()`, `void dispose()`
  - `_appResumed` starts **true** (the service is started by the foregrounded app; the in-app detector owns foreground shakes).

- [ ] **Step 1: Add fake_async and write the failing tests**

In `pubspec.yaml` under `dev_dependencies:` add:

```yaml
  fake_async: ^1.3.1
```

Run `flutter pub get`.

Create `test/services/shake_guard_core_test.dart`:

```dart
// The background shake state machine: cancel never sends, zero sends exactly
// once, foreground shakes are ignored, and no guardians short-circuits.
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safetyproject/services/shake_guard_core.dart';

class _Probe {
  int sends = 0, cancels = 0, sents = 0, noGuardians = 0;
  final ticks = <int>[];
  bool guardians = true;

  late final ShakeGuardCore core = ShakeGuardCore(
    hasGuardians: () async => guardians,
    send: () async => sends++,
    onTick: ticks.add,
    onCancelled: () => cancels++,
    onSent: () => sents++,
    onNoGuardians: () => noGuardians++,
  );
}

void main() {
  test('shake while app is resumed is ignored', () {
    fakeAsync((async) {
      final p = _Probe();
      // core starts with the app considered resumed (service is started by
      // the foregrounded app) — no countdown may begin.
      p.core.shakeDetected();
      async.elapse(const Duration(seconds: 10));
      expect(p.ticks, isEmpty);
      expect(p.sends, 0);
    });
  });

  test('background shake counts down and sends exactly once', () {
    fakeAsync((async) {
      final p = _Probe();
      p.core.appPaused();
      p.core.shakeDetected();
      async.flushMicrotasks();
      expect(p.ticks, [5]);
      async.elapse(const Duration(seconds: 5));
      expect(p.ticks, [5, 4, 3, 2, 1]);
      expect(p.sends, 1);
      expect(p.sents, 1);
      async.elapse(const Duration(seconds: 10));
      expect(p.sends, 1); // never double-fires
    });
  });

  test('cancel stops the countdown and never sends, even past the deadline',
      () {
    fakeAsync((async) {
      final p = _Probe();
      p.core.appPaused();
      p.core.shakeDetected();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 2));
      p.core.cancel();
      expect(p.cancels, 1);
      async.elapse(const Duration(seconds: 20));
      expect(p.sends, 0);
    });
  });

  test('repeat shakes during a countdown are ignored', () {
    fakeAsync((async) {
      final p = _Probe();
      p.core.appPaused();
      p.core.shakeDetected();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 2));
      p.core.shakeDetected();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 3));
      expect(p.sends, 1); // one countdown, one send — not restarted
      expect(p.ticks, [5, 4, 3, 2, 1]);
    });
  });

  test('no guardians short-circuits: prompt, no countdown, no send', () {
    fakeAsync((async) {
      final p = _Probe()..guardians = false;
      p.core.appPaused();
      p.core.shakeDetected();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 10));
      expect(p.noGuardians, 1);
      expect(p.ticks, isEmpty);
      expect(p.sends, 0);
    });
  });

  test('cancel when idle does nothing', () {
    fakeAsync((async) {
      final p = _Probe();
      p.core.cancel();
      expect(p.cancels, 0);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/services/shake_guard_core_test.dart`
Expected: FAIL to load — `Error: Couldn't resolve the package 'safetyproject/services/shake_guard_core.dart'` (file doesn't exist).

- [ ] **Step 3: Write the implementation**

Create `lib/services/shake_guard_core.dart`:

```dart
// ─────────────────────────────────────────────────────────────────────────────
//  Lumi · Shake-guard state machine (background shake-to-SOS)
//  Pure Dart so the countdown/cancel/dispatch rules are unit-testable.
//  The foreground-service TaskHandler wires the callbacks to notifications;
//  nothing in here may touch plugins.
//  See docs/superpowers/specs/2026-07-04-background-shake-to-sos-design.md
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';

class ShakeGuardCore {
  ShakeGuardCore({
    required this.hasGuardians,
    required this.send,
    required this.onTick,
    required this.onCancelled,
    required this.onSent,
    required this.onNoGuardians,
    this.seconds = 5,
  });

  final Future<bool> Function() hasGuardians;
  final Future<void> Function() send;
  final void Function(int remaining) onTick;
  final void Function() onCancelled;
  final void Function() onSent;
  final void Function() onNoGuardians;
  final int seconds;

  // The service is started by the app while it is in the foreground, so the
  // safe initial assumption is "resumed" — the in-app detector owns
  // foreground shakes and must not be doubled by the service.
  bool _appResumed = true;
  bool _counting = false;
  Timer? _timer;

  void appResumed() => _appResumed = true;
  void appPaused() => _appResumed = false;

  Future<void> shakeDetected() async {
    if (_appResumed || _counting) return;
    _counting = true;
    if (!await hasGuardians()) {
      _counting = false;
      onNoGuardians();
      return;
    }
    var remaining = seconds;
    onTick(remaining);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) async {
      remaining--;
      if (remaining <= 0) {
        _timer?.cancel();
        await send();
        _counting = false;
        onSent();
      } else {
        onTick(remaining);
      }
    });
  }

  void cancel() {
    if (!_counting) return;
    _timer?.cancel();
    _counting = false;
    onCancelled();
  }

  void dispose() => _timer?.cancel();
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/services/shake_guard_core_test.dart`
Expected: `+6: All tests passed!`

- [ ] **Step 5: Run the full suite, then commit**

Run: `flutter test` — expected `All tests passed!` (22 total).

```bash
git add pubspec.yaml pubspec.lock lib/services/shake_guard_core.dart test/services/shake_guard_core_test.dart
git commit -m "feat: ShakeGuardCore state machine for background shake-to-SOS"
```

---

### Task 2: `EmergencyAlert.sendBackground()` + pending-call flag

The background path must not open UI: silent SMS via `telephony`, best-effort call, and a persisted "the OS blocked the call" flag the app consumes on next resume.

**Files:**
- Modify: `lib/services/emergency_alert.dart`
- Create: `lib/services/pending_call.dart`
- Test: `test/services/emergency_alert_test.dart` (extend), `test/services/pending_call_test.dart`

**Interfaces:**
- Consumes: `DBHelper().getContacts()`, existing `currentCoordinates()`, existing `callFirstContact()`.
- Produces (Tasks 3–4 rely on these exact members):
  - `static String EmergencyAlert.buildAlertMessage(String? coords)`
  - `class BackgroundSendResult { final List<String> smsFailures; final bool callBlocked; }`
  - `static Future<BackgroundSendResult> EmergencyAlert.sendBackground()`
  - `class PendingCall { static Future<void> set(); static Future<bool> consume(); }` — `consume()` returns true at most once per `set()`.

- [ ] **Step 1: Write the failing tests**

Append to `test/services/emergency_alert_test.dart` (inside `main()`, after the existing test):

```dart
  test('buildAlertMessage includes the maps link when coords are known', () {
    expect(
      EmergencyAlert.buildAlertMessage('50.73,-1.85'),
      'I need help, please find me: https://maps.google.com/?q=50.73,-1.85',
    );
    expect(
      EmergencyAlert.buildAlertMessage(null),
      'I need help! (My location is unavailable right now.)',
    );
  });
```

Create `test/services/pending_call_test.dart`:

```dart
// PendingCall persists "the OS blocked the background auto-call"; the app
// consumes it exactly once on next resume and places the call itself.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safetyproject/services/pending_call.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('consume returns true once after set, then false', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await PendingCall.consume(), isFalse);

    await PendingCall.set();
    expect(await PendingCall.consume(), isTrue);
    expect(await PendingCall.consume(), isFalse); // one-shot
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/services/emergency_alert_test.dart test/services/pending_call_test.dart`
Expected: FAIL — `buildAlertMessage` isn't defined; `pending_call.dart` doesn't exist.

- [ ] **Step 3: Implement**

Create `lib/services/pending_call.dart`:

```dart
// ─────────────────────────────────────────────────────────────────────────────
//  Lumi · Pending guardian call
//  Android 10+ blocks a backgrounded service from launching the dialer. When
//  the background alert can't place the call, this flag survives until the
//  user opens the app (usually by tapping the "alert sent" notification),
//  which consumes it and dials the first guardian from the foreground.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:shared_preferences/shared_preferences.dart';

class PendingCall {
  PendingCall._();

  static const _key = 'pending_guardian_call';

  static Future<void> set() async =>
      (await SharedPreferences.getInstance()).setBool(_key, true);

  /// True at most once per [set] — clears the flag as it reads it.
  static Future<bool> consume() async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getBool(_key) ?? false;
    if (pending) await prefs.remove(_key);
    return pending;
  }
}
```

In `lib/services/emergency_alert.dart`:

1. Add import: `import 'pending_call.dart';`
2. Extract the message strings — inside `sendTexts`, replace

```dart
    final message = coords == null
        ? 'I need help! (My location is unavailable right now.)'
        : 'I need help, please find me: https://maps.google.com/?q=$coords';
```

with `final message = buildAlertMessage(coords);` and add to the class:

```dart
  /// The SMS body. Extracted so the foreground composer path and the
  /// background silent path can never drift apart.
  static String buildAlertMessage(String? coords) => coords == null
      ? 'I need help! (My location is unavailable right now.)'
      : 'I need help, please find me: https://maps.google.com/?q=$coords';
```

3. Add the result type (top level, same file) and the background sender (in the class):

```dart
class BackgroundSendResult {
  const BackgroundSendResult(
      {required this.smsFailures, required this.callBlocked});
  final List<String> smsFailures;
  final bool callBlocked;
}
```

```dart
  /// Background variant used by the Android shake-guard service: silent SMS
  /// per guardian (no composer UI), then a best-effort call. Android 10+
  /// usually blocks the dialer launch from the background — then we set
  /// [PendingCall] and report callBlocked so the notification can say
  /// "tap to call".
  static Future<BackgroundSendResult> sendBackground() async {
    final contacts = await DBHelper().getContacts();
    if (contacts.isEmpty) {
      return const BackgroundSendResult(
          smsFailures: ['Add emergency contacts first.'], callBlocked: false);
    }

    String? coords;
    try {
      coords = await currentCoordinates().timeout(const Duration(seconds: 10));
    } catch (_) {
      coords = null; // background GPS may be denied/slow — degrade, don't die
    }
    final message = buildAlertMessage(coords);

    final smsFailures = <String>[];
    final telephony = Telephony.backgroundInstance;
    for (final c in contacts) {
      try {
        await telephony.sendSms(to: c.contactNo, message: message);
      } catch (e) {
        smsFailures.add('SMS to ${c.name} failed: $e');
      }
    }

    var callBlocked = false;
    try {
      await callFirstContact(contacts: contacts);
    } catch (_) {
      callBlocked = true;
      await PendingCall.set();
    }
    return BackgroundSendResult(
        smsFailures: smsFailures, callBlocked: callBlocked);
  }
```

(`Telephony` is already imported in this file; `currentCoordinates()` already exists and returns `Future<String?>` — check its exact name at the top of the file and keep it.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/services/emergency_alert_test.dart test/services/pending_call_test.dart`
Expected: all pass.

- [ ] **Step 5: Full suite green, commit**

Run: `flutter test` — expected `All tests passed!`

```bash
git add lib/services/emergency_alert.dart lib/services/pending_call.dart test/services/emergency_alert_test.dart test/services/pending_call_test.dart
git commit -m "feat: silent background alert path (SMS + best-effort call + pending-call flag)"
```

---

### Task 3: Foreground service — dependency, manifest, `ShakeGuardService`

Glue with no unit-testable logic (all plugin calls); the gate for this task is `flutter analyze` clean and `flutter build apk --debug` succeeding.

**Files:**
- Modify: `pubspec.yaml` (add `flutter_foreground_task`)
- Modify: `android/app/src/main/AndroidManifest.xml`
- Create: `lib/services/shake_guard_service.dart`

**Interfaces:**
- Consumes: `ShakeGuardCore` (Task 1 signature), `EmergencyAlert.sendBackground()` / `hasGuardians()` (Task 2), `ShakeDetector.autoStart(onPhoneShake:, minimumShakeCount:)` from the existing `shake` package.
- Produces (Task 4 relies on these exact members):
  - `class ShakeGuardService { static void init(); static Future<void> start(); static Future<void> stop(); static void notifyLifecycle({required bool resumed}); }`
  - Top-level `@pragma('vm:entry-point') void shakeGuardCallback()`

- [ ] **Step 1: Add the dependency**

In `pubspec.yaml` under `dependencies:` add:

```yaml
  flutter_foreground_task: ^8.17.0
```

Run: `flutter pub get`
Expected: resolves cleanly. If the resolver or a later build complains about `compileSdk`, bump `compileSdkVersion` in `android/app/build.gradle` to `35` — nothing else.

- [ ] **Step 2: Manifest permissions + service declaration**

In `android/app/src/main/AndroidManifest.xml`, add below the existing `<uses-permission>` block (keep the explanatory comment in sync — extend it):

```xml
    <!-- Background shake-to-SOS (Android only):
         POST_NOTIFICATIONS          - countdown + result notifications (API 33+)
         FOREGROUND_SERVICE(+type)   - keeps shake detection alive in background
         CALL_PHONE                  - direct-dial the first guardian
         VIBRATE                     - countdown ticks are felt, not just seen -->
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE" />
    <uses-permission android:name="android.permission.CALL_PHONE" />
    <uses-permission android:name="android.permission.VIBRATE" />
```

Inside `<application>`, before `</application>`:

```xml
        <service
            android:name="com.pravera.flutter_foreground_task.service.ForegroundService"
            android:foregroundServiceType="specialUse"
            android:exported="false">
            <property
                android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
                android:value="Personal-safety shake detection with a user-cancellable SOS countdown" />
        </service>
```

- [ ] **Step 3: Write the service**

Create `lib/services/shake_guard_service.dart`:

```dart
// ─────────────────────────────────────────────────────────────────────────────
//  Lumi · Shake-guard foreground service (Android only)
//  Hosts ShakeGuardCore + a ShakeDetector in a background isolate so shaking
//  works when the app is backgrounded/swiped away. The Track-page toggle is
//  the master switch (NavBarPage starts/stops us). All countdown rules live
//  in ShakeGuardCore; this file only maps callbacks to notifications.
//  See docs/superpowers/specs/2026-07-04-background-shake-to-sos-design.md
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shake/shake.dart';

import 'emergency_alert.dart';
import 'shake_guard_core.dart';

@pragma('vm:entry-point')
void shakeGuardCallback() {
  FlutterForegroundTask.setTaskHandler(_ShakeGuardTaskHandler());
}

class ShakeGuardService {
  ShakeGuardService._();

  /// Call once at startup (main), before any start().
  static void init() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'shake_guard',
        channelName: 'Shake to SOS protection',
        channelDescription:
            'Watches for shakes and shows the cancellable SOS countdown.',
        channelImportance: NotificationChannelImportance.MAX,
        priority: NotificationPriority.MAX,
        enableVibration: true,
        playSound: true,
        onlyAlertOnce: false,
      ),
      iosNotificationOptions:
          const IOSNotificationOptions(showNotification: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
      ),
    );
  }

  static Future<void> start() async {
    if (await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.startService(
      serviceId: 257,
      notificationTitle: 'Lumi is protecting you',
      notificationText: 'Shake your phone twice to start an SOS.',
      callback: shakeGuardCallback,
    );
  }

  static Future<void> stop() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }

  /// The service must not react to shakes while the app is foregrounded —
  /// the in-app detector owns those. NavBarPage pings us on every change.
  static void notifyLifecycle({required bool resumed}) =>
      FlutterForegroundTask.sendDataToTask(
          resumed ? 'app_resumed' : 'app_paused');
}

class _ShakeGuardTaskHandler extends TaskHandler {
  ShakeDetector? _detector;
  ShakeGuardCore? _core;

  static const _cancelButtonId = 'cancel_sos';
  static const _cancelButton =
      NotificationButton(id: _cancelButtonId, text: "I'm safe — cancel");

  void _idleNotification() {
    FlutterForegroundTask.updateService(
      notificationTitle: 'Lumi is protecting you',
      notificationText: 'Shake your phone twice to start an SOS.',
      notificationButtons: const [],
    );
  }

  Future<void> _sendAlert() async {
    final result = await EmergencyAlert.sendBackground();
    final ok = result.smsFailures.isEmpty;
    FlutterForegroundTask.updateService(
      notificationTitle:
          ok ? 'Alert sent to your guardians' : 'Alert sent with problems',
      notificationText: [
        if (!ok) result.smsFailures.join(' · '),
        if (result.callBlocked)
          'Tap to open Lumi and call your first guardian.',
      ].join(' '),
      notificationButtons: const [],
    );
  }

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _core = ShakeGuardCore(
      hasGuardians: EmergencyAlert.hasGuardians,
      send: _sendAlert,
      onTick: (remaining) => FlutterForegroundTask.updateService(
        notificationTitle: 'Shake detected',
        notificationText: 'Alerting your guardians in $remaining…',
        notificationButtons: const [_cancelButton],
      ),
      onCancelled: _idleNotification,
      onSent: () {}, // _sendAlert wrote the result notification already
      onNoGuardians: () => FlutterForegroundTask.updateService(
        notificationTitle: 'Add guardians first',
        notificationText:
            'Open Lumi and add a guardian so an SOS can reach someone.',
        notificationButtons: const [],
      ),
    );
    _detector = ShakeDetector.autoStart(
      minimumShakeCount: 2,
      onPhoneShake: (_) => _core?.shakeDetected(),
    );
  }

  @override
  void onReceiveData(Object data) {
    if (data == 'app_resumed') _core?.appResumed();
    if (data == 'app_paused') _core?.appPaused();
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id == _cancelButtonId) _core?.cancel();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {} // eventAction: nothing()

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    _detector?.stopListening();
    _core?.dispose();
  }
}
```

**Note for the implementer:** `flutter_foreground_task`'s `TaskHandler` override signatures occasionally shift between majors. The authority is `flutter analyze` — if it flags a signature (e.g. `onDestroy` gaining a `bool isTimeout` parameter or `onStart`'s `TaskStarter`), match the installed version's signature exactly and change nothing else.

- [ ] **Step 4: Analyze and build**

Run: `flutter analyze`
Expected: no new warnings/errors.
Run: `flutter build apk --debug`
Expected: `✓ Built build/app/outputs/flutter-apk/app-debug.apk`. (This proves manifest merging and the service declaration are valid.)

- [ ] **Step 5: Full suite green, commit**

Run: `flutter test` — expected `All tests passed!`

```bash
git add pubspec.yaml pubspec.lock android/app/src/main/AndroidManifest.xml lib/services/shake_guard_service.dart
git commit -m "feat: Android foreground service hosting the shake guard"
```

---

### Task 4: App wiring — startup init, toggle → service, lifecycle pings, pending call

**Files:**
- Modify: `lib/main.dart`
- Modify: `lib/navigation_bar/main_page.dart`

**Interfaces:**
- Consumes: `ShakeGuardService.init/start/stop/notifyLifecycle` (Task 3), `PendingCall.consume()` + `EmergencyAlert.callFirstContact()` (Task 2), existing `ShakePrefs.enabled`.
- Produces: nothing new for later tasks.

- [ ] **Step 1: Startup init in `lib/main.dart`**

Add imports:

```dart
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'services/shake_guard_service.dart';
```

In `main()`, immediately after `WidgetsFlutterBinding.ensureInitialized();`:

```dart
  if (!kIsWeb && Platform.isAndroid) {
    // Receive-port for the shake-guard service isolate + notification config.
    FlutterForegroundTask.initCommunicationPort();
    ShakeGuardService.init();
  }
```

- [ ] **Step 2: NavBarPage — service lifecycle**

In `lib/navigation_bar/main_page.dart`:

Add imports:

```dart
import 'dart:io' show Platform;

import '../services/pending_call.dart';
import '../services/shake_guard_service.dart';
```

Make the state a lifecycle observer — change the class declaration:

```dart
class _NavBarPageState extends State<NavBarPage> with WidgetsBindingObserver {
```

In `initState()`, add before `_syncShakeDetector();`:

```dart
    WidgetsBinding.instance.addObserver(this);
```

In `dispose()`, add before `super.dispose();`:

```dart
    WidgetsBinding.instance.removeObserver(this);
    if (!kIsWeb && Platform.isAndroid) ShakeGuardService.stop(); // logout
```

(`kIsWeb` comes with the material import? No — add `import 'package:flutter/foundation.dart' show kIsWeb;`.)

Add the observer callback and pending-call consumption to the class:

```dart
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (kIsWeb || !Platform.isAndroid) return;
    if (state == AppLifecycleState.resumed) {
      ShakeGuardService.notifyLifecycle(resumed: true);
      _consumePendingCall();
    } else if (state == AppLifecycleState.paused) {
      ShakeGuardService.notifyLifecycle(resumed: false);
    }
  }

  /// The background alert couldn't launch the dialer (Android 10+ blocks
  /// it); the flag survives until the user opens the app — dial now.
  Future<void> _consumePendingCall() async {
    if (!await PendingCall.consume()) return;
    try {
      await EmergencyAlert.callFirstContact();
    } catch (_) {/* user can still dial from the SOS page */}
  }
```

Extend `_syncShakeDetector()` to also drive the service (final form):

```dart
  void _syncShakeDetector() {
    final android = !kIsWeb && Platform.isAndroid;
    if (ShakePrefs.enabled.value) {
      _shakeDetector ??= ShakeDetector.autoStart(
        onPhoneShake: (_) => _onShake(),
        // Two distinct shakes required — cuts down pocket/bag false alarms.
        minimumShakeCount: 2,
      );
      if (android) ShakeGuardService.start();
    } else {
      _shakeDetector?.stopListening();
      _shakeDetector = null;
      if (android) ShakeGuardService.stop();
    }
  }
```

- [ ] **Step 3: Analyze, test, run on iOS to prove nothing regressed**

Run: `flutter analyze` — clean.
Run: `flutter test` — `All tests passed!` (the suite mounts pages that now reference the service only behind `Platform.isAndroid`, which is false in the test VM on macOS, so no platform channels fire).

- [ ] **Step 4: Commit**

```bash
git add lib/main.dart lib/navigation_bar/main_page.dart
git commit -m "feat: wire shake-guard service to toggle, auth lifecycle, and pending call"
```

---

### Task 5: Permission gate on the Track-page toggle (Android)

Flipping the switch ON on Android must request notifications + SMS + phone; any denial flips it back with an explanation. iOS keeps the plain setter.

**Files:**
- Modify: `lib/pages/location_page.dart:159-167` (the `ValueListenableBuilder`/`Switch` for Shake to SOS)

**Interfaces:**
- Consumes: `ShakePrefs.setEnabled(bool)` (existing), `permission_handler` (existing dependency, already imported in this file).
- Produces: nothing for later tasks.

- [ ] **Step 1: Replace the switch handler**

In `lib/pages/location_page.dart`, the Shake to SOS switch currently ends with `onChanged: ShakePrefs.setEnabled,` — replace that line with:

```dart
                    onChanged: _setShakeEnabled,
```

Add to `_LocationPageState` (near the other handlers), plus `import 'dart:io' show Platform;` and `import 'package:flutter/foundation.dart' show kIsWeb;` at the top if not present:

```dart
  /// Android background SOS needs notification + SMS + phone permissions.
  /// Deny any of them and the switch stays OFF with an explanation.
  Future<void> _setShakeEnabled(bool value) async {
    if (!value || kIsWeb || !Platform.isAndroid) {
      await ShakePrefs.setEnabled(value);
      return;
    }
    final statuses = await [
      Permission.notification,
      Permission.sms,
      Permission.phone,
    ].request();
    if (statuses.values.every((s) => s.isGranted)) {
      await ShakePrefs.setEnabled(true);
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text(
          'Lumi needs notification, SMS and phone access for background SOS'),
      backgroundColor: LumiColors.accent.withOpacity(0.9),
    ));
  }
```

- [ ] **Step 2: Analyze and test**

Run: `flutter analyze` — clean.
Run: `flutter test` — `All tests passed!` (the test helper's `FakeGrantedPermissionHandlerPlatform` grants everything, and the test VM isn't Android anyway).

- [ ] **Step 3: Commit**

```bash
git add lib/pages/location_page.dart
git commit -m "feat: request SMS/phone/notification permissions when enabling shake-to-SOS on Android"
```

---

### Task 6: End-to-end verification on the Android emulator

No code — runtime evidence per the spec's testing section. The emulator can synthesize real accelerometer data, so the *actual* sensor→service→notification→SMS chain is exercised, no debug triggers.

- [ ] **Step 1: Launch an emulator and run the app**

```bash
flutter emulators                      # find an Android emulator id
flutter emulators --launch <id>
flutter run -d emulator-5554
```

Sign in (test creds a@a.com / 123456), add a guardian (Contacts tab) if none.

- [ ] **Step 2: Enable the toggle, grant permissions, background the app**

On the Track tab flip "Shake to SOS" ON → grant the three permission prompts. Confirm the persistent notification **"Lumi is protecting you"** appears. Then:

```bash
adb shell input keyevent KEYCODE_HOME
```

- [ ] **Step 3: Synthesize two shakes**

```bash
for i in 1 2; do
  adb emu sensor set acceleration 30:0:9.8;  sleep 0.15
  adb emu sensor set acceleration -30:0:9.8; sleep 0.15
  adb emu sensor set acceleration 30:0:9.8;  sleep 0.15
  adb emu sensor set acceleration 0:0:9.8;   sleep 0.5
done
```

Expected: heads-up notification **"Shake detected — Alerting your guardians in 5…"** ticking down, with the **"I'm safe — cancel"** button, phone vibrating per tick.

- [ ] **Step 4: Exercise all three outcomes**

1. **Cancel:** tap "I'm safe — cancel" during the countdown → notification returns to "Lumi is protecting you", nothing sent.
2. **Send:** re-run the shake script, let it reach zero → result notification; verify the SMS attempt in logs: `adb logcat -d | grep -i -E "sms|telephony" | tail -20`. If the call was blocked, the notification says "Tap to open Lumi and call your first guardian." — tap it and confirm the dialer opens with the guardian's number.
3. **Toggle OFF:** flip the switch off → persistent notification disappears; re-run the shake script → nothing happens.
4. **Foreground no-double:** open the app, shake script again → the in-app full-screen countdown appears (existing behaviour), **no** notification countdown in parallel.

- [ ] **Step 5: Record what you saw**

Report PASS/FAIL per outcome with screenshots/logcat snippets. Any deviation is a finding, not something to route around.

---

## Self-review notes (done at planning time)

- Spec coverage: toggle-tied service ✓ (T3/T4), heads-up countdown + cancel ✓ (T1/T3), silent SMS ✓ (T2), best-effort call + tap-to-call fallback ✓ (T2/T3/T4), no-guardians notification ✓ (T1/T3) — foreground half already shipped in b781c46, permissions ✓ (T3 manifest / T5 runtime), iOS untouched ✓ (Platform guards), unit tests for the state machine ✓ (T1), emulator e2e ✓ (T6).
- Type consistency: `ShakeGuardCore` callback names (T1) match the handler wiring (T3); `BackgroundSendResult.smsFailures/callBlocked` (T2) match `_sendAlert` (T3); `ShakeGuardService` statics (T3) match call sites (T4).
- Known risk, called out in T3: `flutter_foreground_task` signature drift between majors — `flutter analyze` is the arbiter.
