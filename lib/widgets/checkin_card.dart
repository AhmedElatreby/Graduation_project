// ─────────────────────────────────────────────────────────────────────────────
//  Lumi · Check-in timer card (Track page)
//  Display-only view over CheckInPrefs: phase and remaining time are pure
//  functions of the persisted endTime and the shared grace constant — the
//  service isolate's CheckInTimerCore is the only authority that ever sends
//  or cancels an alert. See docs/superpowers/specs/2026-07-12-checkin-card-
//  ui-design.md and the parent 2026-07-05 spec's UI section.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/checkin_prefs.dart';
import '../services/checkin_timer_core.dart';
import '../services/emergency_alert.dart';
import '../services/live_location_service.dart';
import '../services/shake_guard_service.dart';
import '../theme/lumi_theme.dart';
import 'lumi_widgets.dart';

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

class CheckInCard extends StatefulWidget {
  const CheckInCard({super.key});

  @override
  State<CheckInCard> createState() => _CheckInCardState();
}

class _CheckInCardState extends State<CheckInCard> {
  static const _presetMinutes = [10, 20, 30, 60];

  final _noteController = TextEditingController();
  Duration _selected = const Duration(minutes: 10);
  int? _customMinutes; // non-null when Custom… picked; shown on the chip
  Timer? _ticker; // 1s repaint while a timer runs — display only

  @override
  void initState() {
    super.initState();
    CheckInPrefs.endTime.addListener(_syncTicker);
    _syncTicker();
  }

  @override
  void dispose() {
    CheckInPrefs.endTime.removeListener(_syncTicker);
    _ticker?.cancel();
    _noteController.dispose();
    super.dispose();
  }

