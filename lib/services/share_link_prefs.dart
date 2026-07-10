// ─────────────────────────────────────────────────────────────────────────────
//  Lumi · Active guardian share link
//  Which shared_locations document (if any) the Live Location stream
//  should also mirror fresh GPS fixes into. A missing shareId or an
//  expiresAt in the past both mean "nothing to mirror into" — isActive is
//  the single source of truth callers check, not two separate booleans
//  that could drift out of sync.
//  See docs/superpowers/specs/2026-07-10-guardian-live-view-design.md
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ShareLinkPrefs {
  ShareLinkPrefs._();

  static const _shareIdKey = 'guardian_share_id';
  static const _expiresAtKey = 'guardian_share_expires_at_millis';

  static final ValueNotifier<String?> shareId = ValueNotifier(null);
  static final ValueNotifier<DateTime?> expiresAt = ValueNotifier(null);

  static bool get isActive =>
      shareId.value != null &&
      expiresAt.value != null &&
      DateTime.now().isBefore(expiresAt.value!);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    shareId.value = prefs.getString(_shareIdKey);
    final millis = prefs.getInt(_expiresAtKey);
    expiresAt.value =
        millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  /// Always replaces any previous share — there is only ever one active
  /// share tracked at a time (see the design doc's documented trade-off).
  static Future<void> start(String shareId, DateTime expiresAt) async {
    // Normalize to milliseconds to match what load() will restore
    final normalized = DateTime.fromMillisecondsSinceEpoch(expiresAt.millisecondsSinceEpoch);
    ShareLinkPrefs.shareId.value = shareId;
    ShareLinkPrefs.expiresAt.value = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_shareIdKey, shareId);
    await prefs.setInt(_expiresAtKey, expiresAt.millisecondsSinceEpoch);
  }
}
