// EmergencyAlert.hasGuardians gates the shake countdown: no guardians means
// no countdown, just a "add guardians" prompt.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safetyproject/contact/personal_emergency_contacts_model.dart';
import 'package:safetyproject/database/db_helper.dart';
import 'package:safetyproject/services/emergency_alert.dart';
import 'package:safetyproject/services/guardian_share.dart';
import 'package:safetyproject/services/primary_contact_prefs.dart';

import '../test_helpers.dart';

void main() {
  configureTestEnvironment();

  test('hasGuardians is false with an empty contact book, true after adding',
      () async {
    expect(await EmergencyAlert.hasGuardians(), isFalse);

    await DBHelper().add(PersonalEmergency('Sara', '01000000000'));
    expect(await EmergencyAlert.hasGuardians(), isTrue);
  });

  test('callFirstContact calls the primary contact when one is set',
      () async {
    SharedPreferences.setMockInitialValues({});
    final sara =
        await DBHelper().add(PersonalEmergency('Sara', '01000000000'));
    await DBHelper().add(PersonalEmergency('Jo', '02000000000'));
    await PrimaryContactPrefs.set(sara.id);

    final contacts = await DBHelper().getContacts();
    // getContacts() orders id DESC, so Jo (added later) is list.first —
    // this sanity check proves the primary override is what matters below.
    expect(contacts.first.name, 'Jo');

    expect(
      EmergencyAlert.resolveCallTarget(contacts).contactNo,
      '01000000000', // Sara's number, chosen over Jo despite not being first
    );
  });

  test(
      'callFirstContact resolves to list.first when the stored primary id '
      'matches no current contact', () async {
    SharedPreferences.setMockInitialValues({});
    await DBHelper().add(PersonalEmergency('Sara', '01000000000'));
    await PrimaryContactPrefs.set(999999); // no contact has this id

    final contacts = await DBHelper().getContacts();
    expect(EmergencyAlert.resolveCallTarget(contacts).contactNo,
        '01000000000');
  });

  test('resolveCallTarget resolves to list.first when no primary is set',
      () async {
    SharedPreferences.setMockInitialValues({});
    // Explicitly clear the in-memory notifier: a prior test in this file may
    // have left a primary id set on this static, and without this reset the
    // test could pass by inheriting that leftover state rather than
    // genuinely proving the null-primary case.
    PrimaryContactPrefs.id.value = null;
    await DBHelper().add(PersonalEmergency('Sara', '01000000000'));

    final contacts = await DBHelper().getContacts();
    expect(EmergencyAlert.resolveCallTarget(contacts).contactNo,
        '01000000000');
  });

  test(
      'PrimaryContactPrefs.load() restores a persisted primary in a fresh '
      "isolate's notifier before resolveCallTarget is consulted", () async {
    // Simulates the exact cross-isolate seam that let the Critical bug
    // through: the primary is persisted (e.g. set from the main isolate),
    // but the shake-guard's background isolate starts with a fresh
    // ValueNotifier that has never loaded anything — id.value is null even
    // though SharedPreferences has a value on disk. sendBackground's fix
    // (EmergencyAlert.sendBackground calling PrimaryContactPrefs.load()
    // right before the call attempt) is what's supposed to fix this; this
    // test proves that load() call actually does the job.
    SharedPreferences.setMockInitialValues({});
    final sara =
        await DBHelper().add(PersonalEmergency('Sara', '01000000000'));
    await DBHelper().add(PersonalEmergency('Jo', '02000000000'));
    await PrimaryContactPrefs.set(sara.id);

    // Simulate a fresh isolate that hasn't loaded the prefs yet.
    PrimaryContactPrefs.id.value = null;
    final contacts = await DBHelper().getContacts();
    expect(contacts.first.name, 'Jo');
    // Without a load(), the bug reproduces: falls back to contacts.first.
    expect(EmergencyAlert.resolveCallTarget(contacts).contactNo,
        '02000000000');

    // This is the exact call sendBackground now makes right before the call
    // attempt (see emergency_alert.dart).
    await PrimaryContactPrefs.load();

    expect(
      EmergencyAlert.resolveCallTarget(contacts).contactNo,
      '01000000000', // Sara's number, restored from persisted storage
    );
  });

  test('sendTexts refuses to run without SMS permission', () async {
    // The telephony plugin self-requests missing permissions and then
    // crashes the app with "Reply already submitted" when the grant lands
    // (observed on a Samsung device). Failing fast on our side means the
    // plugin never sees an unpermissioned call.
    PermissionHandlerPlatform.instance = SmsDeniedPermissionHandlerPlatform();
    expect(EmergencyAlert.sendTexts, throwsStateError);
    PermissionHandlerPlatform.instance = FakeGrantedPermissionHandlerPlatform();
  });

  test('buildAlertMessage includes the maps link when coords are known', () {
    expect(
      EmergencyAlert.buildAlertMessage('50.73,-1.85'),
      'I need help, please find me: https://maps.google.com/?q=50.73,-1.85',
    );
    expect(
      EmergencyAlert.buildAlertMessage(null),
      'I need help! (My location is unavailable right now.)',
    );
  });

  test('buildAlertMessage appends the share link on its own line when '
      'provided', () {
    expect(
      EmergencyAlert.buildAlertMessage('50.73,-1.85',
          shareLink: 'https://safety-project-71d83.web.app/share.html?id=abc'),
      'I need help, please find me: https://maps.google.com/?q=50.73,-1.85\n'
      'Live location: https://safety-project-71d83.web.app/share.html?id=abc',
    );
    // No share link: byte-for-byte identical to today's message.
    expect(
      EmergencyAlert.buildAlertMessage('50.73,-1.85'),
      'I need help, please find me: https://maps.google.com/?q=50.73,-1.85',
    );
  });

  test('sendBackground includes a share link in the SMS when one can be '
      'created', () async {
    // sendBackground itself hits telephony/geolocator plugins with no
    // mocked platform channel in this suite (see the existing
    // "sendTexts refuses to run..." test's own comment on this) — this
    // test targets buildAlertMessage + GuardianShare.createShareLink
    // directly instead, the same seam-testing approach Task 2 of the
    // primary-guardian-contact plan used for resolveCallTarget.
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'user-1', email: 'a@a.com'),
    );

    final link = await GuardianShare.createShareLink(
      coords: '50.73,-1.85',
      firestore: firestore,
      auth: auth,
    );

    expect(
      EmergencyAlert.buildAlertMessage('50.73,-1.85', shareLink: link),
      'I need help, please find me: https://maps.google.com/?q=50.73,-1.85\n'
      'Live location: $link',
    );
  });

  test('sendTexts is not aborted by a share-link failure', () async {
    // Firebase.initializeApp never runs in this suite, so the
    // FirebaseAuth.instance access inside GuardianShare.createShareLink
    // throws a real "[core/no-app]" FirebaseException — a natural in-test
    // share-link failure with no seam needed. That call sits BEFORE any
    // guardian is texted, so without the degrade-to-null try/catch the
    // error would abort the whole SMS batch. This test proves execution
    // gets PAST the share-link step: whatever surfaces (here, the unmocked
    // telephony platform channel) must be a downstream error, never the
    // Firebase one.
    PermissionHandlerPlatform.instance = FakeGrantedPermissionHandlerPlatform();
    await DBHelper().add(PersonalEmergency('Sara', '01000000000'));

    Object? error;
    try {
      await EmergencyAlert.sendTexts();
    } catch (e) {
      error = e;
    }
    expect(
      '$error',
      isNot(contains('Firebase')),
      reason: 'a share-link creation failure must never block the alert SMS',
    );
  });

  test('send() is not aborted by a live-location startup failure', () async {
    // Firebase.initializeApp never runs in this suite, so the
    // FirebaseAuth.instance access inside LiveLocationService.start()
    // throws a real "[core/no-app]" FirebaseException — a natural in-test
    // live-location failure with no seam needed. That call sits BEFORE the
    // SMS/call attempts in send(), so without its try/catch the error would
    // abort the whole alert. The key assertion: send() returns normally
    // (the unmocked telephony/caller channels' downstream errors land in
    // the returned failures list, whose contents don't matter here) rather
    // than throwing the Firebase error.
    PermissionHandlerPlatform.instance = FakeGrantedPermissionHandlerPlatform();
    await DBHelper().add(PersonalEmergency('Sara', '01000000000'));

    final failures = await EmergencyAlert.send();
    expect(failures, isA<List<String>>());
  });
}
