// ─────────────────────────────────────────────────────────────────────────────
//  Lumi · Shake-to-SOS preferences
//  Two persisted values: whether shake-to-SOS is on, and how hard a shake
//  must be (sensitivity). Default ON / Medium — users who get false triggers
//  while running/cycling can turn it off or make it harder to trigger from
//  the Track tab.
//  See docs/superpowers/specs/2026-07-05-shake-sensitivity-design.md
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ShakeSensitivity { low, medium, high }

/// Force threshold — 2.0g (High) is easier to trigger than 3.5g (Low).
/// Shake *count* stays fixed at 2 everywhere; this only tunes force.
double thresholdFor(ShakeSensitivity level) => switch (level) {
      ShakeSensitivity.low => 3.5,
      ShakeSensitivity.medium => 2.7, // the shake package's own default
      ShakeSensitivity.high => 2.0,
    };

class ShakePrefs {
  ShakePrefs._();

  static const _enabledKey = 'shake_to_sos_enabled';
  static const _sensitivityKey = 'shake_sensitivity';

  /// Listen to this to start/stop the detector; toggle via [setEnabled].
  static final ValueNotifier<bool> enabled = ValueNotifier(true);

  /// Listen to this to rebuild the detector at a new threshold; set via
  /// [setSensitivity].
  static final ValueNotifier<ShakeSensitivity> sensitivity =
      ValueNotifier(ShakeSensitivity.medium);

  /// Load the persisted values (call once at startup, before first listen).
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    enabled.value = prefs.getBool(_enabledKey) ?? true;
    sensitivity.value = _decode(prefs.getString(_sensitivityKey));
  }

  static Future<void> setEnabled(bool value) async {
    enabled.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
  }

  static Future<void> setSensitivity(ShakeSensitivity level) async {
    sensitivity.value = level;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sensitivityKey, level.name);
  }

  static ShakeSensitivity _decode(String? stored) => switch (stored) {
        'low' => ShakeSensitivity.low,
        'high' => ShakeSensitivity.high,
        _ => ShakeSensitivity.medium, // covers 'medium', null, and garbage
      };
}
