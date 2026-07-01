// ─────────────────────────────────────────────────────────────────────────────
//  Lumi · signup
//  Replaces:  lib/pages/signup_page.dart
//  Keeps your AuthController.register + Get navigation.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../oauth/auth_controller.dart';
import '../theme/lumi_theme.dart';
import '../widgets/lumi_widgets.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});
  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LumiScaffold(
      padding: const EdgeInsets.fromLTRB(26, 8, 26, 24),
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
                    // back button
                    GestureDetector(
                      onTap: () => Get.back(),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: LumiColors.field,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: LumiColors.hairline),
                        ),
                        child: const Icon(Icons.chevron_left,
                            color: LumiColors.text, size: 24),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text('Create account', style: LumiText.display(30)),
                    const SizedBox(height: 6),
                    Text('Set up your safety circle in 30 seconds.',
                        style: LumiText.body(14.5, color: LumiColors.textSub)),
                    const SizedBox(height: 26),
                    LumiField(
                      hint: 'Full name',
                      icon: Icons.person_outline,
                      controller: _nameController,
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Enter a name' : null,
                    ),
                    const SizedBox(height: 14),
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
                    const Spacer(),
                    LumiPrimaryButton(
                        label: 'Create account', onPressed: _submit),
                    const SizedBox(height: 18),
                    Center(
                      child: GestureDetector(
                        onTap: () => Get.back(),
                        child: Text.rich(TextSpan(
                          text: 'Already have one?  ',
                          style: LumiText.body(14, color: LumiColors.textSub),
                          children: [
                            TextSpan(
                              text: 'Sign in',
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
    AuthController.instance.register(
      _emailController.text.trim(),
      _passwordController.text,
    );
  }
}
