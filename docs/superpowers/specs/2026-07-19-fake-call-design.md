# Fake Incoming Call — Design

**Date:** 2026-07-19
**Status:** Approved

## Purpose

A one-tap staged incoming call so someone in an uncomfortable situation can
"take a call" and leave. Purely cosmetic by design: it never touches
`EmergencyAlert`, guardians, the foreground service, or any alert path —
nothing about it can misfire a real alert.

## Decisions (agreed in brainstorming)

| Question | Decision |
|---|---|
| Trigger | Fourth quick action on the SOS page + delay picker sheet (Now / 10s / 30s / 1 min, default 10s) |
| Caller identity | User-configurable name + number, persisted; defaults to "Mom" and a plausible number |
| Realism | Full-screen incoming-call page with system ringtone + vibration, Answer/Decline; answering shows an in-call screen with running timer and cosmetic mute/speaker/keypad |
| Locked phone | In-app only for now. No foreground-service routing, no full-screen-intent notification. Locked-pocket support is a possible later upgrade riding `ShakeGuardService`. |
| Ring sound | `flutter_ringtone_player` — plays the device's system default ringtone with looping + vibration. |

## Components

All plain Flutter; no service-isolate involvement.

### 1. `FakeCallPrefs` — `lib/services/fake_call_prefs.dart`

Persisted caller identity, same shape as `ShakePrefs`/`CheckInPrefs`:

- `static final ValueNotifier<String> callerName` (default `Mom`)
- `static final ValueNotifier<String> callerNumber` (default a plausible
  local-format number, e.g. `07700 900123`)
- `load()` at startup (`main.dart`, beside the other prefs), `setCaller(name, number)`.

### 2. Delay sheet + quick action — `lib/pages/sos.dart`

- The quick-action row becomes a 2×2 grid: Send SMS, Call, Siren, **Fake
  Call** (icon `Icons.phone_callback`), styled like the existing
  `_QuickAction`s.
- Tapping Fake Call opens a bottom sheet: title "Fake incoming call",
  subtitle "Stage a call to step away", delay chips (Now / 10s / 30s /
  1 min, default 10s), a caller row showing the current name/number with an
  edit affordance (inline text fields), and a **Ring me** button.
- Editing the caller persists via `FakeCallPrefs` immediately (survives
  the sheet closing).

### 3. `FakeCallController` — `lib/services/fake_call_controller.dart`

Pure Dart (plugin-free), `fake_async`-tested, mirroring the
`CheckInTimerCore` pattern:

- Phases: `idle → scheduled → ringing → inCall → idle`.
- `schedule(Duration delay)` — starts the delay `Timer`; scheduling while
  one is pending replaces it (old timer cancelled).
- `cancel()` — from `scheduled`, back to idle.
- Callbacks: `onRing` (navigate + start sound), `onTick(remaining)` for the
  countdown pill.
- App-wide singleton so tab navigation doesn't lose the pending call.
- Deliberately **not persisted**: an in-app cosmetic feature dies with the
  app. Nothing survives a kill; nothing rings later.

### 4. Call screens — `lib/pages/fake_call_page.dart`

- **`IncomingCallPage`**: full-screen dark page pushed on the root
  navigator, not dismissible by back gesture (Decline is the only exit,
  like a real call). Large caller name, number beneath, avatar circle with
  initial, "Mobile · Incoming call" caption. Ringtone + vibration start on
  push, stop on Answer/Decline/dispose.
- **`InCallPage`**: running `0:00` timer, cosmetic mute/speaker/keypad
  toggles (visual state only), red hang-up button pops back to the
  previous screen.

### 5. Sound seam — `FakeCallSounds`

Thin wrapper interface over `flutter_ringtone_player`
(`start({looping, vibrate})` / `stop()`) so widget tests inject a fake and
assert start/stop, and so a plugin failure on odd OEMs degrades to a
vibration-only loop (a periodic `HapticFeedback.vibrate()` timer owned by
`IncomingCallPage`) — catch, fall back, never crash mid-performance.

## UX details

- While scheduled, the SOS page shows a subtle countdown pill under the
  quick actions — "📞 in 0:08 · tap to cancel" — not a loud banner; the
  whole point is discretion.
- Ring while app backgrounded (timer fired unseen): the call screen shows
  when the user returns. Accepted in-app limitation, noted here.
- No wakelock: delays are ≤60s and the user is holding the phone; if the
  screen times out mid-delay this is the same accepted limitation.
- Siren collision: if the siren is playing, leave it playing (safety beats
  cosmetics); the ringtone just joins it.
- A real incoming call needs no handling — the OS call UI takes over.

## Error handling

- `flutter_ringtone_player` failure → catch, vibration-only fallback.
- All fake-call code is UI-side and cannot throw into any alert path
  (it never runs in one).

## Testing

- **Unit (`fake_async`)**: `FakeCallController` — schedule→ring at the
  right time, tick stream, cancel, replace-on-reschedule, no ring after
  cancel.
- **Widget**: sheet chip selection and default; caller edit persists via
  mocked SharedPreferences; countdown pill renders and cancels; Decline
  pops without pushing InCallPage; Answer pushes InCallPage with a running
  timer; sounds fake asserts start on push and stop on both exits.
- **On-emulator checklist**: quick action → sheet → 10s delay → pocket-sim
  (home button) → reopen → ring with audible system ringtone → answer →
  timer runs → hang up returns to SOS page; Decline path; cancel-from-pill
  path.

## Out of scope

- Locked-screen / full-screen-intent ringing (possible later upgrade).
- Fake voice audio on answer.
- Scheduling beyond 1 minute.
- iOS-style call skinning (generic dark call UI, not a pixel copy of any
  OS dialer).
