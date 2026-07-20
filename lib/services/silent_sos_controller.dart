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

  final ValueNotifier<SilentSosPhase> phase =
      ValueNotifier(SilentSosPhase.idle);

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
