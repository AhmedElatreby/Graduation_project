// ─────────────────────────────────────────────────────────────────────────────
//  Lumi · Check-in timer preferences
//  Persists a running timer's end time (and optional note) so it survives
//  app restart, device reboot, and the foreground service being killed and
//  restarted by Android — the timestamp is the single source of truth,
//  never a remaining-Duration counter that would need to keep ticking in
//  memory to stay correct.
//  See docs/superpowers/specs/2026-07-05-checkin-timer-design.md
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CheckInPrefs {
  CheckInPrefs._();

  static const _endTimeKey = 'checkin_end_time_millis';
  static const _noteKey = 'checkin_note';

  /// Null when no timer is running.
  static final ValueNotifier<DateTime?> endTime = ValueNotifier(null);
  static final ValueNotifier<String?> note = ValueNotifier(null);

  /// Load the persisted values (call once at startup/service-start, before
  /// first read — each isolate has its own SharedPreferences access and its
  /// own copy of these ValueNotifiers).
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final millis = prefs.getInt(_endTimeKey);
    endTime.value =
        millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
    note.value = prefs.getString(_noteKey);
  }

  static Future<void> start(Duration duration, {String? note}) async {
    final end = DateTime.now().add(duration);
    // Normalize to milliseconds to match what load() will restore
    final normalized = DateTime.fromMillisecondsSinceEpoch(end.millisecondsSinceEpoch);
    endTime.value = normalized;
    CheckInPrefs.note.value = note;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_endTimeKey, end.millisecondsSinceEpoch);
    if (note == null) {
      await prefs.remove(_noteKey);
    } else {
      await prefs.setString(_noteKey, note);
    }
  }

  /// Clears both keys. Called on cancel, and after a sent alert.
  static Future<void> clear() async {
    endTime.value = null;
    note.value = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_endTimeKey);
    await prefs.remove(_noteKey);
  }
}
