// lib/services/fake_call_controller.dart
// ─────────────────────────────────────────────────────────────────────────────
//  Lumi · Fake-call phase machine
//  Owns the staged call's delay timer and phase. Deliberately NOT persisted:
//  an in-app cosmetic feature dies with the app — nothing survives a kill,
//  nothing rings later. App-wide singleton so tab switches don't lose a
//  pending call; a public constructor exists for tests.
//  See docs/superpowers/specs/2026-07-19-fake-call-design.md
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';

import 'package:flutter/foundation.dart';

enum FakeCallPhase { idle, scheduled, ringing, inCall }

class FakeCallController {
  FakeCallController();

  static final FakeCallController instance = FakeCallController();

  final ValueNotifier<FakeCallPhase> phase = ValueNotifier(FakeCallPhase.idle);

  /// Time left until the ring; meaningful only while [phase] is `scheduled`.
  final ValueNotifier<Duration> remaining = ValueNotifier(Duration.zero);

  /// Set by the SOS page: navigate to the incoming-call screen.
  void Function()? onRing;

  Timer? _timer;

  /// Stage the call. Scheduling while one is already pending replaces it.
  void schedule(Duration delay) {
    _timer?.cancel();
    if (delay <= Duration.zero) {
      _ring();
      return;
    }
    remaining.value = delay;
    phase.value = FakeCallPhase.scheduled;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final left = remaining.value - const Duration(seconds: 1);
      if (left <= Duration.zero) {
        _timer?.cancel();
        _ring();
      } else {
        remaining.value = left;
      }
    });
  }

  void _ring() {
    phase.value = FakeCallPhase.ringing;
    onRing?.call();
  }

  /// Abort a scheduled call before it rings.
  void cancel() {
    _timer?.cancel();
    _timer = null;
    phase.value = FakeCallPhase.idle;
  }

  void answer() => phase.value = FakeCallPhase.inCall;

  /// Decline or hang up — either way the act is over.
  void end() {
    _timer?.cancel();
    _timer = null;
    phase.value = FakeCallPhase.idle;
  }
}
