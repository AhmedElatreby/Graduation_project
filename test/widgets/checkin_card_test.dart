// The check-in card never runs its own CheckInTimerCore — what it shows is a
// pure function of CheckInPrefs.endTime and the grace constant. These unit
// tests pin that function; the widget tests (added in later tasks) pin the
// three visual states built on top of it.
import 'package:flutter_test/flutter_test.dart';

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
}
