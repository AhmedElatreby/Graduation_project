// ─────────────────────────────────────────────────────────────────────────────
//  Lumi · Check-in timer card (Track page)
//  Display-only view over CheckInPrefs: phase and remaining time are pure
//  functions of the persisted endTime and the shared grace constant — the
//  service isolate's CheckInTimerCore is the only authority that ever sends
//  or cancels an alert. See docs/superpowers/specs/2026-07-12-checkin-card-
//  ui-design.md and the parent 2026-07-05 spec's UI section.
// ─────────────────────────────────────────────────────────────────────────────
import '../services/checkin_timer_core.dart';

enum CheckInPhase { idle, running, grace }

/// Which of the card's three states to show. Deliberately has no "expired"
/// value: once the grace window has fully elapsed the service is sending (or
/// has sent and will clear the prefs); until that clear lands the card keeps
/// showing the grace warning at 0s rather than inventing a fourth state.
CheckInPhase checkInPhase(DateTime? endTime, DateTime now) {
  if (endTime == null) return CheckInPhase.idle;
  if (endTime.isAfter(now)) return CheckInPhase.running;
  return CheckInPhase.grace;
}

/// Whole seconds left in the grace window, rounded up to match
/// CheckInTimerCore's onGraceTick ceil-ing, clamped at 0.
int checkInGraceSecondsLeft(DateTime endTime, DateTime now) {
  final deadline =
      endTime.add(const Duration(seconds: CheckInTimerCore.defaultGraceSeconds));
  final leftMs = deadline.difference(now).inMilliseconds;
  return leftMs <= 0 ? 0 : (leftMs / 1000).ceil();
}

/// `m:ss` (`h:mm:ss` above an hour), clamped at `0:00`.
String formatRemaining(Duration d) {
  final total = d.inSeconds < 0 ? 0 : d.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}