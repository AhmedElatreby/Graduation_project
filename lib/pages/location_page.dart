// ─────────────────────────────────────────────────────────────────────────────
//  Lumi · Track (live-location tab)
//  Replaces:  lib/pages/location_page.dart
//  Returns CONTENT only. Keeps your location stream + Firestore writes.
//  ★ #6  Siren now uses the app-wide Siren singleton, so it keeps playing until
//        the clip finishes even if you leave this screen.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:io' show Platform;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/live_location_service.dart';
import '../services/shake_guard_service.dart';
import '../services/shake_prefs.dart';
import '../services/silent_sos_prefs.dart';
import '../services/siren.dart';
import '../theme/lumi_theme.dart';
import '../widgets/checkin_card.dart';
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

  @override
  void initState() {
    super.initState();
    _requestPermission();
  }

  // NOTE: we intentionally do NOT stop the siren on dispose — it should keep
  // playing even if you leave this tab, so there's nothing to clean up here.

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

              if (!kIsWeb && Platform.isAndroid) ...[
                LumiCard(
                  child: Row(
                    children: [
                      _TileIcon(
                          icon: Icons.volume_down,
                          bg: LumiColors.blue.withValues(alpha: 0.14),
                          fg: LumiColors.blue),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Silent SOS trigger',
                                style: LumiText.body(14.5,
                                    weight: FontWeight.w700)),
                            Text(
                                'Press volume-down 3× to silently alert '
                                'your guardians — press 3× again to cancel',
                                style: LumiText.body(12,
                                    color: LumiColors.textSub)),
                          ],
                        ),
                      ),
                      ValueListenableBuilder<bool>(
                        valueListenable: SilentSosPrefs.enabled,
                        builder: (_, on, __) => Switch(
                          value: on,
                          activeThumbColor: Colors.white,
                          activeTrackColor: LumiColors.blue,
                          onChanged: SilentSosPrefs.setEnabled,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 9),
              ],

              // check-in timer ("walk me home")
              const CheckInCard(),
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
