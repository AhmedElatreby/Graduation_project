// The check-in card never runs its own CheckInTimerCore — what it shows is a
// pure function of CheckInPrefs.endTime and the grace constant. These unit
// tests pin that function; the widget tests (added in later tasks) pin the
// three visual states built on top of it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safetyproject/contact/personal_emergency_contacts_model.dart';
import 'package:safetyproject/database/db_helper.dart';
import 'package:safetyproject/services/checkin_prefs.dart';
import 'package:safetyproject/services/checkin_timer_core.dart';
import 'package:safetyproject/widgets/checkin_card.dart';

import '../test_helpers.dart';

void main() {
  configureTestEnvironment();

  group('phase computation', () {
    final now = DateTime(2026, 7, 12, 20, 0, 0);

    test('null endTime is idle', () {
      expect(checkInPhase(null, now), CheckInPhase.idle);
    });

    test('future endTime is running', () {
      expect(checkInPhase(now.add(const Duration(minutes: 5)), now),
          CheckInPhase.running);
    });

    test('past endTime is grace, even past the grace window (the service '
        'resolves it; the card just keeps showing the warning)', () {
      expect(checkInPhase(now.subtract(const Duration(seconds: 1)), now),
          CheckInPhase.grace);
      expect(checkInPhase(now.subtract(const Duration(minutes: 10)), now),
          CheckInPhase.grace);
    });

    test('an endTime exactly now is grace (not running)', () {
      expect(checkInPhase(now, now), CheckInPhase.grace);
    });
  });

  group('grace seconds left', () {
    final now = DateTime(2026, 7, 12, 20, 0, 0);

    test('counts down from defaultGraceSeconds and clamps at 0', () {
      expect(
        checkInGraceSecondsLeft(now, now),
        CheckInTimerCore.defaultGraceSeconds,
      );
      expect(
        checkInGraceSecondsLeft(now.subtract(const Duration(seconds: 15)), now),
        CheckInTimerCore.defaultGraceSeconds - 15,
      );
      expect(
        checkInGraceSecondsLeft(now.subtract(const Duration(minutes: 5)), now),
        0,
      );
    });

    test('rounds partial seconds up, matching CheckInTimerCore.onGraceTick '
        'ceil-ing so card and notification never disagree by a second', () {
      expect(
        checkInGraceSecondsLeft(
            now.subtract(const Duration(milliseconds: 500)), now),
        CheckInTimerCore.defaultGraceSeconds, // 59.5 → 60
      );
    });
  });

  group('formatRemaining', () {
    test('minutes and seconds', () {
      expect(formatRemaining(const Duration(minutes: 12, seconds: 34)), '12:34');
      expect(formatRemaining(const Duration(seconds: 59)), '0:59');
      expect(formatRemaining(const Duration(minutes: 60)), '1:00:00');
      expect(formatRemaining(const Duration(hours: 1, seconds: 5)), '1:00:05');
    });

    test('never goes negative', () {
      expect(formatRemaining(const Duration(seconds: -3)), '0:00');
    });
  });

  Future<void> pumpCard(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: CheckInCard())),
    ));
    await tester.pump();
  }

  group('CheckInCard widget', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      CheckInPrefs.endTime.value = null;
      CheckInPrefs.note.value = null;
    });

    testWidgets('idle state shows chips, note field and Start', (tester) async {
      await pumpCard(tester);

      expect(find.text('Check-in timer'), findsOneWidget);
      expect(find.text("Alert your guardians if you don't check in"),
          findsOneWidget);
      for (final label in ['10 min', '20 min', '30 min', '60 min', 'Custom…']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('Start'), findsOneWidget);
    });

    // NOTE: must run before any test seeds a contact — DBHelper's backing
    // store is shared across tests in this file (same pattern as
    // emergency_alert_test.dart relies on).
    testWidgets('Start with no guardians shows the prompt and starts nothing',
        (tester) async {
      await pumpCard(tester);

      await tester.tap(find.text('Start'));
      await settleWithRealAsync(tester);

      expect(find.text('Add guardians first — no alert sent'), findsOneWidget);
      expect(CheckInPrefs.endTime.value, isNull);
    });

    testWidgets('Start with a guardian persists endTime + note and shows the '
        'running state', (tester) async {
      await tester.runAsync(
          () => DBHelper().add(PersonalEmergency('Sara', '01000000000')));
      await pumpCard(tester);

      await tester.tap(find.text('20 min'));
      await tester.pump();
      await tester.enterText(
          find.byType(TextField), 'walking home from the station');
      final before = DateTime.now();
      await tester.tap(find.text('Start'));
      await settleWithRealAsync(tester);

      final end = CheckInPrefs.endTime.value;
      expect(end, isNotNull);
      final delta = end!.difference(before) - const Duration(minutes: 20);
      expect(delta.inSeconds.abs() <= 5, isTrue,
          reason: 'endTime should be ~20 min out, got $end');
      expect(CheckInPrefs.note.value, 'walking home from the station');
      expect(find.textContaining('Checking in in'), findsOneWidget);
      expect(find.text('walking home from the station'), findsOneWidget);
      expect(find.text("I'm safe — cancel"), findsOneWidget);

      // Leave no running timer behind for the next test.
      await tester.runAsync(CheckInPrefs.clear);
      await tester.pump();
    });

    testWidgets('countdown ticks down while running', (tester) async {
      await tester
          .runAsync(() => CheckInPrefs.start(const Duration(minutes: 10)));
      await pumpCard(tester);

      expect(find.textContaining('Checking in in 9:'), findsOneWidget);
      // Two ticks of the card's 1s repaint timer — the shown remaining time
      // must move (DateTime.now() is real even under fake-async pumping, so
      // pump() here only fires the periodic timer; the ~0ms of real time
      // that has passed is enough for a strictly smaller remaining string
      // not to be guaranteed — instead cross a whole-second boundary with
      // runAsync, which advances the real clock).
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1100)));
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('Checking in in 9:'), findsOneWidget);

      await tester.runAsync(CheckInPrefs.clear);
      await tester.pump();
    });

    testWidgets('cancel returns to idle and clears prefs', (tester) async {
      await tester.runAsync(() =>
          CheckInPrefs.start(const Duration(minutes: 10), note: 'note'));
      await pumpCard(tester);
      expect(find.text("I'm safe — cancel"), findsOneWidget);

      await tester.tap(find.text("I'm safe — cancel"));
      await settleWithRealAsync(tester);

      expect(CheckInPrefs.endTime.value, isNull);
      expect(CheckInPrefs.note.value, isNull);
      expect(find.text('Start'), findsOneWidget); // idle again
    });

    testWidgets('a just-expired endTime renders the grace warning',
        (tester) async {
      CheckInPrefs.endTime.value =
          DateTime.now().subtract(const Duration(seconds: 10));
      await pumpCard(tester);

      expect(find.text('Check-in missed'), findsOneWidget);
      expect(find.textContaining('alerting your guardians in'), findsOneWidget);
      expect(find.text("I'm safe — cancel"), findsOneWidget);

      CheckInPrefs.endTime.value = null;
      await tester.pump();
    });
  });
}
