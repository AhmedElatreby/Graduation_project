// ─────────────────────────────────────────────────────────────────────────────
//  Lumi · Pending guardian call
//  Android 10+ blocks a backgrounded service from launching the dialer. When
//  the background alert can't place the call, this flag survives until the
//  user opens the app (usually by tapping the "alert sent" notification),
//  which consumes it and dials the first guardian from the foreground.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:shared_preferences/shared_preferences.dart';

class PendingCall {
  PendingCall._();

  static const _key = 'pending_guardian_call';

  static Future<void> set() async =>
      (await SharedPreferences.getInstance()).setBool(_key, true);

  /// True at most once per [set] — clears the flag as it reads it.
  static Future<bool> consume() async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getBool(_key) ?? false;
    if (pending) await prefs.remove(_key);
    return pending;
  }
}
