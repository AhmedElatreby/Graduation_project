// ─────────────────────────────────────────────────────────────────────────────
//  Lumi · Track (live-location tab)
//  Replaces:  lib/pages/location_page.dart
//  Returns CONTENT only. Keeps your location stream + Firestore writes.
//  ★ #6  Siren now uses the app-wide Siren singleton, so it keeps playing until
//        the clip finishes even if you leave this screen.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';
import 'dart:io' show Platform;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/checkin_prefs.dart';
import '../services/checkin_timer_core.dart' show CheckInTimerCore;
import '../services/emergency_alert.dart';
import '../services/live_location_service.dart';
import '../services/shake_guard_service.dart';
import '../services/shake_prefs.dart';
import '../services/siren.dart';
import '../theme/lumi_theme.dart';
import '../widgets/lumi_widgets.dart';

class LocationPage extends StatefulWidget {
  const LocationPage({super.key});
  @override
  State<LocationPage> createState() => _LocationPageState();
}

class _LocationPageState extends State<LocationPage> {
  // Location docs are keyed by the signed-in user's uid so each user only
  // ever touches their own document (was a single shared 'user1' doc that
  // every account overwrote and could read).
  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  Timer? _checkInDisplayTimer; // purely a 1x/sec UI refresh, see below

  @override
  void initState() {
    super.initState();
    _requestPermission();
    _checkInDisplayTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    // NOTE: we intentionally do NOT stop the siren here — it should keep playing
    // even if you leave this tab.
    _checkInDisplayTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // NavBarPage's Scaffold uses extendBody: true, which makes Flutter inject
    // the bottomNavigationBar's actual rendered height into MediaQuery's
    // bottom padding for this body subtree specifically so children can
    // reserve space for it — SafeArea consumes exactly that value, so the
    // scroll viewport stays clear of the bar on every device without
    // guessing at its height ourselves.
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text('Live tracking', style: LumiText.display(24)),
              ),
              const SizedBox(height: 12),

