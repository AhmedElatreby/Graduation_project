// ─────────────────────────────────────────────────────────────────────────────
//  Lumi · logo / pulsing-ring mark
//  Drop this in:  lib/widgets/lumi_logo.dart
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import '../theme/lumi_theme.dart';

/// The Lumi squircle icon (red gradient + white ring + center dot).
/// Set [pulse] to true to radiate expanding rings (use on splash / SOS).
class LumiLogo extends StatefulWidget {
  const LumiLogo({super.key, this.size = 96, this.pulse = false});

  final double size;
  final bool pulse;

  @override
  State<LumiLogo> createState() => _LumiLogoState();
}

class _LumiLogoState extends State<LumiLogo> with TickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
    if (widget.pulse) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s * 1.7,
      height: s * 1.7,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // expanding pulse rings
          if (widget.pulse)
            for (int i = 0; i < 3; i++)
              AnimatedBuilder(
                animation: _c,
                builder: (_, __) {
                  final t = (_c.value + i / 3) % 1.0;
                  return Opacity(
                    opacity: (1 - t) * 0.6,
                    child: Container(
                      width: s * (0.9 + t * 0.9),
                      height: s * (0.9 + t * 0.9),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: LumiColors.accent, width: 1.5),
                      ),
                    ),
                  );
                },
              ),

          // the squircle mark
          Container(
            width: s,
            height: s,
            decoration: BoxDecoration(
              gradient: LumiColors.accentGradient,
              borderRadius: BorderRadius.circular(s * 0.3),
              boxShadow: [
                BoxShadow(
                  color: LumiColors.accent.withValues(alpha: 0.45),
                  blurRadius: s * 0.3,
                  offset: Offset(0, s * 0.12),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // top-left sheen
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(s * 0.3),
                    gradient: RadialGradient(
                      center: const Alignment(-0.5, -0.6),
                      radius: 0.9,
                      colors: [
                        Colors.white.withValues(alpha: 0.4),
                        Colors.transparent
                      ],
                      stops: const [0.0, 0.55],
                    ),
                  ),
                ),
                // white ring + dot
                Container(
                  width: s * 0.46,
                  height: s * 0.46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: s * 0.055),
                  ),
                  child: Center(
                    child: Container(
                      width: s * 0.13,
                      height: s * 0.13,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A flat (non-animated) version of just the squircle — handy for app bars,
/// list leadings, the launcher-icon source, etc.
class LumiMark extends StatelessWidget {
  const LumiMark({super.key, this.size = 44});
  final double size;

  @override
  Widget build(BuildContext context) {
    final s = size;
    return Container(
      width: s,
      height: s,
      decoration: BoxDecoration(
        gradient: LumiColors.accentGradient,
        borderRadius: BorderRadius.circular(s * 0.3),
        boxShadow: [
          BoxShadow(
            color: LumiColors.accent.withValues(alpha: 0.4),
            blurRadius: s * 0.25,
            offset: Offset(0, s * 0.1),
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: s * 0.46,
          height: s * 0.46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: s * 0.06),
          ),
          child: Center(
            child: Container(
              width: s * 0.13,
              height: s * 0.13,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
