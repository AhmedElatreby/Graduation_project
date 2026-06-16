import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safetyproject/pages/login_page.dart';

void main() {
  group('Login page', () {
    testWidgets('renders greeting and input fields', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(home: LoginPage()));
      expect(find.text('Hello'), findsOneWidget);
      expect(find.text('Sign into your account'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Email'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Password'), findsOneWidget);
    });
  });
}
