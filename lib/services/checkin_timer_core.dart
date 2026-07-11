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

  // Bumped on every start()/cancel() so an in-flight send() from a run that
  // has since been superseded (restarted or cancelled) can recognize it's
  // stale and skip firing onSent() into whatever run is current by the time
  // it resolves.
  int _generation = 0;

  bool get isRunning => _running;

  /// Starts (or resumes, after a restart) counting down to [endTime]. If
  /// [endTime] is already in the past, evaluates straight into the grace
  /// phase (or straight to sending, if the grace period has also already
  /// elapsed) instead of it being a special case — a Duration in the past
  /// behaves exactly like "zero remaining" to the phase logic below.
  ///
  /// The periodic timer is created *before* the initial _evaluate() call so
  /// that if that first evaluation already lands on the send branch (endTime
  /// is already past both deadlines), _evaluate() cancels the very timer
  /// start() just created rather than a stale reference — otherwise that
  /// timer would tick forever as a no-op, leaking for the lifetime of the
  /// process.
  void start(DateTime endTime) {
    _timer?.cancel();
    _endTime = endTime;
    _running = true;
    _generation++;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _evaluate());
    _evaluate();
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

    // Capture the generation this send() belongs to before awaiting: if a
    // restart happens while send() is in flight, _generation moves on and
    // this stale run must not fire onSent() into the new one.
    final generation = _generation;
    _timer?.cancel();
    _running = false;
    try {
      await send();
    } catch (_) {
      // Swallow: still reset and call onSent to unblock the UI/notification.
    }
    if (generation == _generation) {
      onSent();
    }
  }

  void cancel() {
    if (!_running) return;
    _timer?.cancel();
    _running = false;
    _generation++;
    onCancelled();
  }

  void dispose() {
    _timer?.cancel();
    _running = false;
  }
}
