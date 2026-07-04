// Regression tests for the Guardians (contacts) page.
//
// The bug: _refresh() used to call
//   setState(() => _contactsFuture = _dbHelper.getContacts())
// which passes setState() a closure that returns a Future. Flutter's
// framework throws on that *before* marking the widget dirty, so the
// FutureBuilder never rebuilt -- a newly added/edited/deleted contact only
// showed up after a full app restart. These tests drive the real add/edit/
// delete flow through the UI (against a real, in-memory sqflite database)
// and assert the list updates in the same frame, with no restart involved.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safetyproject/contact/personal_emergency_contacts.dart';
import 'package:safetyproject/database/db_helper.dart';
import 'package:safetyproject/widgets/lumi_widgets.dart';

import '../test_helpers.dart';

Future<void> _clearContactsTable() async {
  final db = await DBHelper().db;
  await db.delete('contacts');
}

Future<void> _pumpContactsPage(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(
    home: Scaffold(body: PersonalEmergencyContacts()),
  ));
  await settleWithRealAsync(tester);
}

Future<void> _addGuardian(
    WidgetTester tester, String name, String phone) async {
  await tester.tap(find.text('Add guardian').first);
  await settleWithRealAsync(tester);

  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), name);
  await tester.enterText(fields.at(1), phone);
  await settleWithRealAsync(tester);

  await tester.tap(find.byType(LumiPrimaryButton));
  await settleWithRealAsync(tester);
}

void main() {
  configureTestEnvironment();

  setUp(_clearContactsTable);

  group('Guardians list refresh', () {
    testWidgets('a newly added contact appears immediately, no restart',
        (tester) async {
      await _pumpContactsPage(tester);

      expect(find.text('Test Guardian'), findsNothing);

      await _addGuardian(tester, 'Test Guardian', '5551234567');

      expect(find.text('Test Guardian'), findsOneWidget);
      expect(find.text('5551234567'), findsOneWidget);
      expect(find.text('1 people'), findsOneWidget);
    });

    testWidgets('editing a contact updates the list immediately',
        (tester) async {
      await _pumpContactsPage(tester);
      await _addGuardian(tester, 'Original Name', '1112223333');
      expect(find.text('Original Name'), findsOneWidget);

      // Open the "..." menu for the row, then Edit.
      await tester.tap(find.byIcon(Icons.more_horiz));
      await settleWithRealAsync(tester);
      await tester.tap(find.text('Edit'));
      await settleWithRealAsync(tester);

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Updated Name');
      await settleWithRealAsync(tester);

      await tester.tap(find.byType(LumiPrimaryButton));
      await settleWithRealAsync(tester);

      expect(find.text('Original Name'), findsNothing);
      expect(find.text('Updated Name'), findsOneWidget);
    });

    testWidgets('deleting a contact removes it from the list immediately',
        (tester) async {
      await _pumpContactsPage(tester);
      await _addGuardian(tester, 'Doomed Contact', '9998887777');
      expect(find.text('Doomed Contact'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.more_horiz));
      await settleWithRealAsync(tester);
      await tester.tap(find.text('Delete'));
      await settleWithRealAsync(tester);

      // Confirm in the "Remove guardian" dialog.
      await tester.tap(find.text('Delete').last);
      await settleWithRealAsync(tester);

      expect(find.text('Doomed Contact'), findsNothing);
      expect(find.text('0 people'), findsOneWidget);
    });
  });
}
