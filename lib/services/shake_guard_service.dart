// ─────────────────────────────────────────────────────────────────────────────
//  Lumi · Shake-guard foreground service (Android only)
//  Hosts ShakeGuardCore + a ShakeDetector in a background isolate so shaking
//  works when the app is backgrounded/swiped away. The Track-page toggle is
//  the master switch (NavBarPage starts/stops us). All countdown rules live
//  in ShakeGuardCore; this file only maps callbacks to notifications.
//  See docs/superpowers/specs/2026-07-04-background-shake-to-sos-design.md
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shake/shake.dart';

import 'checkin_prefs.dart';
import 'checkin_timer_core.dart';
import 'emergency_alert.dart';
import 'shake_guard_core.dart';
import 'shake_prefs.dart';

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

  /// The runtime permissions background SOS needs. The Track-page toggle
  /// requests them; this check keeps a default-ON pref from starting a
  /// service that can't notify or send. Location is required because the
  /// manifest declares the location service type — starting without it
  /// throws on Android 14+, and the SOS SMS would say "location
  /// unavailable" anyway.
  static Future<bool> hasRequiredPermissions() async =>
      (await Future.wait([
        Permission.notification.status,
        Permission.sms.status,
        Permission.phone.status,
        Permission.locationWhenInUse.status,
      ]))
          .every((s) => s.isGranted);

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

  /// Pushes a live sensitivity change to the running service (no-op if it
  /// isn't running). NavBarPage calls this from the same place it reacts to
  /// ShakePrefs.sensitivity changes for the in-app detector.
  static void notifySensitivity(ShakeSensitivity level) =>
      FlutterForegroundTask.sendDataToTask('sensitivity:${level.name}');

  /// Tells the running service to (re)start its check-in countdown from
  /// whatever CheckInPrefs currently holds on disk (no-op if the service
  /// isn't running). The note's free text travels via CheckInPrefs, not
  /// this message, the same way ShakePrefs already does for `onStart`.
  static void notifyCheckInStart() =>
      FlutterForegroundTask.sendDataToTask('checkin_start');

  static void notifyCheckInCancel() =>
      FlutterForegroundTask.sendDataToTask('checkin_cancel');
}

class _ShakeGuardTaskHandler extends TaskHandler {
  ShakeDetector? _detector;
  ShakeGuardCore? _core;
  CheckInTimerCore? _checkIn;
  // Started on the countdown's first tick so the 5 seconds double as GPS
  // warm-up — a fresh fix is usually ready by the time the SMS is built.
  Future<String?>? _coordsPrefetch;

  static const _cancelButtonId = 'cancel_sos';
  static const _cancelButton =
      NotificationButton(id: _cancelButtonId, text: "I'm safe — cancel");

  static const _cancelCheckInButtonId = 'cancel_checkin';
  static const _cancelCheckInButton = NotificationButton(
      id: _cancelCheckInButtonId, text: "I'm safe — cancel");

  void _idleNotification() {
    FlutterForegroundTask.updateService(
      notificationTitle: 'Lumi is protecting you',
      notificationText: 'Shake your phone twice to start an SOS.',
      notificationButtons: const [],
    );
  }

  Future<void> _sendAlert({String? note}) async {
    try {
      final coords = _coordsPrefetch;
      _coordsPrefetch = null;
      final result = await EmergencyAlert.sendBackground(
          coordsFuture: coords, note: note);
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
    } catch (_) {
      FlutterForegroundTask.updateService(
        notificationTitle: 'Alert may have failed',
        notificationText: 'Open Lumi and use the SOS button.',
        notificationButtons: const [],
      );
    }
  }

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
      // _sendAlert wrote the result notification already; clearing here is
      // what stops a completed run's stale endTime from re-firing a
      // duplicate alert on the next service restart.
      onSent: () => CheckInPrefs.clear(),
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

  void _startDetector(double threshold) {
    _detector = ShakeDetector.autoStart(
      minimumShakeCount: 2,
      shakeThresholdGravity: threshold,
      onPhoneShake: (_) => _core?.shakeDetected(),
    );
  }

  @override
  void onReceiveData(Object data) {
    if (data == 'app_resumed') _core?.appResumed();
    if (data == 'app_paused') _core?.appPaused();
    if (data is String && data.startsWith('sensitivity:')) {
      final level = ShakeSensitivity.values.byName(data.substring(12));
      _detector?.stopListening();
      _startDetector(thresholdFor(level));
    }
    if (data == 'checkin_start') _startCheckIn(++_checkInEpoch);
    if (data == 'checkin_cancel') {
      _checkInEpoch++;
      _checkIn?.cancel();
    }
  }

  // Bumped on every checkin_start/checkin_cancel IPC. _startCheckIn has an
  // async gap at its prefs load; a cancel arriving in that gap would no-op
  // (the core isn't running yet) and then the delayed start would arm the
  // timer anyway, losing the cancel. Re-checking the epoch after the await
  // makes such a superseded start bail out instead.
  int _checkInEpoch = 0;

  Future<void> _startCheckIn(int epoch) async {
    await CheckInPrefs.load(); // pick up the endTime/note just persisted
    if (epoch != _checkInEpoch) return; // superseded by a newer start/cancel
    final end = CheckInPrefs.endTime.value;
    if (end != null) _checkIn?.start(end);
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id == _cancelButtonId) _core?.cancel();
    if (id == _cancelCheckInButtonId) _checkIn?.cancel();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {} // eventAction: nothing()

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    _detector?.stopListening();
    _core?.dispose();
    _checkIn?.dispose();
  }
}
