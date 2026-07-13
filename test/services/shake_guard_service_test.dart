// requestPermissions is the one shared permission-request entry point for
// everything the guard service backs (shake switch, check-in Start): it must
// request exactly the set hasRequiredPermissions() checks, so the two can
// never drift apart.
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:safetyproject/services/shake_guard_service.dart';

import '../test_helpers.dart';

void main() {
  configureTestEnvironment();

  test('requestPermissions requests the exact set hasRequiredPermissions '
      'checks and returns the statuses', () async {
    final statuses = await ShakeGuardService.requestPermissions();

    expect(
      statuses.keys.toSet(),
      {
        Permission.notification,
        Permission.sms,
        Permission.phone,
        Permission.locationWhenInUse,
      },
    );
    // FakeGrantedPermissionHandlerPlatform grants everything, so the granted
    // map must line up with hasRequiredPermissions() saying yes.
    expect(statuses.values.every((s) => s.isGranted), isTrue);
    expect(await ShakeGuardService.hasRequiredPermissions(), isTrue);
  });
}
