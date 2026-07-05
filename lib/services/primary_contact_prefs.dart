// ─────────────────────────────────────────────────────────────────────────────
//  Lumi · Primary guardian contact
//  Which guardian's phone number EmergencyAlert.callFirstContact actually
//  dials. Stored as a bare contact id, not a database column — the
//  `contacts` table has no schema-migration path today, and a nullable
//  int persisted like ShakePrefs already does is all this needs. A stored
//  id that no longer matches any contact (deleted guardian, or nothing
//  ever set) is treated as "no primary" wherever this is read.
//  See docs/superpowers/specs/2026-07-05-primary-guardian-contact-design.md
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PrimaryContactPrefs {
  PrimaryContactPrefs._();

  static const _key = 'primary_contact_id';

  /// Null when no primary is set.
  static final ValueNotifier<int?> id = ValueNotifier(null);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    id.value = prefs.getInt(_key);
  }

  /// Pass null to clear ("Remove as primary").
  static Future<void> set(int? contactId) async {
    id.value = contactId;
    final prefs = await SharedPreferences.getInstance();
    if (contactId == null) {
      await prefs.remove(_key);
    } else {
      await prefs.setInt(_key, contactId);
    }
  }
}
