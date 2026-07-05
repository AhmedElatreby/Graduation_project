# Primary Guardian Contact Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user designate one guardian as the primary contact — the
one who actually gets called on an alert — with automatic fallback to
today's behavior (the most recently added guardian) if none is set.

**Architecture:** A new `PrimaryContactPrefs` service (one nullable int,
persisted the same way `ShakePrefs` persists simple values) is the single
source of truth for which contact id is primary. `EmergencyAlert
.callFirstContact` reads it to decide who to call; the Guardians page reads
it to decide which row shows a star badge and what its "⋯" menu offers.

**Tech Stack:** Flutter/Dart, `shared_preferences` (already a dependency,
already used by `ShakePrefs`/`CheckInPrefs` for the identical pattern).

## Global Constraints

- SMS delivery is unaffected — every guardian gets the alert SMS regardless
  of primary status. Only `callFirstContact` changes.
- A stored primary id that matches no current contact behaves exactly like
  "no primary set" — no crash, no dangling reference, silent fallback to
  `list.first`.
- No database schema change — `contacts` (in `db_helper.dart`) has no
  `onUpgrade` path today and this feature must not require adding one.

---

### Task 1: `PrimaryContactPrefs` — persisted primary contact id

**Files:**
- Create: `lib/services/primary_contact_prefs.dart`
- Test: `test/services/primary_contact_prefs_test.dart`

**Interfaces:**
- Produces: `PrimaryContactPrefs.id` (`ValueNotifier<int?>`, null = no
  primary set), `PrimaryContactPrefs.load()` (`Future<void>`),
  `PrimaryContactPrefs.set(int? contactId)` (`Future<void>`, `null` clears
  it). Task 2 and Task 3 both read/write exactly these three names.

- [ ] **Step 1: Write the failing tests**

Create `test/services/primary_contact_prefs_test.dart`:

```dart
// PrimaryContactPrefs: no primary by default, set() persists and survives a
// reload, set(null) clears a previously stored id.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safetyproject/services/primary_contact_prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('no primary set by default', () async {
    SharedPreferences.setMockInitialValues({});
    await PrimaryContactPrefs.load();
    expect(PrimaryContactPrefs.id.value, isNull);
  });

  test('set persists the id and survives a reload', () async {
    SharedPreferences.setMockInitialValues({});
    await PrimaryContactPrefs.load();

    await PrimaryContactPrefs.set(42);
    expect(PrimaryContactPrefs.id.value, 42);

    // Simulate a fresh read of the same store.
    PrimaryContactPrefs.id.value = null; // scribble over the in-memory value
    await PrimaryContactPrefs.load();
    expect(PrimaryContactPrefs.id.value, 42);
  });

  test('set(null) clears a previously stored id', () async {
    SharedPreferences.setMockInitialValues({});
    await PrimaryContactPrefs.load();
    await PrimaryContactPrefs.set(42);

    await PrimaryContactPrefs.set(null);
    expect(PrimaryContactPrefs.id.value, isNull);

    await PrimaryContactPrefs.load();
    expect(PrimaryContactPrefs.id.value, isNull);
  });

  test('stored value is honoured on load', () async {
    SharedPreferences.setMockInitialValues({'primary_contact_id': 7});
    await PrimaryContactPrefs.load();
    expect(PrimaryContactPrefs.id.value, 7);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/services/primary_contact_prefs_test.dart`
Expected: FAIL — `primary_contact_prefs.dart` doesn't exist yet.

- [ ] **Step 3: Implement `PrimaryContactPrefs`**

Create `lib/services/primary_contact_prefs.dart`:

```dart
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/services/primary_contact_prefs_test.dart`
Expected: PASS (4/4)

- [ ] **Step 5: Commit**

```bash
git add lib/services/primary_contact_prefs.dart test/services/primary_contact_prefs_test.dart
git commit -m "feat: add PrimaryContactPrefs for the primary guardian id"
```

---

### Task 2: `EmergencyAlert.callFirstContact` uses the primary contact

**Files:**
- Modify: `lib/services/emergency_alert.dart`
- Test: `test/services/emergency_alert_test.dart`

