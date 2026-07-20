// ─────────────────────────────────────────────────────────────────────────────
//  Lumi · Silent SOS trigger preference
//  Whether volume-down ×3 is armed as a discreet SOS trigger. Off by
//  default: unlike shake-to-SOS this repurposes a hardware button (see
//  SilentSosChannel) while the app is open, so it's opt-in, not opt-out.
//  See docs/superpowers/specs/2026-07-20-silent-sos-trigger-design.md
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SilentSosPrefs {
  SilentSosPrefs._();

  static const _enabledKey = 'silent_sos_enabled';

  static final ValueNotifier<bool> enabled = ValueNotifier(false);

  /// Load the persisted value (call once at startup, before first listen).
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    enabled.value = prefs.getBool(_enabledKey) ?? false;
  }

  static Future<void> setEnabled(bool value) async {
    enabled.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
  }
}
