# Shake sensitivity — design

**Date:** 2026-07-05 · **Status:** approved

## What

A Low / Medium / High sensitivity picker for shake-to-SOS, on the Track page
directly under the existing "Shake to SOS" switch. It controls how hard a
shake must be to count, on both the in-app detector (all platforms) and the
Android background service. Shake *count* (2 in a row) stays fixed — this
only tunes force.

Out of scope: exposing raw gravity numbers or a slider, a separate settings
screen, per-shake-count tuning.

## Why this shape

- **Three presets, not a slider:** the underlying knob is a gravity-force
  threshold (`2.0`–`3.5`g) that means nothing to a non-technical user. Low/
  Medium/High with everyday framing ("harder to trigger" / "easier to
  trigger") is what the Track-page toggle's audience — people who get false
  triggers while running or cycling — actually needs.
- **Medium = today's behavior:** the `shake` package's own default threshold
  is `2.7`g, which is what every existing install already runs at (neither
  call site currently overrides it). Mapping Medium to `2.7`g means this
  feature ships with zero behavior change for anyone who doesn't touch the
  new control.
- **`ShakeGuardCore` is untouched:** the core state machine (countdown,
  cancel, dispatch) only ever reacts to "a shake was detected" — it has no
  opinion on how sensitive detection is. Sensitivity is entirely a
  `ShakeDetector` construction concern, so this feature is additive at the
  two places a `ShakeDetector` gets created and nowhere else.
- **Live-push to the background service:** the on/off toggle already has a
  live IPC channel to the running Android service (`notifyLifecycle` over
  `sendDataToTask`). Reusing that pattern for sensitivity means a user who
  adjusts it while already protected sees it take effect immediately,
  consistent with how the toggle itself behaves — not "changes apply after
  you restart something."

## Data & persistence

`lib/services/shake_prefs.dart` gains:

```dart
enum ShakeSensitivity { low, medium, high }

/// Force threshold — 2.0g (High) is easier to trigger than 3.5g (Low).
/// Shake *count* stays fixed at 2 everywhere; this only tunes force.
double thresholdFor(ShakeSensitivity level) => switch (level) {
      ShakeSensitivity.low => 3.5,
      ShakeSensitivity.medium => 2.7, // the shake package's own default
      ShakeSensitivity.high => 2.0,
    };
```

- `ShakePrefs.sensitivity`: `ValueNotifier<ShakeSensitivity>`, default
  `medium`, loaded in the existing `ShakePrefs.load()` alongside `enabled`.
- Persisted as a string (`'low' | 'medium' | 'high'`) under a new
  `shake_sensitivity` key via `setSensitivity(ShakeSensitivity)`, mirroring
  the existing `setEnabled(bool)`.
- An unreadable/missing stored value falls back to `medium` — never crashes
  on a corrupt or pre-feature prefs store.

## UI

On `lib/pages/location_page.dart`, directly below the existing "Shake to
SOS" `Switch` row: a `SegmentedButton<ShakeSensitivity>` (Low | Medium |
High) bound to `ShakePrefs.sensitivity`, `onChanged` calling
`ShakePrefs.setSensitivity`. Disabled (not hidden — hiding it would jump the
layout) whenever `ShakePrefs.enabled.value` is `false`, matching the existing
convention that sub-controls of an OFF feature go visually inert rather than
disappear.

## Propagation

**Foreground (`NavBarPage`, all platforms):** `_syncShakeDetector` already
rebuilds `_shakeDetector` from scratch on every call and already listens to
`ShakePrefs.enabled`. It adds a listener on `ShakePrefs.sensitivity` too (both
listeners call the same `_syncShakeDetector`), and passes
`shakeThresholdGravity: thresholdFor(ShakePrefs.sensitivity.value)` into
`ShakeDetector.autoStart`. Because `ShakeDetector`'s fields are `final`,
"changing" sensitivity means `stopListening()` the old instance and construct
a new one — exactly what `_syncShakeDetector` already does for the on/off
toggle, so no new lifecycle shape is introduced.

**Background (`ShakeGuardService`, Android):**
- `onStart` reads `ShakePrefs.sensitivity.value` once (the service isolate
  has its own `SharedPreferences` access, same as `EmergencyAlert` already
  does) and passes the matching threshold into its own
  `ShakeDetector.autoStart`.
- New `ShakeGuardService.notifySensitivity(ShakeSensitivity level)` sends
  `'sensitivity:${level.name}'` over the existing `sendDataToTask` channel.
- `_ShakeGuardTaskHandler.onReceiveData` gets a new branch: on a
  `sensitivity:*` message, `stopListening()` the current detector and
  construct a replacement with the new threshold — the same
  stop-and-replace shape as the foreground path, just triggered by an IPC
  message instead of a `ValueNotifier` callback.
- `NavBarPage` calls `ShakeGuardService.notifySensitivity` from the same
  place it already reacts to `ShakePrefs.sensitivity` changes, Android-only
  guarded like every other service call site.

## Error handling

- No new failure modes: sensitivity only changes a constructor argument to
  an already-battle-tested `ShakeDetector`. If the background service isn't
  running, `notifySensitivity`'s `sendDataToTask` call is a no-op (confirmed
  behavior of `flutter_foreground_task`, already relied on by
  `notifyLifecycle`).
- A corrupted/unrecognized persisted sensitivity string decodes to `medium`
  rather than throwing.

## Testing

- Unit tests (new `test/services/shake_prefs_test.dart` cases, following the
  file's existing pattern): `thresholdFor` returns the three documented
  values; `ShakePrefs.sensitivity` defaults to `medium`; `setSensitivity`
  persists and survives a reload; an unrecognized stored string falls back
  to `medium`.
- No unit test for the detector/service wiring (`_syncShakeDetector`'s
  rebuild, the `TaskHandler`'s `onReceiveData` branch) — this is glue code
  in the same category as the rest of `shake_guard_service.dart`, verified
  by emulator end-to-end instead: three synthesized shake bursts of
  increasing force, one per sensitivity level, confirming a soft burst that
  Low ignores is caught by High, both in the foreground dialog and the
  background notification countdown.