              // map preview (decorative — tap to open full Map tab if you wire it)
              ValueListenableBuilder<bool>(
                valueListenable: LiveLocationService.isLive,
                builder: (_, isLive, __) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _MapPreview(isLive: isLive),
                    const SizedBox(height: 10),

                    // live toggle
                    LumiCard(
                      child: Row(
                        children: [
                          _TileIcon(
                              icon: Icons.my_location,
                              bg: LumiColors.accent.withValues(alpha: 0.14),
                              fg: LumiColors.accent),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Live location',
                                    style: LumiText.body(14.5,
                                        weight: FontWeight.w700)),
                                Text(isLive ? 'Sharing now' : 'Off',
                                    style: LumiText.body(12,
                                        color: LumiColors.textSub)),
                              ],
                            ),
                          ),
                          Switch(
                            value: isLive,
                            activeThumbColor: Colors.white,
                            activeTrackColor: LumiColors.accent,
                            onChanged: (v) => v
                                ? LiveLocationService.start()
                                : LiveLocationService.stop(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 9),

              // siren
              LumiCard(
                child: Row(
                  children: [
                    _TileIcon(
                        icon: Icons.campaign_outlined,
                        bg: LumiColors.amber.withValues(alpha: 0.14),
                        fg: LumiColors.amber),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Loud siren',
                              style:
                                  LumiText.body(14.5, weight: FontWeight.w700)),
                          Text('Scare off & draw attention',
                              style:
                                  LumiText.body(12, color: LumiColors.textSub)),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: _siren,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: LumiColors.amber.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text('Play',
                            style: LumiText.body(13,
                                weight: FontWeight.w700,
                                color: LumiColors.amber)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 9),

              // shake-to-SOS
              LumiCard(
                child: Column(
                  children: [
                    Row(
                      children: [
                        _TileIcon(
                            icon: Icons.vibration,
                            bg: LumiColors.blue.withValues(alpha: 0.14),
                            fg: LumiColors.blue),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Shake to SOS',
                                  style: LumiText.body(14.5,
                                      weight: FontWeight.w700)),
                              Text('Shake your phone to trigger an alert',
                                  style: LumiText.body(12,
                                      color: LumiColors.textSub)),
                            ],
                          ),
                        ),
                        ValueListenableBuilder<bool>(
                          valueListenable: ShakePrefs.enabled,
                          builder: (_, on, __) => Switch(
                            value: on,
                            activeThumbColor: Colors.white,
                            activeTrackColor: LumiColors.blue,
                            onChanged: _setShakeEnabled,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ListenableBuilder(
                      listenable: Listenable.merge(
                          [ShakePrefs.enabled, ShakePrefs.sensitivity]),
                      builder: (_, __) => IgnorePointer(
                        ignoring: !ShakePrefs.enabled.value,
                        child: Opacity(
                          opacity: ShakePrefs.enabled.value ? 1 : 0.4,
                          child: SegmentedButton<ShakeSensitivity>(
                            // The selected fill color already shows which
                            // segment is picked, so the default checkmark's
                            // reserved space on every segment is redundant —
                            // on a real device's narrower effective width it
                            // was enough to wrap "Medium" onto two lines.
                            showSelectedIcon: false,
                            segments: const [
                              ButtonSegment(
                                  value: ShakeSensitivity.low,
                                  label: Text('Low')),
                              ButtonSegment(
                                  value: ShakeSensitivity.medium,
                                  label: Text('Medium')),
                              ButtonSegment(
                                  value: ShakeSensitivity.high,
                                  label: Text('High')),
                            ],
                            selected: {ShakePrefs.sensitivity.value},
                            onSelectionChanged: ShakePrefs.enabled.value
                                ? (s) => ShakePrefs.setSensitivity(s.first)
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 9),

              // check-in timer
              LumiCard(
                child: ListenableBuilder(
                  listenable: CheckInPrefs.endTime,
                  builder: (_, __) => _buildCheckInCard(),
                ),
              ),
              const SizedBox(height: 14),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text('RECENT PINGS',
                    style: LumiText.body(12,
                        weight: FontWeight.w700, color: LumiColors.textFaint)),
              ),
              const SizedBox(height: 8),
              // Only the signed-in user's own document — streaming the whole
              // collection here used to show every user's live coordinates to
              // everyone (and Firestore rules now forbid it anyway).
              //
              // Plain widget, not Expanded/ListView: this only ever renders a
              // single card, so a bounded-height scrolling list was never
              // needed — the page-level SingleChildScrollView above already
              // handles the case where content doesn't fit.
              _uid == null
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text('Sign in to see your pings',
                            style:
                                LumiText.body(13, color: LumiColors.textSub)),
                      ),
                    )
                  : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('location')
                          .doc(_uid)
                          .snapshots(),
                      builder: (context, snap) {
                        if (!snap.hasData) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                                child: CircularProgressIndicator(
                                    color: LumiColors.accent)),
                          );
                        }
                        final data = snap.data!.data();
                        if (data == null) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: Text('No locations shared yet',
                                  style: LumiText.body(13,
                                      color: LumiColors.textSub)),
                            ),
                          );
                        }
                        final lat = data['latitude'];
                        final lng = data['longitude'];
                        return Container(
                          padding: const EdgeInsets.all(13),
                          decoration: BoxDecoration(
                            color: LumiColors.surface2,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.location_on,
                                  color: LumiColors.accent, size: 18),
                              const SizedBox(width: 11),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('You',
                                        style: LumiText.body(13,
                                            weight: FontWeight.w600)),
                                    Text('$lat, $lng',
                                        style: LumiText.body(11,
                                            color: LumiColors.textSub)),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right,
                                  color: LumiColors.textFaint, size: 18),
                            ],
                          ),
                        );
                      },
                    ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }

  // ── logic (yours, trimmed) ──────────────────────────────────────────────────
  Future<void> _siren() async {
    await Siren.instance.play(); // keeps playing after you leave this screen
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Siren activated!'),
      backgroundColor: LumiColors.amber.withValues(alpha: 0.9),
    ));
  }

  Future<void> _requestPermission() async {
    final status = await Permission.location.request();
    if (status.isPermanentlyDenied) openAppSettings();
  }

  /// Android background SOS needs notification + SMS + phone + location
  /// permissions (location: the service declares the location type so GPS
  /// keeps working in the background). Deny any and the switch stays OFF
  /// with an explanation.
  Future<void> _setShakeEnabled(bool value) async {
    if (!value || kIsWeb || !Platform.isAndroid) {
      await ShakePrefs.setEnabled(value);
      return;
    }
    final statuses = await ShakeGuardService.requestPermissions();
    if (statuses.values.every((s) => s.isGranted)) {
      await ShakePrefs.setEnabled(true);
      return;
    }
    if (statuses.values.any((s) => s.isPermanentlyDenied)) {
      openAppSettings();
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text(
          'Lumi needs notification, SMS, phone and location access for background SOS'),
      backgroundColor: LumiColors.accent.withValues(alpha: 0.9),
    ));
  }

  // ── check-in timer card ─────────────────────────────────────────────────

  Widget _buildCheckInCard() {
    final end = CheckInPrefs.endTime.value;
    if (end == null) return _checkInIdle();

    final remaining = end.difference(DateTime.now());
    if (remaining > Duration.zero) return _checkInRunning(remaining);

    final graceRemaining = end
        .add(const Duration(seconds: CheckInTimerCore.defaultGraceSeconds))
        .difference(DateTime.now());
    if (graceRemaining > Duration.zero) {
      return _checkInGrace((graceRemaining.inMilliseconds / 1000).ceil());
    }
    // The service hasn't yet cleared CheckInPrefs for a run that already
    // sent — show grace-expired briefly rather than a stale running state.
    return _checkInGrace(0);
  }

  Widget _checkInIdle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _TileIcon(
                icon: Icons.timer_outlined,
                bg: LumiColors.green.withValues(alpha: 0.14),
                fg: LumiColors.green),
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
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in [10, 20, 30, 60])
              _DurationChip(
                label: '$m min',
                onTap: () => _startCheckIn(Duration(minutes: m)),
              ),
            _DurationChip(label: 'Custom…', onTap: _showCustomDurationSheet),
          ],
        ),
      ],
    );
  }

  Future<void> _showCustomDurationSheet() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final minutes = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: LumiColors.bgTop,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 22,
          bottom: MediaQuery.of(ctx).viewInsets.bottom +
              MediaQuery.of(ctx).padding.bottom +
              28,
        ),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Custom check-in duration', style: LumiText.display(18)),
              const SizedBox(height: 14),
              LumiField(
                hint: 'Minutes',
                icon: Icons.timer_outlined,
                controller: controller,
                keyboardType: TextInputType.number,
                validator: (v) {
                  final n = int.tryParse(v?.trim() ?? '');
                  if (n == null || n <= 0) {
                    return 'Enter a whole number of minutes';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 18),
              LumiPrimaryButton(
                label: 'Start',
                onPressed: () {
                  if (formKey.currentState?.validate() != true) return;
                  Navigator.pop(ctx, int.parse(controller.text.trim()));
                },
              ),
            ],
          ),
        ),
      ),
    );
    if (minutes != null) await _startCheckIn(Duration(minutes: minutes));
  }

  Widget _checkInRunning(Duration remaining) {
    final m = remaining.inMinutes;
    final s = remaining.inSeconds % 60;
    return _checkInActiveCard(
      icon: Icons.timer_outlined,
      color: LumiColors.green,
      title: 'Checking in in $m:${s.toString().padLeft(2, '0')}',
      subtitle: CheckInPrefs.note.value,
    );
  }

  Widget _checkInGrace(int secondsRemaining) {
    return _checkInActiveCard(
      icon: Icons.warning_amber_rounded,
      color: LumiColors.accent,
      title: 'Check-in missed',
      subtitle: 'Alerting your guardians in ${secondsRemaining}s',
    );
  }

  Widget _checkInActiveCard({
    required IconData icon,
    required Color color,
    required String title,
    String? subtitle,
  }) {
    return Row(
      children: [
        _TileIcon(icon: icon, bg: color.withValues(alpha: 0.14), fg: color),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: LumiText.body(14.5, weight: FontWeight.w700)),
              if (subtitle != null)
                Text(subtitle,
                    style: LumiText.body(12, color: LumiColors.textSub)),
            ],
          ),
        ),
        GestureDetector(
          onTap: _cancelCheckIn,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text("I'm safe",
                style:
                    LumiText.body(13, weight: FontWeight.w700, color: color)),
          ),
        ),
      ],
    );
  }

  Future<void> _startCheckIn(Duration duration) async {
    if (!await EmergencyAlert.hasGuardians()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add emergency contacts first.')),
      );
      return;
    }
    // The background service enforces the check-in from a foreground
    // service that can't notify, text, or call without these — same set
    // _setShakeEnabled gates on, requested here so a denial is caught
    // before a timer gets persisted that nothing can act on.
    if (!kIsWeb && Platform.isAndroid) {
      final statuses = await [
        Permission.notification,
        Permission.sms,
        Permission.phone,
        Permission.locationWhenInUse,
      ].request();
      if (!statuses.values.every((s) => s.isGranted)) {
        if (statuses.values.any((s) => s.isPermanentlyDenied)) {
          openAppSettings();
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text(
              'Lumi needs notification, SMS, phone and location access for background SOS'),
          backgroundColor: LumiColors.accent.withValues(alpha: 0.9),
        ));
        return;
      }
    }
    await CheckInPrefs.start(duration);
    // Sharing is a bonus, not a precondition — a location-permission failure
    // here must not stop the timer that was already persisted above.
    try {
      await LiveLocationService.start();
    } catch (_) {/* Live Location's own switch/snackbar covers this normally */}
    if (!kIsWeb && Platform.isAndroid) ShakeGuardService.notifyCheckInStart();
  }

  Future<void> _cancelCheckIn() async {
    // Always clear locally first: this isolate's card must update instantly
    // even off-Android (no background service to notify) or if the service
    // isn't currently running. The IPC below additionally stops the
    // service-side CheckInTimerCore when it is — the double clear is
    // idempotent.
    await CheckInPrefs.clear();
    if (!kIsWeb && Platform.isAndroid) {
      ShakeGuardService.notifyCheckInCancel();
    }
  }
}

