# Check-in timer — Track-page card (UI) — design addendum

**Date:** 2026-07-12 · **Status:** approved
**Parent spec:** [2026-07-05-checkin-timer-design.md](2026-07-05-checkin-timer-design.md)

Everything except the Track-page card from the parent spec is built and
committed (core, prefs, EmergencyAlert note, service wiring, NavBarPage
lifecycle). This addendum records the three implementation decisions the
parent spec's UI section left open; the card's states, copy, placement, and
data flow are exactly as written there and are not restated.

## Decisions

1. **File placement.** The card is a public `CheckInCard` widget in a new
   `lib/widgets/checkin_card.dart`, inserted into `location_page.dart`
   between the Shake-to-SOS card and RECENT PINGS. `location_page.dart` is
   already ~450 lines; a separate file keeps the card independently
   widget-testable and the page readable. The custom-duration bottom sheet
   is its own `StatefulWidget` in the same file, and the note field's
   `TextEditingController` is owned by the card's `State` (never a local in
   a sheet builder — controllers disposed from a builder crash on the
   sheet's exit animation).

2. **Cancel flow.** "I'm safe — cancel" calls
   `ShakeGuardService.notifyCheckInCancel()` and then `CheckInPrefs.clear()`
   locally. The service's own `onCancelled` clears prefs too, but only in
   the service isolate — each isolate has its own copy of the
   `ValueNotifier`s, so the local clear is what flips the card back to idle
   immediately. Both clears are idempotent; ordering between them doesn't
   matter.

3. **Permissions on Start.** Starting a timer requests the same Android
   permission set the shake switch does (notification, SMS, phone,
   location-when-in-use) before persisting anything. The request block in
   `_LocationPageState._setShakeEnabled` moves to a new
   `ShakeGuardService.requestPermissions()` beside the existing
   `hasRequiredPermissions()` (the service already owns the list of what it
   needs); both the shake switch and the card's Start button call it, and
   each call site keeps its own snackbar/openAppSettings handling. If any
   permission is denied, the timer does not start — matching
   `_startGuardIfPermitted`'s assumption that a running check-in always had
   its permissions granted up front.

## Testing

New `test/widgets/checkin_card_test.dart`:

- Idle state renders chips/note/Start; Start with an empty contact book
  shows the "add contacts" message and starts nothing (contact book seeded
  via the same sqflite-ffi helpers `emergency_alert_test.dart` uses).
- Start with a guardian persists `CheckInPrefs.endTime` and shows the
  running state with a ticking countdown.
- Cancel returns to idle and clears `CheckInPrefs`.
- An `endTime` just past expiry renders the grace-warning state with the
  parent spec's copy.

On-device verification stays as written in the parent spec's Testing
section (notification countdown, grace warning, cancel-from-notification,
full send with a placeholder guardian).
