// EmergencyAlert.hasGuardians gates the shake countdown: no guardians means
// no countdown, just a "add guardians" prompt.
import 'package:flutter_test/flutter_test.dart';

import 'package:safetyproject/contact/personal_emergency_contacts_model.dart';
import 'package:safetyproject/database/db_helper.dart';
import 'package:safetyproject/services/emergency_alert.dart';

import '../test_helpers.dart';

void main() {
  configureTestEnvironment();

  test('hasGuardians is false with an empty contact book, true after adding',
      () async {
    expect(await EmergencyAlert.hasGuardians(), isFalse);

    await DBHelper().add(PersonalEmergency('Sara', '01000000000'));
    expect(await EmergencyAlert.hasGuardians(), isTrue);
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
