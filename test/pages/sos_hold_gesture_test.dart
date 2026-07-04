// Regression tests for the SOS button's hold-to-send gesture (issue #5).
//
// Contract: press and hold the button -- a ring fills over 1400ms. Lifting
// the finger before the ring is full cancels (does nothing, shows a "keep
// holding" hint). Sliding the finger off the button before releasing also
// cancels. Only lifting the finger *while the ring is full* fires the alert.
//
// The alert-firing path (_triggerFullAlert -> Firestore + SMS/call plugins)
// is intentionally not exercised here -- that would need Firestore, SMS, and
// phone-dialer plugins mocked, which is its own large surface. Instead we
// assert the ring reaches "RELEASE TO SEND" without ever calling gesture.up()
// at that point, matching how this was verified by hand against a real
// simulator (a completed hold was tested there; only the label/state
// transitions are covered here).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safetyproject/pages/sos.dart';

import '../test_helpers.dart';

Future<void> _pumpSosPage(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(
    home: Scaffold(body: SosPage(userName: 'Tester')),
  ));
  await settleWithRealAsync(tester);
}

void main() {
  configureTestEnvironment();

  group('SOS hold-to-send gesture', () {
    testWidgets('releasing before the ring fills cancels, does not send',
        (tester) async {
      await _pumpSosPage(tester);

      final center = tester.getCenter(find.text('SOS'));
      final gesture = await tester.startGesture(center);
      // A ticker's first pumped frame only records its start time (elapsed
      // 0), so pump once to start the clock and once more to advance it.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700)); // ~half of 1400ms

      expect(find.text('KEEP HOLDING'), findsOneWidget);

      await gesture.up();
      await tester.pump();

      expect(find.text('Keep holding until the ring fills, then release.'),
          findsOneWidget);

      // The ring reverses from ~50% back to 0 -- same two-pump dance for the
      // reverse ticker, then check the label reverts to the idle state.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text('HOLD TO ALERT'), findsOneWidget);
    });

    testWidgets('sliding off the button cancels the hold', (tester) async {
      await _pumpSosPage(tester);

      final center = tester.getCenter(find.text('SOS'));
      final gesture = await tester.startGesture(center);
      await tester.pump(const Duration(milliseconds: 300));

      // Move well outside the 184x184 button (plus its hit-test margin).
      await gesture.moveTo(center + const Offset(300, 300));
      await tester.pump();

      expect(find.text('Cancelled — you slid off the button.'), findsOneWidget);

      await gesture.up();
      await tester.pump();
    });

    testWidgets('holding for the full 1400ms reaches release-to-send',
        (tester) async {
      await _pumpSosPage(tester);

      final center = tester.getCenter(find.text('SOS'));
      final gesture = await tester.startGesture(center);
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.text('RELEASE TO SEND'), findsOneWidget);

      // Release via cancel (not up()) so the full-alert path -- which needs
      // Firestore/SMS/phone plugins this suite doesn't mock -- never fires.
      await gesture.cancel();
    });
  });
}