  void _syncTicker() {
    final running = CheckInPrefs.endTime.value != null;
    if (running && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!running) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  Future<void> _start() async {
    // Deliberate action → guardians checked once, up front (parent spec).
    if (!await EmergencyAlert.hasGuardians()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Add guardians first — no alert sent'),
        backgroundColor: LumiColors.accent.withValues(alpha: 0.9),
      ));
      return;
    }
    // Same permission set as the shake switch, requested before anything is
    // persisted — _startGuardIfPermitted assumes a running check-in always
    // had these granted up front.
    if (!kIsWeb && Platform.isAndroid) {
      final statuses = await ShakeGuardService.requestPermissions();
      if (!statuses.values.every((s) => s.isGranted)) {
        if (statuses.values.any((s) => s.isPermanentlyDenied)) {
          openAppSettings();
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text(
              'Lumi needs notification, SMS, phone and location access for check-in alerts'),
          backgroundColor: LumiColors.accent.withValues(alpha: 0.9),
        ));
        return;
      }
    }
    final note = _noteController.text.trim();
    await CheckInPrefs.start(_selected, note: note.isEmpty ? null : note);
    // NavBarPage's endTime listener starts the service + sends checkin_start.
    // Live sharing is a bonus, not a precondition — the timer is already
    // persisted; a sharing failure (permission, no Firebase) changes nothing.
    try {
      await LiveLocationService.start();
    } catch (_) {}
  }

  Future<void> _cancel() async {
    if (!kIsWeb && Platform.isAndroid) ShakeGuardService.notifyCheckInCancel();
    // The service clears prefs in its own isolate; this isolate's notifier
    // copy is separate — the local clear is what flips this card to idle.
    await CheckInPrefs.clear();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DateTime?>(
      valueListenable: CheckInPrefs.endTime,
      builder: (_, endTime, __) {
        final now = DateTime.now();
        return LumiCard(
          child: switch (checkInPhase(endTime, now)) {
            CheckInPhase.idle => _idle(),
            CheckInPhase.running => _running(endTime!, now),
            CheckInPhase.grace => _grace(endTime!, now),
          },
        );
      },
    );
  }

  Widget _header() => Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: LumiColors.green.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(Icons.timer_outlined,
                color: LumiColors.green, size: 20),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Check-in timer',
                    style: LumiText.body(14.5, weight: FontWeight.w700)),
                Text("Alert your guardians if you don't check in",
                    style: LumiText.body(12, color: LumiColors.textSub)),
              ],
            ),
          ),
        ],
      );

  Widget _idle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in _presetMinutes)
              ChoiceChip(
                label: Text('$m min'),
                selected: _customMinutes == null && _selected.inMinutes == m,
                onSelected: (_) => setState(() {
                  _customMinutes = null;
                  _selected = Duration(minutes: m);
                }),
              ),
            ChoiceChip(
              label: Text(
                  _customMinutes == null ? 'Custom…' : '$_customMinutes min'),
              selected: _customMinutes != null,
              onSelected: (_) => _pickCustomDuration(),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _noteController,
          maxLines: 1,
          style: LumiText.body(14, color: LumiColors.text),
          decoration: const InputDecoration(
            hintText: 'Note for guardians (optional)',
            prefixIcon: Icon(Icons.sticky_note_2_outlined, size: 20),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _start,
            style: ElevatedButton.styleFrom(
              backgroundColor: LumiColors.accent,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text('Start',
                style: LumiText.body(14.5,
                    weight: FontWeight.w700, color: Colors.white)),
          ),
        ),
      ],
    );
  }

  Widget _running(DateTime endTime, DateTime now) {
    final note = CheckInPrefs.note.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(),
        const SizedBox(height: 12),
        Text('Checking in in ${formatRemaining(endTime.difference(now))}',
            style: LumiText.display(22)),
        if (note != null) ...[
          const SizedBox(height: 4),
          Text(note, style: LumiText.body(12.5, color: LumiColors.textSub)),
        ],
        const SizedBox(height: 12),
        _cancelButton(),
      ],
    );
  }

  Widget _grace(DateTime endTime, DateTime now) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: LumiColors.accent, size: 22),
            const SizedBox(width: 9),
            Expanded(
              child: Text('Check-in missed',
                  style: LumiText.body(14.5,
                      weight: FontWeight.w700, color: LumiColors.accent)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
            'Check-in missed — alerting your guardians in '
            '${checkInGraceSecondsLeft(endTime, now)}s',
            style: LumiText.body(13, color: LumiColors.text)),
        const SizedBox(height: 12),
        _cancelButton(),
      ],
    );
  }

  Widget _cancelButton() => SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _cancel,
          style: ElevatedButton.styleFrom(
            backgroundColor: LumiColors.green,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: Text("I'm safe — cancel",
              style: LumiText.body(14.5,
                  weight: FontWeight.w700, color: Colors.white)),
        ),
      );

  Future<void> _pickCustomDuration() async {
    final picked = await showModalBottomSheet<Duration>(
      context: context,
      backgroundColor: LumiColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _CustomDurationSheet(),
    );
    if (picked == null) return;
    setState(() {
      _customMinutes = picked.inMinutes;
      _selected = picked;
    });
  }
}

/// Sheet content is a StatefulWidget so the controller outlives the sheet's
/// exit animation (disposing a controller from a builder local crashes the
/// close animation — established project rule).
class _CustomDurationSheet extends StatefulWidget {
  const _CustomDurationSheet();

  @override
  State<_CustomDurationSheet> createState() => _CustomDurationSheetState();
}

class _CustomDurationSheetState extends State<_CustomDurationSheet> {
  final _minutes = TextEditingController();

  @override
  void dispose() {
    _minutes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Keep the field above the keyboard.
      padding: EdgeInsets.fromLTRB(
          18, 18, 18, 18 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Custom duration', style: LumiText.display(18)),
          const SizedBox(height: 12),
          TextField(
            controller: _minutes,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: LumiText.body(15, color: LumiColors.text),
            decoration: const InputDecoration(
              hintText: 'Minutes (1–720)',
              prefixIcon: Icon(Icons.timer_outlined, size: 20),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                final m = int.tryParse(_minutes.text);
                if (m == null || m < 1 || m > 720) return;
                Navigator.pop(context, Duration(minutes: m));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: LumiColors.accent,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text('Set',
                  style: LumiText.body(14.5,
                      weight: FontWeight.w700, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
}
