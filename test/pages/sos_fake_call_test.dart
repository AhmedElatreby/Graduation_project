// The SOS page's fake-call entry: quick action opens the sheet; Ring me
// schedules; the pill counts down and cancels; ring navigates to the
// incoming-call screen.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safetyproject/pages/fake_call_page.dart';
import 'package:safetyproject/pages/sos.dart';
import 'package:safetyproject/services/fake_call_controller.dart';
import 'package:safetyproject/services/fake_call_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

// SosPage's background pulse animation runs on a repeating AnimationController
// (`..repeat()`), so it never stops scheduling frames -- tester.pumpAndSettle()
// would hang/timeout on this page (see sos_hold_gesture_test.dart, which hits
// the same issue and avoids pumpAndSettle for the same reason). Pump a bounded
// number of frames instead, enough for one-shot transitions (bottom sheet
// open/close, page push) to finish.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  configureTestEnvironment();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await FakeCallPrefs.load();
    FakeCallController.instance.end(); // reset shared singleton between tests
  });

  Future<void> pumpSos(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SosPage()));
    // SosPage kicks off real async work in initState (a location-permission
    // request and DBHelper.getContacts() over sqflite_common_ffi) that a
    // fake-async pumpAndSettle() can't progress -- let real async run first.
    await settleWithRealAsync(tester);
  }

  testWidgets('Fake Call quick action opens the sheet with delay chips',
      (tester) async {
    await pumpSos(tester);
    await tester.tap(find.text('Fake Call'));
    await _settle(tester);
    expect(find.text('Fake incoming call'), findsOneWidget);
    for (final label in ['Now', '10s', '30s', '1 min']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Ring me'), findsOneWidget);
  });

  testWidgets('Ring me with the default 10s delay schedules and shows the pill',
      (tester) async {
    await pumpSos(tester);
    await tester.tap(find.text('Fake Call'));
    await _settle(tester);
    await tester.tap(find.text('Ring me'));
    await _settle(tester);

    expect(FakeCallController.instance.phase.value, FakeCallPhase.scheduled);
    expect(find.textContaining('tap to cancel'), findsOneWidget);

    // Tapping the pill cancels.
    await tester.tap(find.textContaining('tap to cancel'));
    await _settle(tester);
    expect(FakeCallController.instance.phase.value, FakeCallPhase.idle);
    expect(find.textContaining('tap to cancel'), findsNothing);
  });

  testWidgets('editing the caller in the sheet persists via FakeCallPrefs',
      (tester) async {
    await pumpSos(tester);
    await tester.tap(find.text('Fake Call'));
    await _settle(tester);

    await tester.enterText(find.widgetWithText(TextField, 'Mom'), 'Work');
    await tester.enterText(
        find.widgetWithText(TextField, '07700 900123'), '020 7946 0000');
    await tester.tap(find.text('Ring me'));
    await _settle(tester);

    expect(FakeCallPrefs.callerName.value, 'Work');
    expect(FakeCallPrefs.callerNumber.value, '020 7946 0000');
    FakeCallController.instance.cancel();
  });

  testWidgets('Now delay rings immediately: IncomingCallPage is pushed',
      (tester) async {
    await pumpSos(tester);
    await tester.tap(find.text('Fake Call'));
    await _settle(tester);
    await tester.tap(find.text('Now'));
    await tester.tap(find.text('Ring me'));
    await _settle(tester);
    expect(find.byType(IncomingCallPage), findsOneWidget);
    FakeCallController.instance.end();
  });
}
