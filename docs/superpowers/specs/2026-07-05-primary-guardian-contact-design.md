# Primary guardian contact — design

**Date:** 2026-07-05 · **Status:** approved

## What

Guardians gain an optional "primary" designation. The primary contact is who
actually gets called on an SOS/shake/check-in alert; every guardian still
gets the SMS regardless (that was never single-recipient — only the phone
call is). Each guardian row's "⋯" menu gains "Set as primary" (or "Remove as
primary" for the current one), and the primary contact's avatar shows a
small star badge. If no primary is ever set, calling behaves exactly as it
does today — the most recently added guardian (`DBHelper.getContacts()`
orders `id DESC`, so `list.first` is the newest, not the oldest).

Out of scope: reordering the guardian list itself, more than one "priority
tier" (e.g. "call 2nd if 1st doesn't answer" — the app has no way to detect
an unanswered call at all, see below), changing anything about SMS delivery.

## Why this shape

- **A stored id, not a database column:** the `contacts` table
  (`db_helper.dart`) has only ever had an `onCreate`, never an `onUpgrade` —
  there is no schema-migration path in this codebase yet. Introducing one
  just to add a single nullable flag is a disproportionate amount of new
  machinery for what "primary" actually needs: one integer, persisted the
  same way `ShakePrefs`/`CheckInPrefs` already persist simple values.
- **Automatic, silent fallback:** a stored primary id that no longer matches
  any contact (the guardian was deleted, or nothing was ever set) is
  indistinguishable from "no primary" to `callFirstContact()` — it just
  falls through to `list.first`. `sqflite`'s `AUTOINCREMENT` ids are never
  reused, so a stale stored id can never accidentally start matching a
  different, unrelated contact added later.
- **No answer-detection, so no call-order feature:** the user's original
  question was "what if the first guardian doesn't answer" — the honest
  answer is the app has no way to know. `FlutterPhoneDirectCaller.callNumber`
  places the call and returns; Android gives no callback for "was picked up."
  A primary-contact picker fixes the *actual* reachable problem (you can
  make sure the right person is the one who gets called) without pretending
  to solve the unreachable one (auto-retry-on-no-answer).

## Data & persistence

New `lib/services/primary_contact_prefs.dart`, mirroring `shake_prefs.dart`'s
shape:

```dart
class PrimaryContactPrefs {
  PrimaryContactPrefs._();

  static const _key = 'primary_contact_id';

  /// Null when no primary is set (or the stored id no longer matches any
  /// contact — callers treat both the same way).
  static final ValueNotifier<int?> id = ValueNotifier(null);

  static Future<void> load() async { ... }

  /// Pass null to clear (the "Remove as primary" action).
  static Future<void> set(int? contactId) async { ... }
}
```

## Call routing

`EmergencyAlert.callFirstContact` in `lib/services/emergency_alert.dart`
changes from unconditionally calling `list.first` to: read
`PrimaryContactPrefs.id.value`; if a contact in the list has that id, call
them; otherwise call `list.first`, exactly as today. This is the only
change to the alert pipeline — `sendTexts`/`sendBackground`'s SMS loop is
untouched.

## UI

`_ContactTile` (`lib/contact/personal_emergency_contacts.dart`) gains an
`isPrimary` bool and an `onTogglePrimary` callback. Its 46×46 avatar
`Container` is wrapped in a `Stack` with a small star badge
(`Positioned(bottom: -2, right: -2, child: ...)`, a filled circle with a
star icon in the app's amber accent) shown only when `isPrimary`.

`_menu()`'s bottom sheet gains one new `ListTile` — "Set as primary" (star
outline icon) when not primary, "Remove as primary" (filled star icon) when
it is — positioned above the existing Edit/Delete rows, since it changes
what an emergency call actually does, which is a more consequential action
than editing a name.

`_PersonalEmergencyContactsState` computes `isPrimary: contact.id ==
PrimaryContactPrefs.id.value` per row when building each `_ContactTile`,
and wraps the list in a listener on `PrimaryContactPrefs.id` (same
`ListenableBuilder`/`ValueListenableBuilder` pattern already used for
`ShakePrefs` elsewhere) so toggling primary updates the star immediately.

## Error handling

- Deleting the current primary contact requires no special-case code: the
  next rebuild finds no contact whose id matches
  `PrimaryContactPrefs.id.value`, so no star shows anywhere and
  `callFirstContact` naturally falls back to `list.first` — the exact same
  "no primary" path as if one had never been set.
- No guardians at all: unchanged from today — `callFirstContact` is never
  reached because `EmergencyAlert.send`/`sendBackground` already
  short-circuit on an empty contact list before attempting any call.

## Testing

- New `test/services/primary_contact_prefs_test.dart` (mirrors
  `shake_prefs_test.dart`): defaults to `null`; `set()` persists and
  survives a reload; `set(null)` clears a previously stored id.
- `test/services/emergency_alert_test.dart` gains cases: with a primary set
  matching a contact in the list, `callFirstContact` calls that contact's
  number, not `list.first`'s; with a primary set that matches no contact in
  the list, falls back to `list.first`; with no primary set, unchanged
  behavior (existing coverage already exercises this implicitly, but an
  explicit test locks in "no primary" as a real, intended case rather than
  just the absence of one).
- No new test for the `_ContactTile`/`_menu` UI wiring — verified on-device
  alongside the rest of this pass, same as the guardian sheet's own
  wiring today.
