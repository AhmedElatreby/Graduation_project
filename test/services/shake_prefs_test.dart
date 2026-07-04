// ShakePrefs: default ON, toggle persists across a reload.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safetyproject/services/shake_prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('defaults to enabled when nothing is stored', () async {
    SharedPreferences.setMockInitialValues({});
    await ShakePrefs.load();
    expect(ShakePrefs.enabled.value, isTrue);
  });

  test('setEnabled(false) persists and survives a reload', () async {
    SharedPreferences.setMockInitialValues({});
    await ShakePrefs.load();

    await ShakePrefs.setEnabled(false);
    expect(ShakePrefs.enabled.value, isFalse);

    // Simulate a fresh app start reading the same store.
    ShakePrefs.enabled.value = true; // scribble over the in-memory value
    await ShakePrefs.load();
    expect(ShakePrefs.enabled.value, isFalse);
  });

  test('stored value is honoured on load', () async {
    SharedPreferences.setMockInitialValues({'shake_to_sos_enabled': false});
    await ShakePrefs.load();
    expect(ShakePrefs.enabled.value, isFalse);
  });
}
