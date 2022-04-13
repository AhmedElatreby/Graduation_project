import 'package:flutter/material.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Text(
          "Safety App",
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 50,
              color: Colors.redAccent,
              fontWeight: FontWeight.w600,
              fontStyle: FontStyle.italic),
        ),
      ),
    );
  }
}
