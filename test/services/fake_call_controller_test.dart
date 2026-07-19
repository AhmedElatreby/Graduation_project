// test/services/fake_call_controller_test.dart
// The fake call's phase machine: idle → scheduled → ringing → inCall → idle.
// Pure Dart so every timing rule is provable with fake_async.
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safetyproject/services/fake_call_controller.dart';

void main() {
  test('schedule counts down and rings exactly once at zero', () {
    fakeAsync((async) {
      final c = FakeCallController();
      var rings = 0;
      c.onRing = () => rings++;

      c.schedule(const Duration(seconds: 10));
      expect(c.phase.value, FakeCallPhase.scheduled);
      expect(c.remaining.value, const Duration(seconds: 10));

      async.elapse(const Duration(seconds: 9));
      expect(c.phase.value, FakeCallPhase.scheduled);
      expect(c.remaining.value, const Duration(seconds: 1));
      expect(rings, 0);

      async.elapse(const Duration(seconds: 1));
      expect(c.phase.value, FakeCallPhase.ringing);
      expect(rings, 1);

      async.elapse(const Duration(seconds: 30));
      expect(rings, 1); // no re-ring
      c.end();
    });
  });

  test('schedule(Duration.zero) rings immediately', () {
    fakeAsync((async) {
      final c = FakeCallController();
      var rings = 0;
      c.onRing = () => rings++;
      c.schedule(Duration.zero);
      expect(c.phase.value, FakeCallPhase.ringing);
      expect(rings, 1);
      c.end();
    });
  });

  test('cancel during the delay prevents the ring', () {
    fakeAsync((async) {
      final c = FakeCallController();
      var rings = 0;
      c.onRing = () => rings++;
      c.schedule(const Duration(seconds: 10));
      async.elapse(const Duration(seconds: 5));
      c.cancel();
      expect(c.phase.value, FakeCallPhase.idle);
      async.elapse(const Duration(minutes: 1));
      expect(rings, 0);
    });
  });

  test('rescheduling replaces the pending call', () {
    fakeAsync((async) {
      final c = FakeCallController();
      var rings = 0;
      c.onRing = () => rings++;
      c.schedule(const Duration(seconds: 10));
      async.elapse(const Duration(seconds: 5));
      c.schedule(const Duration(seconds: 30)); // replaces
      async.elapse(const Duration(seconds: 10));
      expect(rings, 0); // old timer must not fire
      expect(c.remaining.value, const Duration(seconds: 20));
      async.elapse(const Duration(seconds: 20));
      expect(rings, 1);
      c.end();
    });
  });

  test('answer moves ringing → inCall; end returns to idle', () {
    fakeAsync((async) {
      final c = FakeCallController();
      c.onRing = () {};
      c.schedule(Duration.zero);
      c.answer();
      expect(c.phase.value, FakeCallPhase.inCall);
      c.end();
      expect(c.phase.value, FakeCallPhase.idle);
    });
  });
}
