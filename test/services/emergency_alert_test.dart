// EmergencyAlert.hasGuardians gates the shake countdown: no guardians means
// no countdown, just a "add guardians" prompt.
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safetyproject/contact/personal_emergency_contacts_model.dart';
import 'package:safetyproject/database/db_helper.dart';
import 'package:safetyproject/services/emergency_alert.dart';
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
    await DBHelper().add(PersonalEmergency('Sara', '01000000000'));

    final contacts = await DBHelper().getContacts();
    expect(EmergencyAlert.resolveCallTarget(contacts).contactNo,
        '01000000000');
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
}
