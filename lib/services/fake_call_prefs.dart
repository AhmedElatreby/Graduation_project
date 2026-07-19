// ─────────────────────────────────────────────────────────────────────────────
//  Lumi · Fake-call caller identity
//  Who the staged incoming call appears to be from. Defaults to a caller
//  you'd plausibly answer; both fields are user-editable from the fake-call
//  sheet and persist across restarts.
//  See docs/superpowers/specs/2026-07-19-fake-call-design.md
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeCallPrefs {
  FakeCallPrefs._();

  static const _nameKey = 'fake_call_name';
  static const _numberKey = 'fake_call_number';

  static const defaultName = 'Mom';
  // Ofcom's reserved fictional mobile range — looks real, can never be.
  static const defaultNumber = '07700 900123';

  static final ValueNotifier<String> callerName = ValueNotifier(defaultName);
  static final ValueNotifier<String> callerNumber =
      ValueNotifier(defaultNumber);

  /// Load the persisted values (call once at startup, before first listen).
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    callerName.value = prefs.getString(_nameKey) ?? defaultName;
    callerNumber.value = prefs.getString(_numberKey) ?? defaultNumber;
  }

  /// Blank input falls back to the default — an empty caller screen would
  /// give the act away.
  static Future<void> setCaller(String name, String number) async {
    final n = name.trim().isEmpty ? defaultName : name.trim();
    final num_ = number.trim().isEmpty ? defaultNumber : number.trim();
    callerName.value = n;
    callerNumber.value = num_;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nameKey, n);
    await prefs.setString(_numberKey, num_);
  }
}
