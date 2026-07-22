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
import 'package:permission_handler/permission_handler.dart';
import 'package:telephony/telephony.dart';

import '../contact/personal_emergency_contacts_model.dart';
import '../database/alert_history_db.dart';
import '../database/db_helper.dart';
import 'guardian_share.dart';
import 'live_location_service.dart';
import 'pending_call.dart';
import 'primary_contact_prefs.dart';

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
  /// background silent path can never drift apart. [note] (e.g. a check-in
  /// timer's "walking home from the station") is appended on its own line
  /// first, as human context; [shareLink] (a GuardianShare URL) follows on
  /// its own line after that. Either or both may be omitted, leaving the
  /// message byte-for-byte unchanged when both are null — every existing
  /// call site that doesn't pass them sees no change.
  static String buildAlertMessage(String? coords,
      {String? shareLink, String? note}) {
    final base = coords == null
        ? 'I need help! (My location is unavailable right now.)'
        : 'I need help, please find me: https://maps.google.com/?q=$coords';
    final withNote = note == null ? base : '$base\n$note';
    return shareLink == null
        ? withNote
        : '$withNote\nLive location: $shareLink';
  }

  /// Sends the full alert: SMS to every guardian, then a call to the first.
  /// SMS and call are attempted independently so one failing doesn't block
  /// the other. Returns human-readable failure messages (empty = success).
  /// Returns ['Add emergency contacts first.'] if there are no guardians.
  /// [trigger] identifies which UI trigger fired this (e.g. "SOS button",
  /// "Shake to SOS") — logged to AlertHistoryDb, nothing else.
  static Future<List<String>> send({required String trigger}) async {
    final contacts = await DBHelper().getContacts();
    if (contacts.isEmpty) {
      await _logHistory(
          trigger: trigger,
          outcome: 'Failed',
          detail: 'Add emergency contacts first.');
      return ['Add emergency contacts first.'];
    }

    // Foreground-only: this is what lets the guardian's shared page keep
    // moving instead of showing one static point. A background/killed-app
    // alert (sendBackground) has no widget tree to stream GPS from, so it
    // isn't attempted there — see this plan's Global Constraints.
    try {
      await LiveLocationService.start();
    } catch (_) {
      // Live-location startup must never block the alert itself.
    }

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
    await _logHistory(
        trigger: trigger,
        outcome: failures.isEmpty ? 'Sent' : 'Failed',
        detail: failures.isEmpty ? null : failures.first);
    return failures;
  }

  /// Logs one history entry. Wrapped so a logging failure can never affect
  /// the alert itself — same degrade-silently pattern as every other
  /// bonus step on this path (live location, share link).
  static Future<void> _logHistory(
      {required String trigger,
      required String outcome,
      String? detail}) async {
    try {
      await AlertHistoryDb()
          .insert(trigger: trigger, outcome: outcome, detail: detail);
    } catch (_) {
      // degrade silently
    }
  }

  /// Fail fast if [permission] is missing (Android). The telephony and
  /// direct-caller plugins self-request missing permissions — and the
  /// telephony one then crashes the whole app with "Reply already
  /// submitted" when the grant arrives. Throwing here keeps the plugins
  /// out of the permission business; callers already surface the error.
  static Future<void> _requireGranted(
      Permission permission, String what) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    if (!(await permission.status).isGranted) {
      throw StateError('$what permission not granted');
    }
  }

  /// The guardian who actually gets called: the one marked primary via
  /// PrimaryContactPrefs, if any contact in [contacts] still has that id —
  /// otherwise contacts.first (today's behavior, unchanged for anyone who
  /// never sets a primary). [contacts] must be non-empty.
  static PersonalEmergency resolveCallTarget(List<PersonalEmergency> contacts) {
    final primaryId = PrimaryContactPrefs.id.value;
    if (primaryId != null) {
      for (final c in contacts) {
        if (c.id == primaryId) return c;
      }
    }
    return contacts.first;
  }

  /// Calls the primary guardian (or the first, if none is set). Throws on
  /// failure; returns the plugin's success flag (false/null = the OS
  /// refused the launch without throwing).
  static Future<bool?> callFirstContact(
      {List<PersonalEmergency>? contacts}) async {
    await _requireGranted(Permission.phone, 'Phone');
    final list = contacts ?? await DBHelper().getContacts();
    return FlutterPhoneDirectCaller.callNumber(
        resolveCallTarget(list).contactNo);
  }

  /// Texts every guardian the location link. Throws on failure.
  static Future<void> sendTexts({List<PersonalEmergency>? contacts}) async {
    await _requireGranted(Permission.sms, 'SMS');
    final list = contacts ?? await DBHelper().getContacts();
    final coords = await currentCoordinates();
    String? shareLink;
    try {
      shareLink = await GuardianShare.createShareLink(coords: coords);
    } catch (_) {
      shareLink = null; // a share-link failure must never block the alert
    }
    final message = buildAlertMessage(coords, shareLink: shareLink);
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
  /// the freshest fix matters), then the OS's cached last-known fix, then
  /// the user's own Firestore location doc (written by the Track tab),
  /// then null.
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
      // fall through to the cached fix
    }
    try {
      // A minutes-old fix beats "location unavailable" in an emergency —
      // and unlike a fresh fix it's instant and works indoors.
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) return '${last.latitude},${last.longitude}';
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
  /// "tap to call". Pass [coordsFuture] to reuse a fix already being
  /// acquired (the countdown doubles as GPS warm-up time). Pass [note] to
  /// carry a check-in timer's note through to the SMS body. [trigger]
  /// identifies which background trigger fired this (e.g. "Shake to SOS",
  /// "Check-in timer") — logged to AlertHistoryDb, nothing else.
  static Future<BackgroundSendResult> sendBackground(
      {required String trigger,
      Future<String?>? coordsFuture,
      String? note}) async {
    final contacts = await DBHelper().getContacts();
    if (contacts.isEmpty) {
      await _logHistory(
          trigger: trigger,
          outcome: 'Failed',
          detail: 'Add emergency contacts first.');
      return const BackgroundSendResult(
          smsFailures: ['Add emergency contacts first.'], callBlocked: false);
    }

    String? coords;
    try {
      coords = await (coordsFuture ?? currentCoordinates())
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      coords = null; // background GPS may be denied/slow — degrade, don't die
    }
    String? shareLink;
    try {
      shareLink = await GuardianShare.createShareLink(coords: coords);
    } catch (_) {
      // a share-link failure must never block the alert. In this background
      // isolate this currently ALWAYS degrades to null: the shake-guard
      // service never calls Firebase.initializeApp, so the FirebaseAuth
      // access above throws core/no-app every time. Background SMSes today
      // carry the static pin only — see the design doc's "Live Location
      // auto-enable, and its real limit" section.
      shareLink = null;
    }
    final message = buildAlertMessage(coords, shareLink: shareLink, note: note);

    final smsFailures = <String>[];
    try {
      await _requireGranted(Permission.sms, 'SMS');
      final telephony = Telephony.backgroundInstance;
      for (final c in contacts) {
        try {
          await telephony.sendSms(to: c.contactNo, message: message);
        } catch (e) {
          smsFailures.add('SMS to ${c.name} failed: $e');
        }
      }
    } catch (e) {
      smsFailures.add('SMS failed: $e');
    }

    var callBlocked = false;
    try {
      // This runs in the shake-guard's own isolate, which never runs
      // main.dart's startup code — PrimaryContactPrefs.id would otherwise
      // stay null here forever, making the call always fall back to
      // contacts.first. Reload fresh right before the call (not once at
      // service startup) since this foreground service can run for a long
      // time and the user could change the primary while it's running.
      await PrimaryContactPrefs.load();
      final ok = await callFirstContact(contacts: contacts);
      if (ok != true) callBlocked = true;
    } catch (_) {
      callBlocked = true;
    }
    if (callBlocked) await PendingCall.set();
    await _logHistory(
        trigger: trigger,
        outcome: smsFailures.isEmpty ? 'Sent' : 'Failed',
        detail: smsFailures.isEmpty ? null : smsFailures.first);
    return BackgroundSendResult(
        smsFailures: smsFailures, callBlocked: callBlocked);
  }
}
