# Silent SOS Trigger — Design

**Date:** 2026-07-20
**Status:** Approved

## Purpose

A discreet way to trigger a full SOS alert while the phone is in hand, screen
on, without an obvious tap-and-hold on the visible red SOS button — for a
moment where being seen reaching for "the emergency app" is itself risky
(e.g. mid-conversation with the person you're afraid of). Reuses the
existing `EmergencyAlert` pipeline end to end; this only adds a new trigger
into it, the same relationship shake-to-SOS has to the SOS button.

## Decisions (agreed in brainstorming)

| Question | Decision |
|---|---|
| Scenario | Screen on, phone in hand, foreground app only. Backgrounded/screen-off is out of scope (a possible later feature, like background shake-to-SOS was). |
| Trigger pattern | Volume-down × 3 within 1.5s |
| Platform | Android only |
| On-screen feedback | None — fully silent, haptic-only feedback throughout |
| System volume popup | Suppressed while the feature is enabled (native `dispatchKeyEvent` override); volume buttons behave completely normally while it's off |
| False-trigger safety | 8s silent grace period after arming; repeating the same 3× pattern during the grace cancels |
| Default state | Off — opt-in via a Track-page switch, unlike shake-to-SOS's default-on |

## Components

### 1. `SilentSosPrefs` — `lib/services/silent_sos_prefs.dart`

Single persisted bool, same shape as `ShakePrefs`:

- `static final ValueNotifier<bool> enabled` (default `false`)
- `load()` at startup, `setEnabled(bool)`

### 2. `SilentSosController` — `lib/services/silent_sos_controller.dart`

Pure Dart, `fake_async`-tested using the `clock` package (same technique as
`CheckInTimerCore`, which already depends on `clock` for testable
real-time countdown logic).

- `enum SilentSosPhase { idle, armed }`
- A sliding window of press timestamps: `onVolumeDownPress()` appends
  `clock.now()`, prunes entries older than 1.5s relative to the newest
  press, and when 3 remain, fires a match and clears the buffer.
- A match while `idle`: transition to `armed`, start an 8s `Timer`, call
  `onArmed()`.
- A match while `armed`: cancel the timer, transition to `idle`, call
  `onCancelled()`.
- The 8s timer elapsing: transition to `idle`, call `onSend()`.
- No persistence — matches `FakeCallController`'s reasoning: this is
  transient in-session state, not something that should survive a kill or
  fire later.

### 3. Native interception — `android/app/src/main/kotlin/.../MainActivity.kt`

Currently empty boilerplate (`class MainActivity: FlutterActivity() {}`).
Adds:

- A `MethodChannel` named `com.elatreby.safety/silent_sos`.
- Dart → native: `setEnabled(bool)` — stores a local flag.
- Override `dispatchKeyEvent(event: KeyEvent)`: if the flag is off, or the
  event isn't `KEYCODE_VOLUME_DOWN`, delegate to
  `super.dispatchKeyEvent(event)` unchanged (fail-safe default: normal
  volume behavior). If the flag is on, consume `ACTION_DOWN` events for
  `KEYCODE_VOLUME_DOWN` (return `true`, suppressing the system volume UI)
  and invoke the channel's `onVolumeDownPress` back into Dart; consume (but
  otherwise ignore) the matching `ACTION_UP` so no stray volume change or
  popup slips through on release.
- No new Android permission needed.

### 4. Wiring — `lib/navigation_bar/main_page.dart`

`NavBarPage` already hosts app-wide, always-mounted device-trigger wiring
(shake detection); this joins it there rather than in `SosPage`, since the
trigger must work from any tab.

- Owns one `SilentSosController`.
- A listener on `SilentSosPrefs.enabled` calls the native `setEnabled`
  method whenever the pref changes (and once at startup after load).
- The `MethodChannel`'s native→Dart handler calls
  `controller.onVolumeDownPress()`.
- `onArmed`: 3 short haptic pulses (`HapticFeedback.vibrate()`, ~120ms
  apart).
- `onCancelled`: 1 pulse.
- `onSend`: wrapped in `try/catch` (never throws past this point, same
  invariant as every other alert trigger); calls
  `EmergencyAlert.hasGuardians()` first — if false, a single long buzz and
  stop; otherwise `EmergencyAlert.send()`, then 2 slightly longer pulses on
  success or the same single long buzz on failure.

### 5. Track-page switch — `lib/pages/location_page.dart`

A new switch row beside "Shake to SOS," same visual style, default off:

- Label: "Silent SOS trigger"
- Description: "Press volume-down 3× to silently alert your guardians —
  press 3× again to cancel."
- Bound to `SilentSosPrefs.enabled` / `setEnabled`.

## Error handling

- Native side fails safe to "not intercepted" (see above) — a channel not
  yet ready, or any exception in the override, must never leave volume
  buttons stuck non-functional or leave the popup suppressed when the
  feature is meant to be off.
- `SilentSosController`'s `onSend` callback in `main_page.dart` is
  try/catch-wrapped around `EmergencyAlert.send()`, matching the existing
  pattern in `_onShake` and the SOS button's `_handleAction`.

## Testing

- **Unit (`fake_async` + `clock`)**: `SilentSosController` — 3 presses
  within 1.5s arms; presses spread further apart don't match and don't
  leave stale entries; a repeat pattern during the 8s grace cancels; grace
  elapsing fires `onSend` exactly once; a 4th/5th/6th stray press
  immediately after a match doesn't double-fire (buffer is cleared on
  every match).
- **Widget**: the Track-page switch — default off, persists via
  `SilentSosPrefs`, calling the native channel's `setEnabled` on toggle
  (mock the `MethodChannel` via `TestDefaultBinaryMessengerBinding`).
- **On-emulator checklist**: toggle on → `adb shell input keyevent
  KEYCODE_VOLUME_DOWN` ×3 quickly → confirm no system volume UI appears
  and the alert fires (observable via SMS content-provider check, same
  technique used for shake-to-SOS and check-in-timer verification) →
  repeat-pattern-cancels case (haptics aren't screenshot-verifiable, but
  the absence of a second alert is) → toggle off → confirm volume buttons
  raise/lower volume and show the system UI normally again.

## Out of scope

- Background / screen-off triggering (phone in pocket) — a possible later
  feature, analogous to how background shake-to-SOS shipped after
  foreground shake-to-SOS.
- iOS support.
- Any visible on-screen indicator, however subtle — fully haptic by
  design.
- A "test the pattern" button or in-app tutorial — parity with how
  shake-to-SOS ships with just a toggle and a description line.
