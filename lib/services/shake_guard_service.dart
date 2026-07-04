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

  /// The three runtime permissions background SOS needs. The Track-page
  /// toggle requests them; this check keeps a default-ON pref from starting
  /// a service that can't notify or send.
  static Future<bool> hasRequiredPermissions() async =>
      (await Future.wait([
        Permission.notification.status,
        Permission.sms.status,
        Permission.phone.status,
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
