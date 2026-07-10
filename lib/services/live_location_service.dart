// ─────────────────────────────────────────────────────────────────────────────
//  Lumi · Live location streaming
//  Extracted out of LocationPage's widget state so a plain static caller
//  (EmergencyAlert.send(), which has no BuildContext) can turn Live
//  Location on when a foreground alert fires. The Track page's toggle is
//  now a thin wrapper around this — behavior is unchanged from before
//  this extraction.
//  See docs/superpowers/specs/2026-07-10-guardian-live-view-design.md
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:location/location.dart' as loc;

import 'share_link_prefs.dart';

class LiveLocationService {
  LiveLocationService._();

  static final loc.Location _location = loc.Location();
  static StreamSubscription<loc.LocationData>? _sub;

  static final ValueNotifier<bool> isLive = ValueNotifier(false);

  /// Starts streaming fixes to Firestore for the signed-in user. No-op if
  /// already running or nobody is signed in (mirrors the snackbar-free
  /// "just don't start" behavior LocationPage already had for this case).
  static Future<void> start() async {
    if (_sub != null) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    await _location.changeSettings(
        interval: 300, accuracy: loc.LocationAccuracy.high);
    _sub = _location.onLocationChanged
        .handleError((_) => stop())
        .listen((d) async {
      await FirebaseFirestore.instance.collection('location').doc(uid).set({
        'latitude': d.latitude,
        'longitude': d.longitude,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (ShareLinkPrefs.isActive) {
        await FirebaseFirestore.instance
            .collection('shared_locations')
            .doc(ShareLinkPrefs.shareId.value)
            .set({
          'latitude': d.latitude,
          'longitude': d.longitude,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    });
    isLive.value = true;
  }

  static void stop() {
    _sub?.cancel();
    _sub = null;
    isLive.value = false;
  }
}
