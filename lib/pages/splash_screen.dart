// ─────────────────────────────────────────────────────────────────────────────
//  Lumi · splash
//  Replaces:  lib/pages/splash_screen.dart
//  Note: you already use flutter_native_splash for the cold-start splash — update
//  its color to #06080E (see README). This widget is the in-app animated splash
//  you can show while Firebase / auth initialise, then navigate away from.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import '../theme/lumi_theme.dart';
import '../widgets/lumi_logo.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LumiColors.bgDeep,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.1),
            radius: 0.9,
            colors: [Color(0xFF19223A), Color(0xFF090D18)],
            stops: [0.0, 0.7],
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const LumiLogo(size: 104, pulse: true),
                const SizedBox(height: 34),
                Text('Lumi', style: LumiText.display(34)),
                const SizedBox(height: 6),
                Text("Someone's always with you.",
                    style: LumiText.body(14, color: LumiColors.textSub)),
              ],
            ),
            const Positioned(bottom: 54, child: _LoadingDots()),
          ],
        ),
      ),
    );
  }
}

class _LoadingDots extends StatefulWidget {
  const _LoadingDots();
  @override
  State<_LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<_LoadingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final t = ((_c.value + i * 0.2) % 1.0);
          final on = t < 0.5;
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 3.5),
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: LumiColors.accent.withOpacity(on ? 1 : 0.25),
            ),
          );
        }),
      ),
    );
  }
}