**Interfaces:**
- Consumes: `PrimaryContactPrefs.id` (Task 1).
- Produces: no signature change to `callFirstContact` — same
  `Future<bool?> callFirstContact({List<PersonalEmergency>? contacts})` —
  only its internal contact-selection logic changes, so no other call site
  in the app needs to change.

- [ ] **Step 1: Write the failing tests**

In `test/services/emergency_alert_test.dart`, add this import:

```dart
import 'package:safetyproject/services/primary_contact_prefs.dart';
```

Add these tests inside `main()`, after the existing `hasGuardians` test.
They target a new `EmergencyAlert.resolveCallTarget` method (implemented in
Step 3) rather than `callFirstContact` directly: `callFirstContact` ends by
calling straight into `FlutterPhoneDirectCaller.callNumber`, which throws
`MissingPluginException` in a widget test with no platform channel mocked
— `resolveCallTarget` is the actual contact-selection logic, extracted so
it's reachable from a test without hitting that plugin boundary, the same
shape this file already uses for `buildAlertMessage`.

```dart
  test('callFirstContact calls the primary contact when one is set',
      () async {
    final sara =
        await DBHelper().add(PersonalEmergency('Sara', '01000000000'));
    await DBHelper().add(PersonalEmergency('Jo', '02000000000'));
    await PrimaryContactPrefs.set(sara.id);

    final contacts = await DBHelper().getContacts();
    // getContacts() orders id DESC, so Jo (added later) is list.first —
    // this sanity check proves the primary override is what matters below.
    expect(contacts.first.name, 'Jo');

    expect(
      EmergencyAlert.resolveCallTarget(contacts).contactNo,
      '01000000000', // Sara's number, chosen over Jo despite not being first
    );
  });

  test(
      'callFirstContact resolves to list.first when the stored primary id '
      'matches no current contact', () async {
    await DBHelper().add(PersonalEmergency('Sara', '01000000000'));
    await PrimaryContactPrefs.set(999999); // no contact has this id

    final contacts = await DBHelper().getContacts();
    expect(EmergencyAlert.resolveCallTarget(contacts).contactNo,
        '01000000000');
  });

  test('resolveCallTarget resolves to list.first when no primary is set',
      () async {
    await DBHelper().add(PersonalEmergency('Sara', '01000000000'));

    final contacts = await DBHelper().getContacts();
    expect(EmergencyAlert.resolveCallTarget(contacts).contactNo,
        '01000000000');
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/services/emergency_alert_test.dart`
Expected: FAIL — `EmergencyAlert.resolveCallTarget` doesn't exist yet.

- [ ] **Step 3: Implement `resolveCallTarget` and use it in `callFirstContact`**

In `lib/services/emergency_alert.dart`, add the import:

```dart
import 'primary_contact_prefs.dart';
```

Replace the existing `callFirstContact`:

```dart
  /// Calls the first guardian. Throws on failure; returns the plugin's
  /// success flag (false/null = the OS refused the launch without throwing).
  static Future<bool?> callFirstContact(
      {List<PersonalEmergency>? contacts}) async {
    await _requireGranted(Permission.phone, 'Phone');
    final list = contacts ?? await DBHelper().getContacts();
    return FlutterPhoneDirectCaller.callNumber(list.first.contactNo);
  }
```

with:

```dart
  /// The guardian who actually gets called: the one marked primary via
  /// PrimaryContactPrefs, if any contact in [contacts] still has that id —
  /// otherwise contacts.first (today's behavior, unchanged for anyone who
  /// never sets a primary). [contacts] must be non-empty.
  static PersonalEmergency resolveCallTarget(List<PersonalEmergency> contacts) {
    final primaryId = PrimaryContactPrefs.id.value;
    if (primaryId != null) {
      for (final c in contacts) {
        if (c.id == primaryId) return c;
      }
    }
    return contacts.first;
  }

  /// Calls the primary guardian (or the first, if none is set). Throws on
  /// failure; returns the plugin's success flag (false/null = the OS
  /// refused the launch without throwing).
  static Future<bool?> callFirstContact(
      {List<PersonalEmergency>? contacts}) async {
    await _requireGranted(Permission.phone, 'Phone');
    final list = contacts ?? await DBHelper().getContacts();
    return FlutterPhoneDirectCaller.callNumber(
        resolveCallTarget(list).contactNo);
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/services/emergency_alert_test.dart`
Expected: PASS (7/7)

