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
