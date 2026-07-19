// ─────────────────────────────────────────────────────────────────────────────
//  Lumi · Pending guardian call
//  Android 10+ blocks a backgrounded service from launching the dialer. When
//  the background alert can't place the call, this flag survives until the
//  user opens the app (usually by tapping the "alert sent" notification),
//  which consumes it and dials the first guardian from the foreground.
//  The flag stores its set-time and expires after [maxAge]: it can outlive
//  the session that set it (that's the point), but a copy surviving into a
//  much later session must be dropped, not dialed — observed on-device as a
//  guardian call firing two weeks after the alert it belonged to.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:shared_preferences/shared_preferences.dart';

class PendingCall {
  PendingCall._();

  static const _key = 'pending_guardian_call';

  /// How long a blocked call stays worth placing. Generous enough to cover
  /// "saw the notification, opened the app a bit later"; far too short for a
  /// flag from an abandoned session to resurface as a surprise call.
  static const maxAge = Duration(minutes: 15);

  static Future<void> set() async =>
      (await SharedPreferences.getInstance())
          .setInt(_key, DateTime.now().millisecondsSinceEpoch);

  /// True at most once per [set] — clears the flag as it reads it. A flag
  /// older than [maxAge] (or a legacy bool from an old install, which getInt
  /// reads as null) is cleared and reported false.
  static Future<bool> consume() async {
    final prefs = await SharedPreferences.getInstance();
    int? setAt;
    try {
      setAt = prefs.getInt(_key);
    } on TypeError {
      setAt = null; // legacy bool value from a pre-timestamp install
    }
    final hadKey = prefs.containsKey(_key);
    if (hadKey) await prefs.remove(_key);
    if (setAt == null) return false;
    final age = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(setAt));
    return age <= maxAge;
  }
}