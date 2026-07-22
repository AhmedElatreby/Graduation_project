// AlertHistoryPage: renders seeded entries newest first, the empty state
// with none, pull-to-refresh re-queries, and Clear history empties both the
// list and the underlying table.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safetyproject/database/alert_history_db.dart';
import 'package:safetyproject/pages/alert_history_page.dart';

import '../test_helpers.dart';

void main() {
  configureTestEnvironment();

  setUp(() async {
    await AlertHistoryDb().clear();
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: AlertHistoryPage()),
    ));
    await settleWithRealAsync(tester);
  }

  testWidgets('shows the empty state with no entries', (tester) async {
    await pumpPage(tester);
    expect(find.text('No alerts yet'), findsOneWidget);
  });

  testWidgets(
      'renders seeded entries newest first with trigger, outcome '
      'and detail', (tester) async {
    await tester.runAsync(() async {
      await AlertHistoryDb().insert(trigger: 'SOS button', outcome: 'Sent');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await AlertHistoryDb().insert(
          trigger: 'Shake to SOS',
          outcome: 'Failed',
          detail: 'Add emergency contacts first.');
    });
    await pumpPage(tester);

    expect(find.text('SOS button'), findsOneWidget);
    expect(find.text('Shake to SOS'), findsOneWidget);
    expect(find.text('Sent'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('Add emergency contacts first.'), findsOneWidget);

    // Newest first: Shake to SOS (inserted second) appears above SOS button.
    final shakeY = tester.getTopLeft(find.text('Shake to SOS')).dy;
    final sosY = tester.getTopLeft(find.text('SOS button')).dy;
    expect(shakeY, lessThan(sosY));
  });

  testWidgets('pull-to-refresh re-queries and shows a newly inserted entry',
      (tester) async {
    await pumpPage(tester);
    expect(find.text('No alerts yet'), findsOneWidget);

    await tester.runAsync(
        () => AlertHistoryDb().insert(trigger: 'SOS button', outcome: 'Sent'));

    await tester.fling(
        find.byType(RefreshIndicator), const Offset(0, 300), 1000);
    await tester.pump();
    await settleWithRealAsync(tester);
    await tester.pumpAndSettle();

    expect(find.text('SOS button'), findsOneWidget);
  });

  testWidgets('Clear history confirms then empties the list and the table',
      (tester) async {
    await tester.runAsync(
        () => AlertHistoryDb().insert(trigger: 'SOS button', outcome: 'Sent'));
    await pumpPage(tester);
    expect(find.text('SOS button'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.text('Clear alert history'), findsOneWidget);

    await tester.tap(find.text('Clear'));
    await settleWithRealAsync(tester);

    expect(find.text('No alerts yet'), findsOneWidget);
    // Raw sqflite calls need a real event-loop tick to resolve; a bare
    // `await` here would hang forever inside testWidgets' fake-async zone
    // (see test_helpers.dart's settleWithRealAsync doc comment).
    await tester.runAsync(() async {
      expect(await AlertHistoryDb().getEntries(), isEmpty);
    });
  });
}
