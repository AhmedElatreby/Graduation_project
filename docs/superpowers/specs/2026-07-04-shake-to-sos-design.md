# Shake-to-SOS — design

**Date:** 2026-07-04 · **Status:** approved

## What

Shaking the phone (while the app is open and the user is signed in) opens a
full-screen 5-second countdown with a large Cancel button. If the countdown
reaches zero, the app sends the full emergency alert — the same SMS + call
flow as holding the SOS button. A "Shake to SOS" switch on the Track page
(default ON, persisted) lets users who get false triggers turn it off.

Out of scope: background shake detection (needs a foreground service /
motion entitlements), custom sensitivity settings.

## Why this shape

- **Countdown, not instant send:** accelerometers false-positive (phone
  tossed on a bed, running). A cancellable countdown with loud haptics is
  the standard safety-app pattern — fast when real, forgiving when not.
- **Detector lives in NavBarPage:** it hosts all four tabs, so shake works
  anywhere in the signed-in app; it dies with the page on logout.
- **Alert logic extracted to a service:** the SMS/call/GPS code currently
  lives inside `_SosPageState`; both the hold-button and the shake flow
  need it, so it moves to `lib/services/emergency_alert.dart`.

## Components

| Piece | Responsibility |
|---|---|
| `lib/services/emergency_alert.dart` | `EmergencyAlert.send()` — contacts lookup, best-effort coordinates (live GPS, 8s limit → own Firestore doc → none), SMS to all guardians, call to first guardian. Returns a list of human-readable failure strings (empty = full success). No BuildContext. |
| `lib/services/shake_prefs.dart` | `ShakePrefs.enabled` — `ValueNotifier<bool>` backed by shared_preferences, default true. |
| `lib/widgets/sos_countdown.dart` | `showSosCountdown(context, onSend)` — full-screen barrier-dismiss-proof dialog: count 5→0, heavy haptic per tick, giant Cancel. Zero → pops and invokes `onSend`. Cancel → pops, nothing sent. |
| `NavBarPage` | Owns a `ShakeDetector` (package `shake`), started/stopped by `ShakePrefs.enabled`. On shake: if a countdown isn't already open, switch to the SOS tab and show the countdown; on send, run `EmergencyAlert.send()` and surface failures in a snackbar. |
| Track page | Third `LumiCard`: "Shake to SOS / Shake your phone to trigger an alert" + `Switch` bound to `ShakePrefs`. |

`sos.dart` shrinks: `_triggerFullAlert`, `_sendTextsToContacts`,
`_callEmergencyContact`, `_currentCoordinates` are replaced by a call to
`EmergencyAlert.send()`.

## Dependencies

Re-add `shake` (^3.x), add `shared_preferences` (^2.x).

## Error handling

Identical to the hold-button path: SMS and call attempted independently;
failures joined into one red snackbar. Repeat shakes ignored while the
countdown is showing (guard flag).

## Testing

Widget tests (the iOS **simulator has no accelerometer**, so real shakes
need a physical device — the detector wiring is kept thin and its handler
is invoked directly in tests):

1. Countdown: Cancel before zero → dialog closes, `onSend` never called.
2. Countdown: reaching zero → `onSend` called exactly once.
3. Track toggle: flips `ShakePrefs.enabled` and persists.
4. Existing suite stays green (SOS refactor must not change hold-button
   behaviour).
