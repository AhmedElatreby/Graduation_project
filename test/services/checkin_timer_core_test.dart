// The check-in timer state machine: counts down, enters a grace period at
// zero, sends exactly once if the grace period also elapses, and cancel
// stops either phase without ever sending.
import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safetyproject/services/checkin_timer_core.dart';

class _Probe {
  int sends = 0, cancels = 0, sents = 0;
  final ticks = <Duration>[];
  final graceTicks = <int>[];

  late CheckInTimerCore core;

  _Probe({int graceSeconds = 3}) {
    core = CheckInTimerCore(
      send: () async => sends++,
      onTick: ticks.add,
      onGraceTick: graceTicks.add,
      onCancelled: () => cancels++,
      onSent: () => sents++,
      graceSeconds: graceSeconds,
    );
  }
}

void main() {
  test('counts down every second while above zero', () {
    fakeAsync((async) {
      final p = _Probe();
      p.core.start(clock.now().add(const Duration(seconds: 3)));
      expect(p.ticks, [const Duration(seconds: 3)]);

      async.elapse(const Duration(seconds: 1));
      expect(p.ticks.last, const Duration(seconds: 2));

      async.elapse(const Duration(seconds: 1));
      expect(p.ticks.last, const Duration(seconds: 1));

      expect(p.graceTicks, isEmpty);
      expect(p.sends, 0);
    });
  });

  test('reaching zero enters the grace period and sends once it also elapses',
      () {
    fakeAsync((async) {
      final p = _Probe(graceSeconds: 3);
      p.core.start(clock.now().add(const Duration(seconds: 2)));

      async.elapse(const Duration(seconds: 2));
      expect(p.graceTicks, [3]);
      expect(p.sends, 0);

      async.elapse(const Duration(seconds: 1));
      expect(p.graceTicks, [3, 2]);

      async.elapse(const Duration(seconds: 1));
      expect(p.graceTicks, [3, 2, 1]);
      expect(p.sends, 0);

      async.elapse(const Duration(seconds: 1));
      expect(p.sends, 1);
      expect(p.sents, 1);

      // Never double-fires even well past the deadline.
      async.elapse(const Duration(seconds: 10));
      expect(p.sends, 1);
    });
  });

  test('cancel during the main countdown stops it and never sends', () {
    fakeAsync((async) {
      final p = _Probe();
      p.core.start(clock.now().add(const Duration(seconds: 5)));
      async.elapse(const Duration(seconds: 2));

      p.core.cancel();
      expect(p.cancels, 1);

      async.elapse(const Duration(seconds: 10));
      expect(p.sends, 0);
      expect(p.graceTicks, isEmpty);
    });
  });

  test('cancel during the grace period stops it and never sends', () {
    fakeAsync((async) {
      final p = _Probe(graceSeconds: 3);
      p.core.start(clock.now().add(const Duration(seconds: 1)));
      async.elapse(const Duration(seconds: 1));
      expect(p.graceTicks, isNotEmpty);

      p.core.cancel();
      expect(p.cancels, 1);

      async.elapse(const Duration(seconds: 10));
      expect(p.sends, 0);
    });
  });

  test('cancel is a no-op once already sent', () {
    fakeAsync((async) {
      final p = _Probe(graceSeconds: 1);
      p.core.start(clock.now().add(const Duration(seconds: 1)));
      async.elapse(const Duration(seconds: 2));
      expect(p.sends, 1);

      p.core.cancel(); // must not call onCancelled after a send
      expect(p.cancels, 0);
    });
  });

  test(
      'starting with an endTime already past the main duration goes '
      'straight into the grace period', () {
    fakeAsync((async) {
      final p = _Probe(graceSeconds: 5);
      // 2 seconds already elapsed past the main deadline before start() is
      // even called (e.g. the service restarted late after an OS kill).
      p.core.start(clock.now().subtract(const Duration(seconds: 2)));

      expect(p.ticks, isEmpty); // never shows the main countdown
      expect(p.graceTicks, [3]); // 5s grace minus the 2s already elapsed

      async.elapse(const Duration(seconds: 3));
      expect(p.sends, 1);
    });
  });

  test(
      'starting with an endTime past both the duration and the grace '
      'period sends immediately', () {
    fakeAsync((async) {
      final p = _Probe(graceSeconds: 5);
      p.core.start(clock.now().subtract(const Duration(seconds: 10)));
      async.flushMicrotasks(); // let the fire-and-forget send()/onSent() run

      expect(p.sends, 1);
      expect(p.sents, 1);
      expect(p.ticks, isEmpty);
      expect(p.graceTicks, isEmpty);
    });
  });

  test(
      'an immediately-elapsed start leaves no live periodic timer behind '
      '(regression: the send branch used to cancel a stale _timer '
      'reference, leaking the one start() had just created)', () {
    fakeAsync((async) {
      final p = _Probe(graceSeconds: 5);
      p.core.start(clock.now().subtract(const Duration(seconds: 100)));
      async.flushMicrotasks();

      expect(p.sends, 1);
      expect(p.sents, 1);
      expect(async.periodicTimerCount, 0);
    });
  });

  test(
      'a restart while the previous run\'s send() is still in flight does '
      'not let its onSent() fire into the new run '
      '(regression: _running went false before awaiting send(), so a '
      'restart could begin before the old send() resolved)', () {
    fakeAsync((async) {
      var sendCalls = 0;
      final sents = <int>[];

      final core = CheckInTimerCore(
        send: () async {
          sendCalls++;
          // Simulates a slow network call: still unresolved by the time a
          // restart happens below.
          await Future.delayed(const Duration(seconds: 10));
        },
        onTick: (_) {},
        onGraceTick: (_) {},
        onCancelled: () {},
        onSent: () => sents.add(sendCalls),
        graceSeconds: 2,
      );

      // Run A: main 1s + grace 2s -> send() invoked at t=3, but it won't
      // resolve until t=13.
      core.start(clock.now().add(const Duration(seconds: 1)));
      async.elapse(const Duration(seconds: 3));
      expect(sendCalls, 1);
      expect(sents, isEmpty);

      // Run B starts before A's send() has resolved.
      core.start(clock.now().add(const Duration(seconds: 2)));

      // Elapse past t=13, when A's send() resolves: its onSent() must be
      // suppressed because the generation has moved on to run B.
      async.elapse(const Duration(seconds: 10));
      expect(sents, isEmpty);

      // Run B reaches its own deadline (main 2s + grace 2s -> send() at
      // t=7) and its send() resolves normally 10s later, at t=17.
      async.elapse(const Duration(seconds: 4));
      expect(sents, [2]);
    });
  });
}
