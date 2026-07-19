// test/pages/fake_call_page_test.dart
// The staged call screens. Decline ends the act; Answer runs an in-call
// screen with a live timer. Ring sound starts on show, stops on any exit.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safetyproject/pages/fake_call_page.dart';
import 'package:safetyproject/services/fake_call_controller.dart';
import 'package:safetyproject/services/fake_call_prefs.dart';
import 'package:safetyproject/services/fake_call_sounds.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RecordingSounds implements FakeCallSounds {
  int starts = 0;
  int stops = 0;
  @override
  Future<void> start() async => starts++;
  @override
  Future<void> stop() async => stops++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeCallController controller;
  late _RecordingSounds sounds;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await FakeCallPrefs.load();
    controller = FakeCallController();
    controller.phase.value = FakeCallPhase.ringing;
    sounds = _RecordingSounds();
  });

  Future<void> pumpIncoming(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => IncomingCallPage(
                      sounds: sounds, controller: controller))),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows caller identity and starts the ring sound',
      (tester) async {
    await pumpIncoming(tester);
    expect(find.text('Mom'), findsOneWidget);
    expect(find.text('07700 900123'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);
    expect(find.text('Answer'), findsOneWidget);
    expect(sounds.starts, 1);
  });

  testWidgets('Decline stops the sound, ends the act, pops back',
      (tester) async {
    await pumpIncoming(tester);
    await tester.tap(find.text('Decline'));
    await tester.pumpAndSettle();
    expect(find.text('go'), findsOneWidget); // back on the host screen
    expect(sounds.stops, greaterThanOrEqualTo(1));
    expect(controller.phase.value, FakeCallPhase.idle);
  });

  testWidgets('Answer stops the ring and shows a running in-call timer',
      (tester) async {
    await pumpIncoming(tester);
    await tester.tap(find.text('Answer'));
    await tester.pumpAndSettle();
    expect(controller.phase.value, FakeCallPhase.inCall);
    expect(sounds.stops, greaterThanOrEqualTo(1));
    expect(find.text('0:00'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    expect(find.text('0:02'), findsOneWidget);

    // Hang up: back to the host screen, act over.
    await tester.tap(find.byIcon(Icons.call_end));
    await tester.pumpAndSettle();
    expect(find.text('go'), findsOneWidget);
    expect(controller.phase.value, FakeCallPhase.idle);
  });
}