- [ ] **Step 5: Run the full test suite**

Run: `flutter test`
Expected: all tests PASS — `callFirstContact`'s public signature and
behavior when no primary is set are both unchanged.

- [ ] **Step 6: Commit**

```bash
git add lib/services/emergency_alert.dart test/services/emergency_alert_test.dart
git commit -m "feat: EmergencyAlert calls the primary guardian when one is set"
```

---

### Task 3: Guardians-page UI — star badge and "Set as primary" menu item

**Files:**
- Modify: `lib/contact/personal_emergency_contacts.dart`

**Interfaces:**
- Consumes: `PrimaryContactPrefs.id/set` (Task 1). Does not depend on
  Task 2 (the UI only ever writes the pref; `EmergencyAlert` is what reads
  it at alert time).

No new automated test file — this is page-level UI wiring in the same
category as the Track-page cards elsewhere in this app, verified with
`flutter analyze` and on-device rather than a widget test.

- [ ] **Step 1: Add the import and listen for primary changes**

In `lib/contact/personal_emergency_contacts.dart`, add the import:

```dart
import '../services/primary_contact_prefs.dart';
```

Wrap the existing `FutureBuilder<List<PersonalEmergency>>` (the one whose
`builder` returns the `ListView.separated`) in a
`ValueListenableBuilder<int?>` so toggling primary rebuilds the list
immediately. Replace:

```dart
          Expanded(
            child: FutureBuilder<List<PersonalEmergency>>(
              future: _contactsFuture,
              builder: (context, snapshot) {
```

with:

```dart
          Expanded(
            child: ValueListenableBuilder<int?>(
              valueListenable: PrimaryContactPrefs.id,
              builder: (context, primaryId, _) => FutureBuilder<List<PersonalEmergency>>(
              future: _contactsFuture,
              builder: (context, snapshot) {
```

And its matching closing — replace:

```dart
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
```

with:

```dart
                  },
                );
              },
            ),
            ),
          ),
        ],
      ),
    );
  }
```

