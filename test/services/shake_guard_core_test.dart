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
