# Check-in timer ("Walk me home") — design

**Date:** 2026-07-05 · **Status:** approved

## What

A card on the Track page: pick a duration (10/20/30/60 min presets, or a
custom value), optionally add a one-line note (e.g. "walking home from the
station"), and start a timer. Live location sharing turns on automatically
for the duration. A countdown shows on the card and in a persistent
notification, surviving the app being backgrounded or the phone locked. The
user cancels any time with an "I'm safe" tap. If the timer reaches zero
uncancelled, a 60-second grace-period warning fires (same shape as the
shake-to-SOS countdown) with a cancel action. If the grace period also
elapses, `EmergencyAlert.send()` fires — the same SMS + call pipeline as the
SOS button and shake-to-SOS — with the note appended to the SMS if one was
set. Live sharing stays on after a sent alert so guardians can follow the
map.

Out of scope: trip history/past-timer log, a "share ETA without a timer"
mode, editing a running timer's duration (cancel and restart instead),
guardian-side web view.

## Why this shape

- **One alert pipeline, always:** `EmergencyAlert.send()` is already the
  single code path shake-to-SOS and the SOS button share specifically so
  they can't drift apart. A missed check-in reusing it — rather than a
  distinct "softer" message — keeps that guarantee intact instead of
  creating a third, subtly different alert format to maintain.
- **Grace period, not instant alert:** the whole risk profile here is the
  opposite of an accidental SOS hold — the danger is a *forgotten* timer
  false-alarming a guardian for someone who arrived safely and forgot to
  cancel. A 60-second warning (mirroring `showSosCountdown`'s existing
  shape) catches that case the same way it already catches an accidental
  shake.
- **Live sharing bundled in:** the point of "walk me home" is a guardian
  being able to proactively check on you mid-trip, not only react after the
  fact. The Live Location toggle and its Firestore write path already exist
  on the same page — starting a timer just drives that toggle instead of
  building a second location-sharing mechanism.
- **One foreground service, not two:** `flutter_foreground_task` runs a
  single service per app, and shake-to-SOS already occupies it. Rather than
  fight the plugin for a second concurrent service, the existing
  `ShakeGuardService` gains a second, independent state machine
  (`CheckInTimerCore` alongside its existing `ShakeGuardCore`) and the
  persistent notification reflects whichever of the two are active. The
  class keeps its current name — renaming it to something feature-neutral
  would touch five files for no behavioral gain, so that's left alone.
- **Guardians checked once, at start:** shake-to-SOS gates every detected
  shake on `hasGuardians()` because a shake is passive — the user isn't
  choosing that moment. Starting a check-in timer is a deliberate action, so
  the same check happens once, before the timer starts (reusing
  `EmergencyAlert.hasGuardians()`, the same guard the SOS quick-actions
  already use) — `CheckInTimerCore` itself doesn't need a `hasGuardians`
  callback the way `ShakeGuardCore` does.

## Data & persistence

New `lib/services/checkin_prefs.dart`, mirroring `shake_prefs.dart`'s shape:

```dart
class CheckInPrefs {
  CheckInPrefs._();

  static const _endTimeKey = 'checkin_end_time_millis';
  static const _noteKey = 'checkin_note';

  /// Null when no timer is running. Holds the end-of-countdown instant (not
  /// a remaining Duration) so the true remaining time survives app restart
  /// or device reboot — recomputed as `endTime.difference(DateTime.now())`
  /// wherever it's read, never decremented in place.
  static final ValueNotifier<DateTime?> endTime = ValueNotifier(null);
  static final ValueNotifier<String?> note = ValueNotifier(null);

  static Future<void> load() async { ... } // mirrors ShakePrefs.load()

  static Future<void> start(Duration duration, {String? note}) async { ... }

  /// Clears both keys. Called on cancel, and after a sent alert once the
  /// notification has shown the "alert sent" state.
  static Future<void> clear() async { ... }
}
```

- Persisted as an epoch-millis int (`endTimeKey`) and an optional string
  (`noteKey`) — both cleared together, never one without the other.
- A missing `endTime` means "no timer running," including on a fresh
  install and after a reboot with no timer set — no separate "is running"
  boolean to drift out of sync with the timestamp.

## Core state machine

New `lib/services/checkin_timer_core.dart`, pure Dart (no plugin imports),
mirroring `ShakeGuardCore`'s shape but with two phases instead of one:

```dart
class CheckInTimerCore {
  CheckInTimerCore({
    required this.send,
    required this.onTick,       // void Function(Duration remaining) — main countdown
    required this.onGraceTick,  // void Function(int secondsRemaining) — 60s warning
    required this.onCancelled,
    required this.onSent,
    this.graceSeconds = 60,
  });

  final Future<void> Function() send;
  final void Function(Duration remaining) onTick;
  final void Function(int secondsRemaining) onGraceTick;
  final void Function() onCancelled;
  final void Function() onSent;
  final int graceSeconds;

  /// Starts (or restarts, after a reboot) counting down to [endTime].
  /// Ticks onTick once per second; at endTime, moves to the grace phase
  /// (ticks onGraceTick once per second); if grace also elapses, calls
  /// send() then onSent(). cancel() stops either phase and calls
  /// onCancelled() — never both onCancelled and onSent for the same run.
  void start(DateTime endTime) { ... }
  void cancel() { ... }
  void dispose() { ... }
}
```

- Recomputes remaining time from `endTime.difference(DateTime.now())` on
  every tick rather than counting down an in-memory integer — this is what
  makes recovering a timer after a reboot correct: the service restarts with
  `starter != TaskStarter.developer` (already how `onStart` detects an OS
  restart today), reads `CheckInPrefs.endTime` if non-null, and calls
  `start(endTime)` immediately, same as a fresh start.
- If `endTime` is already in the past when `start()` is called (device was
  off for the whole duration, or the app wasn't relaunched until well after
  expiry), it moves straight to evaluating the grace phase the same way,
  rather than a special case — a `Duration` in the past behaves like "zero
  remaining," which the tick logic already treats as "move to the next
  phase."

## UI

New card on `lib/pages/location_page.dart`, positioned after the existing
"Shake to SOS" card and before "RECENT PINGS" (same `LumiCard` pattern as
the other three cards):

- **Idle state:** title "Check-in timer", subtitle "Alert your guardians if
  you don't check in", a row of duration chips (10/20/30/60 min, `ChoiceChip`
  or the same `SegmentedButton` pattern as sensitivity) plus a "Custom…" chip
  that opens a small duration-only bottom sheet, an optional one-line note
  field, and a "Start" button.
