// FINDING A regression: a fresh install has ShakePrefs.enabled defaulting ON,
// so the foreground service must not start until notification/SMS/phone
// permissions are actually granted (checked, not requested — the Track-page
// toggle owns the request flow in location_page.dart).
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:safetyproject/services/shake_guard_service.dart';

import '../test_helpers.dart';

/// Grants notification + phone but denies SMS — enough to prove
/// hasRequiredPermissions() requires *all three*, not just some.
class _SmsDeniedPermissionHandlerPlatform extends PermissionHandlerPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<PermissionStatus> checkPermissionStatus(Permission permission) async {
    if (permission == Permission.sms) return PermissionStatus.denied;
    return PermissionStatus.granted;
  }
}

void main() {
  setUp(configureTestEnvironment);

  test('hasRequiredPermissions is false when SMS is denied', () async {
    PermissionHandlerPlatform.instance = _SmsDeniedPermissionHandlerPlatform();
    expect(await ShakeGuardService.hasRequiredPermissions(), isFalse);
  });

  test('hasRequiredPermissions is true when everything is granted', () async {
    PermissionHandlerPlatform.instance = FakeGrantedPermissionHandlerPlatform();
    expect(await ShakeGuardService.hasRequiredPermissions(), isTrue);
  });
}
