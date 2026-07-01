// ─────────────────────────────────────────────────────────────────────────────
//  Lumi · Track (live-location tab)
//  Replaces:  lib/pages/location_page.dart
//  Returns CONTENT only. Keeps your location stream + Firestore writes.
//  ★ #6  Siren now uses the app-wide Siren singleton, so it keeps playing until
//        the clip finishes even if you leave this screen.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:location/location.dart' as loc;
import 'package:permission_handler/permission_handler.dart';

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
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('Live tracking', style: LumiText.display(24)),
          ),
          const SizedBox(height: 16),

          // map preview (decorative — tap to open full Map tab if you wire it)
          _MapPreview(isLive: _isLive),
          const SizedBox(height: 14),

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
                          style: LumiText.body(14.5, weight: FontWeight.w700)),
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
                  onChanged: (v) => v ? _listenLocation() : _stopListening(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 11),

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
                          style: LumiText.body(14.5, weight: FontWeight.w700)),
                      Text('Scare off & draw attention',
                          style: LumiText.body(12, color: LumiColors.textSub)),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: _siren,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: LumiColors.amber.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text('Play',
                        style: LumiText.body(13,
                            weight: FontWeight.w700, color: LumiColors.amber)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('RECENT PINGS',
                style: LumiText.body(12,
                    weight: FontWeight.w700, color: LumiColors.textFaint)),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream:
                  FirebaseFirestore.instance.collection('location').snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(
                      child: CircularProgressIndicator(
                          color: LumiColors.accent));
                }
                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return Center(
                    child: Text('No locations shared yet',
                        style: LumiText.body(13, color: LumiColors.textSub)),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 100),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final d = docs[i];
                    final lat = d['latitude'];
                    final lng = d['longitude'];
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
                                Text(d.id,
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
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── logic (yours, trimmed) ──────────────────────────────────────────────────
  Future<void> _listenLocation() async {
    setState(() {});
    _sub = location.onLocationChanged.handleError((e) {
      _sub?.cancel();
      setState(() => _sub = null);
    }).listen((d) async {
      await FirebaseFirestore.instance.collection('location').doc('user1').set({
        'latitude': d.latitude,
        'longitude': d.longitude,
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
      height: 150,
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
              child: Container(height: 12, color: Colors.white.withOpacity(0.06)),
            ),
          ),
          Positioned(
            left: 90,
            top: -30,
            bottom: -30,
            child: Transform.rotate(
              angle: 0.16,
              child: Container(width: 10, color: Colors.white.withOpacity(0.05)),
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
