import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:get/get.dart';

import 'firebase_options.dart';
import 'oauth/auth_controller.dart';
import 'pages/splash_screen.dart';
import 'theme/lumi_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform).then((value) => Get.put(AuthController()));
  FlutterNativeSplash.removeAfter(initialization);
  runApp(const MyApp());
}

Future initialization(BuildContext? context) async {
  await Future.delayed(const Duration(seconds: 2));
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

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