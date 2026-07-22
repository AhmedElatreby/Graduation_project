# SOS History Log — Design

**Date:** 2026-07-22
**Status:** Approved

## Purpose

A timeline of past alerts — when one was triggered, by which mechanism, and
whether it actually reached anyone. Closes the last gap in the app's
feature roadmap: right now `EmergencyAlert` persists nothing, so there is
no way to look back and confirm "did that shake/silent-trigger/SOS-hold
actually send."

## Decisions (agreed in brainstorming)

| Question | Decision |
|---|---|
| What's logged | Only actual sends (the two `EmergencyAlert.send()`/`sendBackground()` calls) — no cancelled countdowns from any trigger |
| Entry detail | Timestamp, trigger source, overall outcome (Sent / Failed + reason). No per-guardian breakdown, no note/location content |
| Storage | SQLite (new dedicated file/table) — proven to work from the background service isolate today (`sendBackground()` already calls `DBHelper().getContacts()` there); Firestore is not an option since that isolate never runs `Firebase.initializeApp()` |
| Retention | Bounded — keep the most recent 50 entries, prune older on insert |
| Zero-guardians attempts | Still logged, as a "Failed — Add emergency contacts first." entry — a real attempt that reached nobody is worth surfacing |
| UI placement | New 5th tab in the bottom nav bar: Track / SOS / Contacts / Map / **History** |
| Clear history | Yes — an app-bar action, confirm-then-wipe-all |

## Components

### 1. `AlertHistoryDb` — `lib/database/alert_history_db.dart`

A small dedicated SQLite helper, same shape as the existing `DBHelper`
(`lib/database/db_helper.dart`) but its own file/table — this codebase's
convention is one small focused file per concern (`ShakePrefs`,
`CheckInPrefs`, `FakeCallPrefs`, `SilentSosPrefs` are all separate files),
not bolting an unrelated table onto the contacts helper.

- DB file `AlertHistory.db`, table `alert_history`:
  `id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp INTEGER, trigger TEXT, outcome TEXT, detail TEXT`
  (`timestamp` stored as `millisecondsSinceEpoch`; `detail` nullable).
- `insert({required String trigger, required String outcome, String? detail})` —
  writes one row, then deletes any rows beyond the 50 most recent (by
  `timestamp DESC`).
- `getEntries()` — returns all rows, newest first.
- `clear()` — deletes all rows.

`trigger` values: `"SOS button"`, `"Shake to SOS"`, `"Check-in timer"`,
`"Silent SOS trigger"`. `outcome` values: `"Sent"`, `"Failed"`.

### 2. Instrumentation — `lib/services/emergency_alert.dart`

Single instrumentation point, not per-trigger: both `send()` (foreground —
used by the SOS button, foreground shake, and the silent trigger) and
`sendBackground()` (background — used by background shake and the
check-in timer) log exactly one entry right before returning, wrapped in
its own try/catch so a logging failure can never block or fail the alert
itself (same degrade-silently pattern already used on this path for
`LiveLocationService.start()` and `GuardianShare.createShareLink()`).

Because `send()`/`sendBackground()` don't currently know *which* UI
trigger called them, each call site passes a `trigger` string identifying
itself. The SOS button and the silent trigger each call `send()` with
their own distinct label; foreground and background shake both pass the
same `"Shake to SOS"` label regardless of which one fired (from the
user's perspective it's one feature, matching how the README already
describes it) — foreground shake calls `send()`, background shake calls
`sendBackground()`, same label either way. Check-in timer calls
`sendBackground()` with its own label. Outcome is
derived from the existing return shape: empty failure list → `"Sent"`,
non-empty → `"Failed"` with the first failure message as `detail`
(matches the "no guardians" case too, since that already returns
`['Add emergency contacts first.']` from the existing early-return).

### 3. `AlertHistoryPage` — `lib/pages/alert_history_page.dart`

- `ListView` of entries, newest first, wrapped in a `RefreshIndicator` for
  pull-to-refresh (the page lives in `NavBarPage`'s `IndexedStack`, which
  builds every tab once and keeps it alive — a plain re-fetch-on-visit
  wouldn't fire on tab switches, so pull-to-refresh is how you see a
  freshly-triggered alert without new reactive plumbing).
- Each row: trigger icon + label, a formatted timestamp (matching the
  existing app style, e.g. "Today 3:42 PM"), a colored outcome badge
  (green "Sent" / red "Failed"), and the `detail` line underneath when
  present.
- Empty state: "No alerts yet" (matches the existing empty-state copy
  style, e.g. `location_page.dart`'s "No locations shared yet").
- App-bar **Clear history** icon → `showDialog` confirm ("Clear alert
  history? This can't be undone.") → `AlertHistoryDb.clear()` → refresh.

### 4. Nav bar — `lib/navigation_bar/main_page.dart`

- `_pages` gains `const AlertHistoryPage()` as a 5th entry.
- `_LumiTabBar` gains a 5th `_tab(4, Icons.history_outlined, Icons.history, 'History')`,
  appended after the Map tab — the existing `spaceAround` `Row` layout
  accommodates a 5th child without restructuring.

## Error handling

- Every `AlertHistoryDb` write from `EmergencyAlert` is try/catch-wrapped;
  a SQLite failure (disk full, corrupt file, etc.) never blocks or fails
  the SMS/call attempt itself.
- `AlertHistoryPage` handles an empty table and a fresh-install (no DB
  file yet) identically via the empty state — no special-casing needed
  since `sqflite`'s `openDatabase` creates the file/table on first access.

## Testing

- **Unit (`AlertHistoryDb`)**: insert order (newest first), 50-entry cap
  prunes the oldest row on the 51st insert, `clear()` empties the table,
  using `sqflite_common_ffi` the same way the existing contacts-DB tests
  do.
- **Unit (`EmergencyAlert`)**: a successful `send()`/`sendBackground()`
  logs one `"Sent"` entry; a failure (including the no-guardians
  early-return) logs one `"Failed"` entry with the right `detail`; a
  logging-layer throw doesn't propagate out of either method (regression
  test: inject a failing `AlertHistoryDb` and assert `send()` still
  returns normally).
- **Widget (`AlertHistoryPage`)**: renders seeded entries; shows the empty
  state with none; pull-to-refresh re-queries; Clear history shows the
  confirm dialog, and confirming empties the list.
- **On-emulator checklist**: trigger a real send (SOS button or silent
  trigger) with the seeded placeholder guardian → open the History tab →
  confirm the entry appears with the correct trigger label and "Sent";
  trigger with guardians removed → confirm a "Failed — Add emergency
  contacts first." entry appears; Clear history → confirm the list
  empties and stays empty after an app restart (cold `am start`, not just
  hot reload).

## Out of scope

- Logging cancelled countdowns from any trigger.
- Per-guardian success/failure breakdown.
- Storing the note text or coordinates from a check-in-timer alert.
- Any cloud/Firestore sync of history (stays local-only, same trust
  boundary as the contacts DB).
