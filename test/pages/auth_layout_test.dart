// Regression tests for the login/signup layout bug.
//
// The bug: both pages sized their scrollable content with
//   ConstrainedBox(minHeight: MediaQuery.of(context).size.height - 120)
// The "120" was a guess that didn't account for the real available height
// (safe areas, status bar, etc.), so on some screen sizes the tail of the
// page -- "Create account" on the login screen, "Sign in" on the signup
// screen -- was pushed just past the visible viewport with no scroll
// indicator, making it look like the link didn't exist. Fixed by measuring
// the real constraint via LayoutBuilder instead of guessing.
//
// These tests pin the viewport to a small, real device size (iPhone SE) --
// the size most likely to expose a wrong fixed offset -- and assert the
// links are both present *and* within the visible screen bounds.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:safetyproject/pages/login_page.dart';
import 'package:safetyproject/pages/signup_page.dart';
import 'package:safetyproject/theme/lumi_theme.dart';

import '../test_helpers.dart';

/// iPhone SE (2nd/3rd gen): one of the smallest common iOS screens, and the
/// size most likely to expose a hardcoded height offset that's too small.
const _smallScreen = Size(375, 667);

Future<void> _setSmallScreen(WidgetTester tester) async {
  tester.view.physicalSize = _smallScreen;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

bool _isFullyOnscreen(WidgetTester tester, Finder finder) {
  final rect = tester.getRect(finder);
  final screen =
      Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;
  return screen.contains(rect.topLeft) && screen.contains(rect.bottomRight);
}

void main() {
  configureTestEnvironment();

  group('Login page', () {
    testWidgets('Create account link is visible without scrolling',
        (tester) async {
      await _setSmallScreen(tester);
      await tester.pumpWidget(GetMaterialApp(
        theme: LumiTheme.dark(),
        home: const LoginPage(),
      ));
      await settleWithRealAsync(tester);

      final createAccount = find.textContaining('Create account');
      expect(createAccount, findsOneWidget);
      expect(_isFullyOnscreen(tester, createAccount), isTrue,
          reason: 'Create account link must be reachable without scrolling');
    });

    testWidgets('tapping Create account navigates to the signup page',
        (tester) async {
      await _setSmallScreen(tester);
      await tester.pumpWidget(GetMaterialApp(
        theme: LumiTheme.dark(),
        home: const LoginPage(),
      ));
      await settleWithRealAsync(tester);

      await tester.tap(find.textContaining('Create account'));
      await settleWithRealAsync(tester);

      expect(find.text('Set up your safety circle in 30 seconds.'),
          findsOneWidget);
    });
  });

  group('Signup page', () {
    testWidgets('Sign in link is visible without scrolling', (tester) async {
      await _setSmallScreen(tester);
      await tester.pumpWidget(GetMaterialApp(
        theme: LumiTheme.dark(),
        home: const SignUpPage(),
      ));
      await settleWithRealAsync(tester);

      final signIn = find.textContaining('Sign in');
      expect(signIn, findsOneWidget);
      expect(_isFullyOnscreen(tester, signIn), isTrue,
          reason: 'Sign in link must be reachable without scrolling');
    });
  });
}
