import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:get/get.dart';

import 'firebase_options.dart';
import 'oauth/auth_controller.dart';
import 'pages/splash_screen.dart';
import 'services/checkin_prefs.dart';
import 'services/fake_call_prefs.dart';
import 'services/primary_contact_prefs.dart';
import 'services/shake_guard_service.dart';
import 'services/shake_prefs.dart';
import 'services/share_link_prefs.dart';
import 'services/silent_sos_prefs.dart';
import 'theme/lumi_theme.dart';

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  // The SOS page's hold button and animated rings are fixed-size and were
  // never laid out for landscape — rotating overflows the screen. This app
  // has no landscape design, so lock to portrait like other safety apps.
  await SystemChrome.setPreferredOrientations(
      [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  if (!kIsWeb && Platform.isAndroid) {
    // Receive-port for the shake-guard service isolate + notification config.
    FlutterForegroundTask.initCommunicationPort();
    ShakeGuardService.init();
  }
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)
      .then((value) => Get.put(AuthController()));
  await ShakePrefs.load();
  await PrimaryContactPrefs.load();
  await ShareLinkPrefs.load();
  // Without this, a cold launch with a timer running sees endTime == null,
  // computes "no check-in" and stops the legitimately-counting service.
  await CheckInPrefs.load();
  await FakeCallPrefs.load();
  await SilentSosPrefs.load();
  runApp(const MyApp());
  await initialization();
  FlutterNativeSplash.remove();
}

Future<void> initialization() async {
  await Future.delayed(const Duration(seconds: 2));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Safety App',
      theme: LumiTheme.dark(),
      debugShowCheckedModeBanner: false,
      // AuthController navigates to LoginPage or NavBarPage as soon as the
      // auth state resolves; showing the branded splash until then avoids
      // flashing the login form at users who are already signed in.
      home: const SplashScreen(),
    );
  }
}
