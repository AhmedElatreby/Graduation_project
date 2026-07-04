// ─────────────────────────────────────────────────────────────────────────────
//  Lumi · Shake-to-SOS preference
//  A single persisted flag. Default ON — users who get false triggers while
//  running/cycling can turn it off from the Track tab.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ShakePrefs {
  ShakePrefs._();

  static const _key = 'shake_to_sos_enabled';

  /// Listen to this to start/stop the detector; toggle via [setEnabled].
  static final ValueNotifier<bool> enabled = ValueNotifier(true);

  /// Load the persisted value (call once at startup, before first listen).
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    enabled.value = prefs.getBool(_key) ?? true;
  }

  static Future<void> setEnabled(bool value) async {
    enabled.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }
}
