// Whether the silent SOS trigger is on — off by default, unlike ShakePrefs
// (this repurposes a hardware button while the app is open, so it's opt-in).
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safetyproject/services/silent_sos_prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('off by default', () async {
    SharedPreferences.setMockInitialValues({});
    await SilentSosPrefs.load();
    expect(SilentSosPrefs.enabled.value, isFalse);
  });

  test('setEnabled persists and survives a reload', () async {
    SharedPreferences.setMockInitialValues({});
    await SilentSosPrefs.load();

    await SilentSosPrefs.setEnabled(true);
    expect(SilentSosPrefs.enabled.value, isTrue);

    SilentSosPrefs.enabled.value = false; // scribble over the in-memory value
    await SilentSosPrefs.load();
    expect(SilentSosPrefs.enabled.value, isTrue);
  });
}
