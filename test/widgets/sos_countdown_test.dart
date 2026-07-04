// Tests for the shake-to-SOS countdown overlay: cancelling must never send,
// and reaching zero must send exactly once.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safetyproject/widgets/sos_countdown.dart';

import '../test_helpers.dart';

void main() {
  configureTestEnvironment();

  Future<void> pumpHost(
    WidgetTester tester, {
    required Future<void> Function() onSend,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showSosCountdown(context, onSend: onSend),
              child: const Text('trigger'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('trigger'));
    await tester.pump(); // dialog route animation start
    await tester.pump(const Duration(milliseconds: 300)); // settle
  }

  testWidgets('cancelling stops the countdown and never sends',
      (tester) async {
    var sends = 0;
    await pumpHost(tester, onSend: () async => sends++);

    expect(find.text('5'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    expect(find.text('3'), findsOneWidget);

    await tester.tap(find.text("I'm safe — cancel"));
    await tester.pumpAndSettle();

    expect(find.text('3'), findsNothing); // dialog gone
    expect(sends, 0);

    // Even well after the original deadline, nothing fires.
    await tester.pump(const Duration(seconds: 10));
    expect(sends, 0);
  });

  testWidgets('reaching zero sends exactly once', (tester) async {
    var sends = 0;
    await pumpHost(tester, onSend: () async => sends++);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(sends, 1);
    expect(find.text("I'm safe — cancel"), findsNothing);

    await tester.pump(const Duration(seconds: 5));
    expect(sends, 1); // no double-fire
  });
}
