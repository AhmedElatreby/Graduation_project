// ─────────────────────────────────────────────────────────────────────────────
//  Lumi · Emergency alert service
//
//  The single code path for "send the alert": texts every guardian a maps
//  link and calls the first one. Used by the SOS hold-button and by
//  shake-to-SOS, so the two triggers can never drift apart.
//
//  No BuildContext in here — callers decide how to surface failures.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:flutter_sms/flutter_sms.dart';
import 'package:geolocator/geolocator.dart';
import 'package:telephony/telephony.dart';

import '../contact/personal_emergency_contacts_model.dart';
import '../database/db_helper.dart';
import 'pending_call.dart';

class BackgroundSendResult {
  const BackgroundSendResult(
      {required this.smsFailures, required this.callBlocked});
  final List<String> smsFailures;
  final bool callBlocked;
}

class EmergencyAlert {
  EmergencyAlert._();

  /// Whether at least one guardian exists — callers gate the shake countdown
  /// on this so users without contacts get a prompt instead of a countdown.
  static Future<bool> hasGuardians() async =>
      (await DBHelper().getContacts()).isNotEmpty;

  /// The SMS body. Extracted so the foreground composer path and the
  /// background silent path can never drift apart.
  static String buildAlertMessage(String? coords) => coords == null
      ? 'I need help! (My location is unavailable right now.)'
      : 'I need help, please find me: https://maps.google.com/?q=$coords';

  /// Sends the full alert: SMS to every guardian, then a call to the first.
  /// SMS and call are attempted independently so one failing doesn't block
  /// the other. Returns human-readable failure messages (empty = success).
  /// Returns ['Add emergency contacts first.'] if there are no guardians.
  static Future<List<String>> send() async {
    final contacts = await DBHelper().getContacts();
    if (contacts.isEmpty) return ['Add emergency contacts first.'];

    final failures = <String>[];
    try {
      await sendTexts(contacts: contacts);
    } catch (e) {
      failures.add('SMS failed: $e');
    }
    try {
      await callFirstContact(contacts: contacts);
    } catch (e) {
      failures.add('Call failed: $e');
    }
    return failures;
  }

  /// Calls the first guardian. Throws on failure.
  static Future<void> callFirstContact(
      {List<PersonalEmergency>? contacts}) async {
    final list = contacts ?? await DBHelper().getContacts();
    await FlutterPhoneDirectCaller.callNumber(list.first.contactNo);
  }

  /// Texts every guardian the location link. Throws on failure.
  static Future<void> sendTexts({List<PersonalEmergency>? contacts}) async {
    final list = contacts ?? await DBHelper().getContacts();
    final coords = await currentCoordinates();
    final message = buildAlertMessage(coords);
    final recipients = list.map((c) => c.contactNo).toList();

    if (defaultTargetPlatform == TargetPlatform.android) {
      final telephony = Telephony.instance;
      for (final number in recipients) {
        await telephony.sendSms(to: number, message: message);
      }
    } else {
      await sendSMS(message: message, recipients: recipients);
    }
  }

  /// Best-effort current coordinates: live GPS first (this is an emergency,
  /// the freshest fix matters), then the user's own Firestore location doc
  /// (written by the Track tab), then null.
  static Future<String?> currentCoordinates() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      return '${pos.latitude},${pos.longitude}';
    } catch (_) {
      // fall through to the last value shared via the Track tab
    }
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return null;
      final snap = await FirebaseFirestore.instance
          .collection('location')
          .doc(uid)
          .get();
      final data = snap.data();
      final lat = data?['latitude'];
      final lng = data?['longitude'];
      if (lat == null || lng == null) return null;
      return '$lat,$lng';
    } catch (_) {
      return null;
    }
  }

  /// Background variant used by the Android shake-guard service: silent SMS
  /// per guardian (no composer UI), then a best-effort call. Android 10+
  /// usually blocks the dialer launch from the background — then we set
  /// [PendingCall] and report callBlocked so the notification can say
  /// "tap to call".
  static Future<BackgroundSendResult> sendBackground() async {
    final contacts = await DBHelper().getContacts();
    if (contacts.isEmpty) {
      return const BackgroundSendResult(
          smsFailures: ['Add emergency contacts first.'], callBlocked: false);
    }

    String? coords;
    try {
      coords = await currentCoordinates().timeout(const Duration(seconds: 10));
    } catch (_) {
      coords = null; // background GPS may be denied/slow — degrade, don't die
    }
    final message = buildAlertMessage(coords);

    final smsFailures = <String>[];
    final telephony = Telephony.backgroundInstance;
    for (final c in contacts) {
      try {
        await telephony.sendSms(to: c.contactNo, message: message);
      } catch (e) {
        smsFailures.add('SMS to ${c.name} failed: $e');
      }
    }

    var callBlocked = false;
    try {
      await callFirstContact(contacts: contacts);
    } catch (_) {
      callBlocked = true;
      await PendingCall.set();
    }
    return BackgroundSendResult(
        smsFailures: smsFailures, callBlocked: callBlocked);
  }
}