(`dart format` in Step 5 fixes the indentation of everything between these
two edits — don't hand-indent the body in between.)

- [ ] **Step 2: Pass `isPrimary`/`onTogglePrimary` into `_ContactTile`**

Replace the existing `_ContactTile` construction:

```dart
                    return _ContactTile(
                      contact: c,
                      colors: colors,
                      onSms: () => _sms(c.contactNo),
                      onCall: () =>
                          FlutterPhoneDirectCaller.callNumber(c.contactNo),
                      onEdit: () => _showSheet(existing: c),
                      onDelete: () => _confirmDelete(c),
                    );
```

with:

```dart
                    return _ContactTile(
                      contact: c,
                      colors: colors,
                      isPrimary: c.id == primaryId,
                      onSms: () => _sms(c.contactNo),
                      onCall: () =>
                          FlutterPhoneDirectCaller.callNumber(c.contactNo),
                      onEdit: () => _showSheet(existing: c),
                      onDelete: () => _confirmDelete(c),
                      onTogglePrimary: () => PrimaryContactPrefs.set(
                          c.id == primaryId ? null : c.id),
                    );
```

- [ ] **Step 3: Add the star badge and menu item to `_ContactTile`**

Replace the existing `_ContactTile` class fields and constructor:

```dart
class _ContactTile extends StatelessWidget {
  const _ContactTile({
    required this.contact,
    required this.colors,
    required this.onSms,
    required this.onCall,
    required this.onEdit,
    required this.onDelete,
  });
  final PersonalEmergency contact;
  final List<Color> colors;
  final VoidCallback onSms, onCall, onEdit, onDelete;
```

with:

```dart
class _ContactTile extends StatelessWidget {
  const _ContactTile({
    required this.contact,
    required this.colors,
    required this.isPrimary,
    required this.onSms,
    required this.onCall,
    required this.onEdit,
    required this.onDelete,
    required this.onTogglePrimary,
  });
  final PersonalEmergency contact;
  final List<Color> colors;
  final bool isPrimary;
  final VoidCallback onSms, onCall, onEdit, onDelete, onTogglePrimary;
```

Replace the avatar `Container` in `build()`:

```dart
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: colors),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child:
                Text(initial, style: LumiText.display(17, color: Colors.white)),
          ),
```

with:

```dart
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: colors),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Text(initial,
                    style: LumiText.display(17, color: Colors.white)),
              ),
              if (isPrimary)
                Positioned(
                  bottom: -2,
                  right: -2,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: const BoxDecoration(
                      color: LumiColors.amber,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.star,
                        size: 12, color: Colors.white),
                  ),
                ),
            ],
          ),
```

Replace the `_menu` call site so it can read `isPrimary`/call
`onTogglePrimary` — replace:

```dart
          _RoundIcon(
              icon: Icons.more_horiz,
              color: LumiColors.textSub,
              onTap: () => _menu(context)),
```

with (unchanged — `_menu` is already an instance method with access to
`this.isPrimary`/`this.onTogglePrimary`, no call-site change needed):

```dart
          _RoundIcon(
              icon: Icons.more_horiz,
              color: LumiColors.textSub,
              onTap: () => _menu(context)),
```

Replace the existing `_menu` method:

```dart
  void _menu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: LumiColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: LumiColors.text),
              title: Text('Edit', style: LumiText.body(15)),
              onTap: () {
                Navigator.pop(ctx);
                onEdit();
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.delete_outline, color: LumiColors.accent),
              title: Text('Delete',
                  style: LumiText.body(15, color: LumiColors.accent)),
              onTap: () {
                Navigator.pop(ctx);
                onDelete();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
```

with:

```dart
  void _menu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: LumiColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(isPrimary ? Icons.star : Icons.star_border,
                  color: LumiColors.amber),
              title: Text(isPrimary ? 'Remove as primary' : 'Set as primary',
                  style: LumiText.body(15)),
              onTap: () {
                Navigator.pop(ctx);
                onTogglePrimary();
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: LumiColors.text),
              title: Text('Edit', style: LumiText.body(15)),
              onTap: () {
                Navigator.pop(ctx);
                onEdit();
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.delete_outline, color: LumiColors.accent),
              title: Text('Delete',
                  style: LumiText.body(15, color: LumiColors.accent)),
              onTap: () {
                Navigator.pop(ctx);
                onDelete();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
```

Check `LumiColors.amber` exists in `lib/theme/lumi_theme.dart` before this
step — it's already referenced elsewhere in this codebase (the Track
page's siren card uses `LumiColors.amber`), so no new color needs adding.

- [ ] **Step 4: Load `PrimaryContactPrefs` at startup**

In `lib/main.dart`, alongside the existing `await ShakePrefs.load();`, add:

```dart
  await PrimaryContactPrefs.load();
```

and the import:

```dart
import 'services/primary_contact_prefs.dart';
```

Without this, `PrimaryContactPrefs.id` stays at its default `null` for the
whole app session regardless of what's stored on disk — every other
`Prefs.load()` call site in this app already runs at startup for the same
reason.

- [ ] **Step 5: Format and verify with static analysis**

Run: `dart format lib/contact/personal_emergency_contacts.dart lib/main.dart`
Run: `flutter analyze lib/contact/personal_emergency_contacts.dart lib/main.dart`
Expected: no new errors or warnings.

- [ ] **Step 6: Run the full test suite**

Run: `flutter test`
Expected: all tests PASS.

- [ ] **Step 7: On-device verification**

Build and install a debug APK, then on the Contacts (Guardians) page:

1. With two or more guardians, open "⋯" on one and tap "Set as primary" —
   confirm a star badge appears on that guardian's avatar and their menu
   now offers "Remove as primary".
2. Confirm no other guardian shows a star.
3. Tap "Remove as primary" — star disappears, menu reverts to "Set as
   primary".
4. Set a primary, then delete that guardian — confirm the app doesn't
   crash and no star shows anywhere afterward (per the spec's "automatic,
   silent fallback").
5. With a primary set, trigger the SOS hold button with a safe placeholder
   guardian roster and confirm (via the phone's own call log, not by
   actually letting a real call complete) that the primary's number is
   what gets dialed, not the most-recently-added guardian's.

- [ ] **Step 8: Commit**

```bash
git add lib/contact/personal_emergency_contacts.dart lib/main.dart
git commit -m "feat: primary guardian star badge and set/remove menu action"
```
