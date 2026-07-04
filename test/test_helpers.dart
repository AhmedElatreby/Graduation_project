// Shared setup for widget tests: an in-memory sqflite backend (so DBHelper
// works without a real device), a fake path_provider (DBHelper asks for the
// app documents directory before opening the database), and disabling
// google_fonts' runtime network fetch (the app's text styles all route
// through GoogleFonts.*, which otherwise tries to hit the network in tests).
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final Directory _dir = Directory.systemTemp.createTempSync('lumi_test_');

  @override
  Future<String?> getApplicationDocumentsPath() async => _dir.path;
}

/// Grants every permission instantly. SosPage fires off a location
/// permission request in initState() without awaiting it; without this, that
/// request would hit a real platform channel that doesn't exist in a widget
/// test and throw a MissingPluginException.
class FakeGrantedPermissionHandlerPlatform extends PermissionHandlerPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<PermissionStatus> checkPermissionStatus(Permission permission) async =>
      PermissionStatus.granted;

  @override
  Future<Map<Permission, PermissionStatus>> requestPermissions(
          List<Permission> permissions) async =>
      {for (final p in permissions) p: PermissionStatus.granted};

  @override
  Future<ServiceStatus> checkServiceStatus(Permission permission) async =>
      ServiceStatus.enabled;

  @override
  Future<bool> shouldShowRequestPermissionRationale(
          Permission permission) async =>
      false;

  @override
  Future<bool> openAppSettings() async => true;
}

/// Fails every request immediately instead of letting google_fonts hang (or
/// time out slowly) trying to reach fonts.gstatic.com from a widget test.
/// google_fonts checksums its downloads, so a fake successful response isn't
/// an option -- an instant, clean failure is what keeps pumpAndSettle() from
/// tripping over a lingering network timer.
class _BlockedHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _BlockedHttpClient();
}

class _BlockedHttpClient implements HttpClient {
  // Deliberately never completes: an unresolved Future can't reject, so it
  // can't surface as an "unhandled exception after the test completed" --
  // google_fonts' fire-and-forget font load just sits pending forever, which
  // pumpAndSettle() ignores (it only waits on scheduled frames/animations).
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      Completer<HttpClientRequest>().future;

  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);

  @override
  void noSuchMethod(Invocation invocation) {}
}

/// Call once per test file, before any widget test that touches DBHelper or
/// GoogleFonts-based text styles.
void configureTestEnvironment() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  PathProviderPlatform.instance = FakePathProviderPlatform();
  PermissionHandlerPlatform.instance = FakeGrantedPermissionHandlerPlatform();
  HttpOverrides.global = _BlockedHttpOverrides();
  GoogleFonts.config.allowRuntimeFetching = true;
}

/// `pumpAndSettle()` runs inside flutter_test's fake-async zone, which never
/// lets genuinely-async work (sqflite_common_ffi's FFI/isolate calls) make
/// progress -- it just hangs until pumpAndSettle's own timeout fires. This
/// alternates `tester.runAsync()` (which *does* let real async work run) with
/// `tester.pump()` (so the widget tree observes whatever just resolved), for
/// use anywhere DBHelper is on the other end of a rebuild.
Future<void> settleWithRealAsync(
  WidgetTester tester, {
  int rounds = 6,
  Duration step = const Duration(milliseconds: 50),
}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(step));
    await tester.pump(step);
  }
}
