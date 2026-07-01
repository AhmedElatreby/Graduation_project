// ─────────────────────────────────────────────────────────────────────────────
//  Lumi · shared widgets
//  Drop this in:  lib/widgets/lumi_widgets.dart
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import '../theme/lumi_theme.dart';

/// Screen wrapper with the midnight vertical gradient + SafeArea.
class LumiScaffold extends StatelessWidget {
  const LumiScaffold({
    super.key,
    required this.child,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      backgroundColor: LumiColors.bgDeep,
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
      body: Container(
        decoration: const BoxDecoration(gradient: LumiColors.screenGradient),
        child: SafeArea(child: Padding(padding: padding, child: child)),
      ),
    );
  }
}

/// Full-width red gradient pill button.
class LumiPrimaryButton extends StatelessWidget {
  const LumiPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.height = 56,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double height;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          gradient: LumiColors.accentGradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: LumiColors.accent.withOpacity(0.4),
              blurRadius: 26,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 8),
            ],
            Text(label, style: LumiText.display(16.5, color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

/// A rounded text field matching the mockups (dark fill + leading icon).
class LumiField extends StatelessWidget {
  const LumiField({
    super.key,
    required this.hint,
    required this.icon,
    this.controller,
    this.obscure = false,
    this.keyboardType,
    this.suffix,
    this.validator,
  });

  final String hint;
  final IconData icon;
  final TextEditingController? controller;
  final bool obscure;
  final TextInputType? keyboardType;
  final Widget? suffix;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      validator: validator,
      style: LumiText.body(15, color: LumiColors.text),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, size: 20),
        suffixIcon: suffix,
      ),
    );
  }
}

/// Small pill — e.g. "Protected · 3 guardians watching".
class LumiStatusPill extends StatelessWidget {
  const LumiStatusPill({
    super.key,
    required this.label,
    this.color = LumiColors.green,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: color, blurRadius: 8)],
            ),
          ),
          const SizedBox(width: 7),
          Text(label,
              style: LumiText.body(12.5,
                  weight: FontWeight.w600,
                  color: Color.lerp(color, Colors.white, 0.35))),
        ],
      ),
    );
  }
}

/// Card used for list rows / toggles.
class LumiCard extends StatelessWidget {
  const LumiCard({super.key, required this.child, this.padding});
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: LumiColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: LumiColors.hairline),
      ),
      child: child,
    );
  }
}
