// test/services/silent_sos_controller_test.dart
// The silent-trigger pattern matcher: 3 volume-down presses within the
// window arms; the same pattern again during the grace period cancels;
// the grace period elapsing sends exactly once. Pure Dart, fake_async +
// clock so every timing rule is provable (same technique CheckInTimerCore
// uses).
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

  test(
      'repeating the pattern during grace cancels and the grace timer '
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
