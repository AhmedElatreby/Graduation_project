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
import 'package:location/location.dart' as loc;
import 'package:permission_handler/permission_handler.dart';

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
  final loc.Location location = loc.Location();
  StreamSubscription<loc.LocationData>? _sub;

  bool get _isLive => _sub != null;

  // Location docs are keyed by the signed-in user's uid so each user only
  // ever touches their own document (was a single shared 'user1' doc that
  // every account overwrote and could read).
  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _requestPermission();
    location.changeSettings(interval: 300, accuracy: loc.LocationAccuracy.high);
  }

  @override
  void dispose() {
    _sub?.cancel();
    // NOTE: we intentionally do NOT stop the siren here — it should keep playing
    // even if you leave this tab.
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
              _MapPreview(isLive: _isLive),
              const SizedBox(height: 10),

              // live toggle
              LumiCard(
                child: Row(
                  children: [
                    _TileIcon(
                        icon: Icons.my_location,
                        bg: LumiColors.accent.withOpacity(0.14),
                        fg: LumiColors.accent),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Live location',
                              style:
                                  LumiText.body(14.5, weight: FontWeight.w700)),
                          Text(_isLive ? 'Sharing now' : 'Off',
                              style:
                                  LumiText.body(12, color: LumiColors.textSub)),
                        ],
                      ),
                    ),
                    Switch(
                      value: _isLive,
                      activeColor: Colors.white,
                      activeTrackColor: LumiColors.accent,
                      onChanged: (v) =>
                          v ? _listenLocation() : _stopListening(),
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
                        bg: LumiColors.amber.withOpacity(0.14),
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
                          color: LumiColors.amber.withOpacity(0.16),
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
                            bg: LumiColors.blue.withOpacity(0.14),
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
                            activeColor: Colors.white,
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
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  // ── logic (yours, trimmed) ──────────────────────────────────────────────────
  Future<void> _listenLocation() async {
    final uid = _uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to share your location')),
      );
      return;
    }
    setState(() {});
    _sub = location.onLocationChanged.handleError((e) {
      _sub?.cancel();
      setState(() => _sub = null);
    }).listen((d) async {
      await FirebaseFirestore.instance.collection('location').doc(uid).set({
        'latitude': d.latitude,
        'longitude': d.longitude,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
    if (mounted) setState(() {});
  }

  void _stopListening() {
    _sub?.cancel();
    setState(() => _sub = null);
  }

  Future<void> _siren() async {
    await Siren.instance.play(); // keeps playing after you leave this screen
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Siren activated!'),
      backgroundColor: LumiColors.amber.withOpacity(0.9),
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
    final statuses = await [
      Permission.notification,
      Permission.sms,
      Permission.phone,
      Permission.locationWhenInUse,
    ].request();
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
      backgroundColor: LumiColors.accent.withOpacity(0.9),
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
              child:
                  Container(height: 12, color: Colors.white.withOpacity(0.06)),
            ),
          ),
          Positioned(
            left: 90,
            top: -30,
            bottom: -30,
            child: Transform.rotate(
              angle: 0.16,
              child:
                  Container(width: 10, color: Colors.white.withOpacity(0.05)),
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
          boxShadow: [BoxShadow(color: LumiColors.accent, blurRadius: 16)],
        ),
      );
}
