// ─────────────────────────────────────────────────────────────────────────────
//  Lumi · Guardian live-view share links
//  Creates a short-lived, unguessable share for the guardian-facing web
//  page (public/share.html) to read. Deliberately a separate Firestore
//  collection from location/{uid} — that document's owner-only rule is
//  never touched or weakened to accommodate guests.
//  See docs/superpowers/specs/2026-07-10-guardian-live-view-design.md
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'share_link_prefs.dart';

class GuardianShare {
  GuardianShare._();

  static const _validity = Duration(hours: 2);
  static const _collection = 'shared_locations';
  static const _baseUrl = 'https://safety-project-71d83.web.app/share.html';

  /// Creates a fresh, independent share for the current position. Returns
  /// null (no link, alert message unchanged) if nobody is signed in or
  /// [coords] is unavailable — a share link is a bonus on top of an
  /// already-working alert, never a precondition for sending it. Always
  /// mints a brand-new shareId; an earlier still-valid share from a prior
  /// alert is left running, untouched.
  static Future<String?> createShareLink({
    required String? coords,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  }) async {
    final user = (auth ?? FirebaseAuth.instance).currentUser;
    if (user == null || coords == null) return null;

    final parts = coords.split(',');
    if (parts.length != 2) return null;
    final lat = double.tryParse(parts[0]);
    final lng = double.tryParse(parts[1]);
    if (lat == null || lng == null) return null;

    final db = firestore ?? FirebaseFirestore.instance;
    final shareId = _generateToken();
    final expiresAt = DateTime.now().add(_validity);

    await db.collection(_collection).doc(shareId).set({
      'ownerUid': user.uid,
      'name': _firstName(user.email),
      'latitude': lat,
      'longitude': lng,
      'updatedAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(expiresAt),
    });

    await ShareLinkPrefs.start(shareId, expiresAt);
    return '$_baseUrl?id=$shareId';
  }

  /// Same derivation SosPage already uses for its "Good evening, X"
  /// greeting, reused here so the guardian sees a matching first name.
  static String _firstName(String? email) {
    if (email == null || email.isEmpty) return 'Someone';
    final base = email.contains('@') ? email.split('@').first : email;
    if (base.isEmpty) return 'Someone';
    return base[0].toUpperCase() + base.substring(1);
  }

  static String _generateToken() {
    final bytes = List<int>.generate(24, (_) => Random.secure().nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}
