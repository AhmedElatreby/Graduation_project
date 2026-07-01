// ─────────────────────────────────────────────────────────────────────────────
//  Lumi · login
//  Replaces:  lib/pages/login_page.dart
//  Keeps your AuthController + Get + FirebaseAuth logic — only the UI changed.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../oauth/auth_controller.dart';
import '../theme/lumi_theme.dart';
import '../widgets/lumi_logo.dart';
import '../widgets/lumi_widgets.dart';
import 'signup_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LumiScaffold(
      padding: const EdgeInsets.fromLTRB(26, 30, 26, 24),
      child: Form(
        key: _formKey,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 6),
                    const LumiMark(size: 62),
                    const SizedBox(height: 30),
                    Text('Welcome back', style: LumiText.display(30)),
                    const SizedBox(height: 6),
                    Text('Sign in to keep your circle close.',
                        style: LumiText.body(14.5, color: LumiColors.textSub)),
                    const SizedBox(height: 28),
                    LumiField(
                      hint: 'Email',
                      icon: Icons.mail_outline,
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) => v == null || !v.contains('@')
                          ? 'Enter a valid email'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    LumiField(
                      hint: 'Password',
                      icon: Icons.lock_outline,
                      controller: _passwordController,
                      obscure: _obscure,
                      validator: (v) =>
                          v == null || v.length < 6 ? 'Min 6 characters' : null,
                      suffix: IconButton(
                        icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: LumiColors.textFaint,
                            size: 20),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _forgotPassword,
                        child: Text('Forgot password?',
                            style: LumiText.body(13,
                                weight: FontWeight.w600,
                                color: LumiColors.textSub)),
                      ),
                    ),
                    const Spacer(),
                    LumiPrimaryButton(label: 'Sign in', onPressed: _submit),
                    const SizedBox(height: 18),
                    Center(
                      child: GestureDetector(
                        onTap: () => Get.to(() => const SignUpPage()),
                        child: Text.rich(TextSpan(
                          text: 'New here?  ',
                          style: LumiText.body(14, color: LumiColors.textSub),
                          children: [
                            TextSpan(
                              text: 'Create account',
                              style: LumiText.body(14,
                                  weight: FontWeight.w700,
                                  color: LumiColors.accent),
                            ),
                          ],
                        )),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) return;
    AuthController.instance.login(
      _emailController.text.trim(),
      _passwordController.text.trim(),
    );
  }

  Future<void> _forgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your email above first')),
      );
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reset link sent to $email')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send reset email: $e')),
      );
    }
  }
}