class _DurationChip extends StatelessWidget {
  const _DurationChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: LumiColors.hairline),
        ),
        child: Text(label, style: LumiText.body(13, weight: FontWeight.w600)),
      ),
    );
  }
}

class _TileIcon extends StatelessWidget {
  const _TileIcon({required this.icon, required this.bg, required this.fg});
  final IconData icon;
  final Color bg, fg;
  @override
  Widget build(BuildContext context) => Container(
        width: 42,
        height: 42,
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(13)),
        child: Icon(icon, color: fg, size: 20),
      );
}

/// Lightweight stylised map preview (no Google tile cost on this tab).
class _MapPreview extends StatelessWidget {
  const _MapPreview({required this.isLive});
  final bool isLive;
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 118,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: LumiColors.hairline),
        gradient: const RadialGradient(
          center: Alignment(0.2, -0.2),
          radius: 1.1,
          colors: [Color(0xFF122036), Color(0xFF0A1120)],
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            left: -40,
            top: 92,
            right: -40,
            child: Transform.rotate(
              angle: -0.22,
              child: Container(
                  height: 12, color: Colors.white.withValues(alpha: 0.06)),
            ),
          ),
          Positioned(
            left: 90,
            top: -30,
            bottom: -30,
            child: Transform.rotate(
              angle: 0.16,
              child: Container(
                  width: 10, color: Colors.white.withValues(alpha: 0.05)),
            ),
          ),
          const Center(child: _Marker()),
          if (isLive)
            const Positioned(
              left: 12,
              top: 12,
              child: LumiStatusPill(label: 'Sharing live'),
            ),
        ],
      ),
    );
  }
}

class _Marker extends StatelessWidget {
  const _Marker();
  @override
  Widget build(BuildContext context) => Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: LumiColors.accent,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [
            BoxShadow(color: LumiColors.accent, blurRadius: 16)
          ],
        ),
      );
}
