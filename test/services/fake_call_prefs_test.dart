// test/services/fake_call_prefs_test.dart
// Caller identity for the fake incoming call. Defaults must be plausible
// (the whole feature is an act); edits persist across restarts.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safetyproject/services/fake_call_prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('defaults to Mom / 07700 900123 when nothing is stored', () async {
    SharedPreferences.setMockInitialValues({});
    await FakeCallPrefs.load();
    expect(FakeCallPrefs.callerName.value, 'Mom');
    expect(FakeCallPrefs.callerNumber.value, '07700 900123');
  });

  test('setCaller persists and load restores', () async {
    SharedPreferences.setMockInitialValues({});
    await FakeCallPrefs.load();
    await FakeCallPrefs.setCaller('Dad', '07700 900456');

    // Fresh notifier state, then reload from the same mock store.
    FakeCallPrefs.callerName.value = '';
    FakeCallPrefs.callerNumber.value = '';
    await FakeCallPrefs.load();
    expect(FakeCallPrefs.callerName.value, 'Dad');
    expect(FakeCallPrefs.callerNumber.value, '07700 900456');
  });

  test('blank edits fall back to the defaults, not empty strings', () async {
    SharedPreferences.setMockInitialValues({});
    await FakeCallPrefs.load();
    await FakeCallPrefs.setCaller('   ', '');
    expect(FakeCallPrefs.callerName.value, 'Mom');
    expect(FakeCallPrefs.callerNumber.value, '07700 900123');
  });
}
