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

  test('thresholdFor returns the three documented gravity values', () {
    expect(thresholdFor(ShakeSensitivity.low), 3.5);
    expect(thresholdFor(ShakeSensitivity.medium), 2.7);
    expect(thresholdFor(ShakeSensitivity.high), 2.0);
  });

  test('sensitivity defaults to medium when nothing is stored', () async {
    SharedPreferences.setMockInitialValues({});
    await ShakePrefs.load();
    expect(ShakePrefs.sensitivity.value, ShakeSensitivity.medium);
  });

  test('setSensitivity persists and survives a reload', () async {
    SharedPreferences.setMockInitialValues({});
    await ShakePrefs.load();

    await ShakePrefs.setSensitivity(ShakeSensitivity.high);
    expect(ShakePrefs.sensitivity.value, ShakeSensitivity.high);

    // Simulate a fresh app start reading the same store.
    ShakePrefs.sensitivity.value = ShakeSensitivity.medium; // scribble over memory
    await ShakePrefs.load();
    expect(ShakePrefs.sensitivity.value, ShakeSensitivity.high);
  });

  test('an unrecognized stored sensitivity string falls back to medium',
      () async {
    SharedPreferences.setMockInitialValues({'shake_sensitivity': 'bogus'});
    await ShakePrefs.load();
    expect(ShakePrefs.sensitivity.value, ShakeSensitivity.medium);
  });
}
