# Background shake-to-SOS (Android) — design

**Date:** 2026-07-04 · **Status:** approved

## What

On Android, shake detection keeps working while the app is backgrounded,
swiped away, or the screen is locked. A shake vibrates the phone and shows a
high-priority heads-up notification with a 5-second countdown and a big
"I'm safe — cancel" action. At zero the alert goes out: silent SMS to every
guardian (no composer) and a best-effort call to the first one.

**iOS is unchanged** (foreground-only shake, the existing in-app countdown).
iOS forbids programmatic SMS entirely, forbids auto-dialing from the
background, and suspends accelerometer delivery for backgrounded apps —
there is no App-Store-legal way to build this feature there.

Out of scope: restarting the service after device reboot, custom
sensitivity, any iOS background behaviour.

## Why this shape

- **Foreground service tied to the existing toggle:** Android requires a
  foreground service (with a persistent notification) for continuous sensor
  access. The Track-page "Shake to SOS" switch becomes the master switch:
  ON + signed in → service runs ("Lumi is protecting you" notification);
  OFF or logout → service stops. One switch, one meaning.
- **Dart isolate, not a Kotlin service:** `flutter_foreground_task` runs a
  Flutter engine inside the service, so the service reuses the `shake`
  detector and `lib/services/emergency_alert.dart` unchanged. A native
  service would duplicate the SMS/call/GPS logic in Kotlin — two code paths
  that drift.
- **Heads-up notification countdown, not a full-screen takeover:**
  full-screen intents are restricted on Android 14+ and add failure modes.
  A high-priority notification with a countdown and a cancel action works
  over the lock screen and other apps with no special permission.

## Architecture

```
ShakePrefs.enabled (existing ValueNotifier, persisted)
        │ ON + signed in → start / OFF or logout → stop
        ▼
ShakeGuardService (new, lib/services/shake_guard_service.dart)
  Android foreground service via flutter_foreground_task
  • runs its own ShakeDetector (same package, minimumShakeCount: 2)
  • receives app-resumed / app-paused pings from the main isolate and
    ignores shakes while the app is in the foreground
  • on background shake: vibration + countdown notification (5…4…3…)
      – "I'm safe — cancel" action → cancel, nothing sent, notification gone
      – zero → EmergencyAlert path (below), result notification
        ("Alert sent to your guardians" / failure strings)
        with a tap-to-call action when the auto-call was blocked
        • no guardians in the DB → no countdown; one "Add guardians first"
          notification instead
```

- **NavBarPage detector stays** — it is the iOS implementation and the
  Android *foreground* implementation (full-screen dialog). The service's
  resumed/paused gate guarantees exactly one path fires per shake.
- **EmergencyAlert grows one Android-only branch:** in the background path
  SMS must be silent — use `telephony`'s `sendSms` (already a dependency)
  instead of the `flutter_sms` composer. Foreground behaviour is untouched.
- **Auto-call is best-effort:** Android 10+ blocks activity launches from a
  backgrounded service. Attempt the call; if the OS refuses, the result
  notification carries a "Call <first guardian> now" tap action (a
  notification tap is an allowed launch path). SMS always goes out.
- The service isolate initialises Firebase and opens its own SQLite
  connection; `DBHelper` already supports that.

## Permissions (Android)

`SEND_SMS`, `CALL_PHONE`, `POST_NOTIFICATIONS` (13+), `FOREGROUND_SERVICE`
plus the Android 14 service-type declaration, and optionally
`ACCESS_BACKGROUND_LOCATION` — without it the SMS uses the existing
"location unavailable" wording. Runtime requests happen when the user flips
the toggle ON; if a required permission is denied the toggle flips back OFF
with an explanatory snackbar.

## Error handling

- No guardians → no countdown in the background; a single "Add guardians
  first" notification. (Foreground gets the same guard before showing the
  in-app countdown — fixes the existing wart where the countdown ran and
  then said "Add emergency contacts first.")
- Send failures reuse the failure strings `EmergencyAlert.send()` already
  returns, shown in the result notification.
- Service killed by the OS → `flutter_foreground_task` auto-restart stays
  on; if the user revokes a permission mid-flight the next start re-checks
  and flips the toggle OFF.

## Testing

- Unit tests for the service-side countdown/dispatch state machine: cancel
  never sends (even past the original deadline); zero sends exactly once;
  shakes while the app is resumed are ignored; no-guardians short-circuits.
- Widget test for the new foreground no-guardians guard.
- End-to-end on the Android emulator: `adb emu sensor` can synthesize real
  accelerometer shakes, so background detection, the notification countdown,
  cancel, and the SMS path are all demoable without a physical device.