- **Running state:** the chips/note are replaced by a live countdown
  ("Checking in in 12:34"), the note if set, and an "I'm safe — cancel"
  button (same visual treatment as `_SosCountdown`'s cancel button).
  Live-updates the countdown text via a local `Timer.periodic` in the page
  state, computed from `CheckInPrefs.endTime` — the page doesn't own the
  authoritative countdown, the service does; the page timer is purely a
  display refresh.
- Card is driven by `ListenableBuilder(listenable: CheckInPrefs.endTime, ...)`
  the same way the sensitivity picker already listens to `ShakePrefs`
  notifiers.

**Grace-period dialog (foreground only):** `showSosCountdown` is
generalized to accept the title/subtitle text as parameters (currently
hardcoded to "Shake detected" / "Alerting your guardians in") instead of
duplicating the whole widget for "Check-in missed" / "Alerting your
guardians in" — same countdown circle, same cancel button, different copy
and `seconds: 60` instead of `5`. When the app is backgrounded during the
grace period, the persistent notification carries the same cancel action
the shake countdown's notification already has.

## Extending `EmergencyAlert`

`buildAlertMessage(String? coords)` and `sendBackground({coordsFuture})` both
gain an optional `String? note` parameter. When present, it's appended to the
message as a new line (`'...find me: <link>\n<note>'`); when absent, the
message is byte-for-byte what it is today — the SOS button and shake-to-SOS
call sites pass no note and see no change. This is the only change to
`emergency_alert.dart`; the SMS/call mechanics themselves are untouched.

## Propagation & lifecycle

- `LocationPage`'s Start button calls `EmergencyAlert.hasGuardians()` first
  (blocking start with the existing "Add emergency contacts first" message
  if empty, matching `SosPage._handleAction`'s guard) then
  `CheckInPrefs.start(duration, note: note)`, then turns on Live Location the
  same way the existing Live Location switch does, then ensures the
  foreground service is running.
- **Service start/stop condition changes:** today `NavBarPage._syncShakeDetector`
  starts `ShakeGuardService` only when `ShakePrefs.enabled.value` is true,
  and stops it on logout or when shake is turned off. This becomes "start if
  shake-to-SOS is enabled **or** a check-in timer is running; stop only when
  both are false" — a small new `_syncGuardService()` helper (or inline
  check) replaces the single-condition version, so an active check-in timer
  keeps the service alive even with shake-to-SOS off, and vice versa.
- `NavBarPage` sends a new `'checkin:start:<endTimeMillis>:<note>'` message
  over the existing `sendDataToTask` channel (mirroring `notifySensitivity`),
  and `'checkin:cancel'` on cancel.
- `_ShakeGuardTaskHandler` gains a `CheckInTimerCore? _checkIn` alongside its
  existing `ShakeGuardCore? _core`, wired the same way: `onTick`/`onGraceTick`
  update the persistent notification text (combined with the shake-guard's
  own "Shake protection on" text when both are active), `onSent` calls
  `EmergencyAlert.send()` through the same `_sendAlert()` helper already
  used by shake-to-SOS (parameterized with the note, if any), and
  `onCancelled` resets the notification and calls `CheckInPrefs.clear()`.
- `onStart` (service (re)start, including after an OS-initiated restart)
  additionally reads `CheckInPrefs.endTime`; if non-null, calls
  `_checkIn.start(endTime)` immediately — this is what makes a running
  timer survive the foreground service itself being killed and restarted
  by Android.
- Cancelling from the notification's action button (grace phase) reaches
  `CheckInTimerCore.cancel()` the same way the existing `cancel_sos` button
  reaches `ShakeGuardCore.cancel()`.

## Error handling

- Starting with no guardians is blocked at the UI layer before any timer or
  service state changes — no partial "timer running with nobody to alert"
  state is reachable.
- If turning on Live Location fails (e.g. location permission denied), the
  timer still starts — sharing is a bonus, not a precondition; the same
  failure path the existing Live Location switch already has (a snackbar,
  no exception surfaced further) applies here too.
- A `CheckInPrefs.endTime` left over from a run that ended (sent or
  cancelled) but wasn't cleared for any reason is indistinguishable from a
  fresh start at that same instant — since `start()`'s past-endTime handling
  (above) treats an elapsed instant as "already in grace/expired," a stale
  value degrades to firing the grace phase promptly rather than staying
  silently stuck, instead of crashing or hanging.
- `EmergencyAlert.send()` failures during a check-in-triggered alert surface
  exactly like a shake-triggered one does today (`ShakeGuardService`'s
  existing `_sendAlert`'s try/catch and notification-text update) — no new
  failure surface.

## Testing

- New `test/services/checkin_timer_core_test.dart`, same `fake_async`-based
  approach as `shake_guard_core_test.dart`: starting counts down and ticks;
  reaching zero enters the grace phase and ticks there; grace reaching zero
  calls `send()` exactly once and `onSent()`; `cancel()` during either phase
  stops the timer and calls `onCancelled()` without ever calling `send()`;
  starting with an already-past `endTime` goes straight to grace-phase
  evaluation.
- New `test/services/checkin_prefs_test.dart`, mirroring
  `shake_prefs_test.dart`: `start()` persists both keys; `clear()` removes
  both; a fresh load with no stored value gives `endTime == null`.
- No unit test for the `TaskHandler` wiring or the two-services-in-one
  lifecycle change in `main_page.dart` — glue code, verified on-device:
  start a short (e.g. 1-minute) timer, background the app, confirm the
  notification counts down and the grace warning fires, cancel from the
  notification action, confirm no alert was sent (check guardian's SMS
  inbox is empty); separately, let a timer run to a full send with a safe
  placeholder guardian and confirm the SMS includes the note text.
