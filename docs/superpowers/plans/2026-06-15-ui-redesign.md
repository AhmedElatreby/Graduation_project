# UI Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Modernise the safety app UI from a 2021 Material 2 design to Material 3, fix all broken interactive elements, and remove dead UI artefacts.

**Architecture:** Introduce a single `AppTheme` class that owns the `ThemeData` (Material 3, `ColorScheme.fromSeed`). Every screen is then updated to use theme tokens instead of hardcoded `Colors.cyan`. Structural bugs (wrong logOut gesture, dead social buttons, missing empty state) are fixed alongside the visual pass so the branch is always shippable.

**Tech Stack:** Flutter 3.44 · Material 3 · `NavigationBar` (replaces `BottomNavigationBar`) · `firebase_auth` (for forgot-password) · existing `sqflite` DBHelper · `flutter_sms` · `flutter_phone_direct_caller`

---

## File Map

| Action | Path | What changes |
|--------|------|-------------|
| Create | `lib/theme/app_theme.dart` | `AppTheme.light()` — single ThemeData source |
| Modify | `lib/main.dart:28-30` | Wire `AppTheme.light()` into `GetMaterialApp` |
| Modify | `lib/navigation_bar/main_page.dart` | `NavigationBar` + correct icons + labels |
| Modify | `lib/pages/sos.dart` | Fix logOut bug, confirmation dialog, theme colours |
| Modify | `lib/pages/login_page.dart` | `FilledButton`, forgot-password, form validation |
| Modify | `lib/pages/signup_page.dart` | Remove dead social buttons, `FilledButton`, validation |
| Modify | `lib/contact/personal_emergency_contacts.dart` | Empty state, `ModalBottomSheet` for add |
| Modify | `lib/pages/location_page.dart` | Card for coordinates, clean layout |

---

## Task 1: Material 3 Theme

**Files:**
- Create: `lib/theme/app_theme.dart`
- Modify: `lib/main.dart`

- [ ] **Step 1: Create `lib/theme/app_theme.dart`**

```dart
import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFFB71C1C),
      brightness: Brightness.light,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: const StadiumBorder(),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: const StadiumBorder(),
          minimumSize: const Size(double.infinity, 52),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
      ),
      cardTheme: const CardThemeData(elevation: 2),
    );
  }
}
```

- [ ] **Step 2: Wire theme into `lib/main.dart`**

Replace lines 3–6 and the `theme:` property. Full file after edit:

```dart
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:get/get.dart';

import 'oauth/auth_controller.dart';
import 'pages/login_page.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp().then((value) => Get.put(AuthController()));
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
      theme: AppTheme.light(),
      debugShowCheckedModeBanner: false,
      home: LoginPage(),
    );
  }
}
```

- [ ] **Step 3: Run the app and verify it starts**

```bash
flutter run
```

Expected: App launches, AppBar is deep red, no cyan anywhere yet.

- [ ] **Step 4: Commit**

```bash
git add lib/theme/app_theme.dart lib/main.dart
git commit -m "feat: introduce Material 3 AppTheme with safety-red colour scheme"
```

---

## Task 2: Navigation Bar

**Files:**
- Modify: `lib/navigation_bar/main_page.dart`

Current problems: `BottomNavigationBar` (deprecated in M3), icons don't match their tabs (`Icons.emergency` is on the Location tab, `Icons.home` is on SOS), labels hidden entirely, sign-out embedded in a child screen.

- [ ] **Step 1: Rewrite `lib/navigation_bar/main_page.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:safetyproject/contact/personal_emergency_contacts.dart';
import 'package:safetyproject/location/googlemap_page.dart';
import 'package:safetyproject/pages/sos.dart';

import '../oauth/auth_controller.dart';
import '../pages/location_page.dart';

class NavBarPage extends StatefulWidget {
  const NavBarPage({Key? key, required this.email}) : super(key: key);

  final String email;

  @override
  State<NavBarPage> createState() => _NavBarPageState();
}

class _NavBarPageState extends State<NavBarPage> {
  int _currentIndex = 1;

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.location_on_outlined),
      selectedIcon: Icon(Icons.location_on),
      label: 'Track',
    ),
    NavigationDestination(
      icon: Icon(Icons.emergency_outlined),
      selectedIcon: Icon(Icons.emergency),
      label: 'SOS',
    ),
    NavigationDestination(
      icon: Icon(Icons.contacts_outlined),
      selectedIcon: Icon(Icons.contacts),
      label: 'Contacts',
    ),
    NavigationDestination(
      icon: Icon(Icons.map_outlined),
      selectedIcon: Icon(Icons.map),
      label: 'Map',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final screens = [
      LocationPage(),
      const SosPage(),
      const PersonalEmergencyContacts(deleteFunction: _delete),
      GoogleMapPage(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Safety App'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () => AuthController.instance.logOut(),
          ),
        ],
      ),
      body: screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: _destinations,
      ),
    );
  }
}

void _delete(int id) {}
```

- [ ] **Step 2: Run and verify**

```bash
flutter run
```

Expected: Bottom nav shows 4 tabs with correct icons and labels (Track, SOS, Contacts, Map). Sign out icon is in the top-right AppBar. Tapping tabs switches screens.

- [ ] **Step 3: Commit**

```bash
git add lib/navigation_bar/main_page.dart
git commit -m "feat: replace BottomNavigationBar with M3 NavigationBar, fix icons/labels, move sign-out to AppBar"
```

---

## Task 3: SOS Page

**Files:**
- Modify: `lib/pages/sos.dart`

Current bugs:
- Outer `GestureDetector` wrapping the SOS call button has `onTap: logOut()` — any tap in that area signs the user out
- Sign-out button duplicated from the nav bar (now removed in Task 2, so just delete it)
- No confirmation before calling emergency contact

- [ ] **Step 1: Rewrite `lib/pages/sos.dart`**

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:flutter_sms/flutter_sms.dart';
import 'package:permission_handler/permission_handler.dart';

import '../contact/personal_emergency_contacts_model.dart';
import '../database/db_helper.dart';

class SosPage extends StatefulWidget {
  const SosPage({Key? key}) : super(key: key);

  @override
  _SosPageState createState() => _SosPageState();
}

class _SosPageState extends State<SosPage> {
  late final DBHelper _dbHelper = DBHelper();

  @override
  void initState() {
    super.initState();
    _requestPermission();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Text(
                'Emergency',
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              _BigCircleButton(
                label: 'SOS\nCall',
                color: colorScheme.error,
                onColor: colorScheme.onError,
                icon: Icons.phone_in_talk,
                onPressed: () => _handleAction(_callEmergencyContact),
              ),
              _BigCircleButton(
                label: 'SMS\nAlert',
                color: colorScheme.primary,
                onColor: colorScheme.onPrimary,
                icon: Icons.message,
                onPressed: () => _handleAction(_sendTextsToContacts),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleAction(Future<void> Function() action) async {
    final contacts = await _dbHelper.getContacts();
    if (!mounted) return;
    if (contacts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text("Add emergency contacts first."),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
      return;
    }
    final confirmed = await _showConfirmation();
    if (confirmed == true) await action();
  }

  Future<bool?> _showConfirmation() => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Confirm'),
          content: const Text('Send an emergency alert now?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Yes, send'),
            ),
          ],
        ),
      );

  Future<void> _callEmergencyContact() async {
    final contacts = await _dbHelper.getContacts();
    await FlutterPhoneDirectCaller.callNumber(contacts.first.contactNo);
  }

  Future<void> _sendTextsToContacts() async {
    final contacts = await _dbHelper.getContacts();
    final snap = await FirebaseFirestore.instance
        .collection('location')
        .doc('user1')
        .get();
    final vals = snap.data()?.values.toList();
    final lat = vals?.isNotEmpty == true ? vals![0] : '?';
    final lng = vals?.length == 2 ? vals![1] : '?';
    final message =
        'I need help, please find me: https://maps.google.com/?q=$lat,$lng';
    final recipients = contacts.map((c) => c.contactNo).toList();
    await sendSMS(message: message, recipients: recipients);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('SMS compose opened — tap Send to alert your contacts'),
    ));
  }
}

class _BigCircleButton extends StatelessWidget {
  const _BigCircleButton({
    required this.label,
    required this.color,
    required this.onColor,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final Color color;
  final Color onColor;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        fixedSize: const Size(160, 160),
        shape: const CircleBorder(),
        backgroundColor: color,
        foregroundColor: onColor,
        elevation: 6,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 36),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

Future<void> _requestPermission() async {
  final status = await Permission.location.request();
  if (status.isDenied) await _requestPermission();
  if (status.isPermanentlyDenied) await openAppSettings();
}
```

- [ ] **Step 2: Run and verify**

```bash
flutter run
```

Expected: SOS tab shows "Emergency" heading, two large circles (red SOS Call, theme-primary SMS Alert). Tapping either shows a confirmation dialog. No sign-out button visible. No accidental logout on tap.

- [ ] **Step 3: Commit**

```bash
git add lib/pages/sos.dart
git commit -m "fix: SOS page — remove logOut bug, add confirmation dialog, adopt M3 theme"
```

---

## Task 4: Login Page

**Files:**
- Modify: `lib/pages/login_page.dart`

Current problems: Custom `Container`+`GestureDetector` button (no ripple, no a11y), "Forgot your Password?" does nothing, no form validation.

- [ ] **Step 1: Rewrite `lib/pages/login_page.dart`**

```dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../oauth/auth_controller.dart';
import '../pages/signup_page.dart';

class LoginPage extends StatefulWidget {
  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 48),
                Text('Hello',
                    style: Theme.of(context)
                        .textTheme
                        .displaySmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('Sign into your account',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  validator: (v) =>
                      v == null || !v.contains('@') ? 'Enter a valid email' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (v) =>
                      v == null || v.length < 6 ? 'Min 6 characters' : null,
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _forgotPassword,
                    child: const Text('Forgot password?'),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _submit,
                  child: const Text('Sign in',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 24),
                Center(
                  child: RichText(
                    text: TextSpan(
                      text: "Don't have an account?  ",
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 15),
                      children: [
                        TextSpan(
                          text: 'Create one',
                          style: TextStyle(
                              color: scheme.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 15),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () => Get.to(() => const SignUpPage()),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Enter your email above first'),
      ));
      return;
    }
    await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Reset link sent to $email'),
    ));
  }
}
```

- [ ] **Step 2: Run and verify**

```bash
flutter run
```

Expected: Login page shows large "Hello" heading, two labeled text fields, password visibility toggle, working "Forgot password?" that sends a reset email (check spam), `FilledButton` with ripple. Submitting empty fields shows inline validation errors.

- [ ] **Step 3: Commit**

```bash
git add lib/pages/login_page.dart
git commit -m "feat: login page — FilledButton, form validation, working forgot-password"
```

---

## Task 5: Sign-Up Page

**Files:**
- Modify: `lib/pages/signup_page.dart`

Current problems: Three social-login `CircleAvatar` images (g.png, t.png, f.png) with no `onTap` — dead UI. Custom button same as login.

- [ ] **Step 1: Rewrite `lib/pages/signup_page.dart`**

```dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../oauth/auth_controller.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({Key? key}) : super(key: key);

  @override
  _SignUpPageState createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create account'),
        leading: BackButton(onPressed: () => Get.back()),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  validator: (v) =>
                      v == null || !v.contains('@') ? 'Enter a valid email' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (v) =>
                      v == null || v.length < 6 ? 'Min 6 characters' : null,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _submit,
                  child: const Text('Create account',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 16),
                Center(
                  child: RichText(
                    text: TextSpan(
                      text: 'Already have an account?  ',
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 15),
                      children: [
                        TextSpan(
                          text: 'Sign in',
                          style: TextStyle(
                              color: scheme.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 15),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () => Get.back(),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
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
      _passwordController.text.trim(),
    );
  }
}
```

- [ ] **Step 2: Run and verify**

```bash
flutter run
```

Expected: Signup has AppBar with back button, two labeled fields with validation, password visibility toggle, `FilledButton`, no social login icons.

- [ ] **Step 3: Commit**

```bash
git add lib/pages/signup_page.dart
git commit -m "feat: signup page — remove dead social buttons, FilledButton, form validation"
```

---

## Task 6: Contacts Page — Empty State & Bottom Sheet

**Files:**
- Modify: `lib/contact/personal_emergency_contacts.dart`

Current problems: Blank screen when no contacts added (no empty state), `AlertDialog` for add (feels dated), `getData()` called inside FutureBuilder without guarding null snapshot.

- [ ] **Step 1: Rewrite `lib/contact/personal_emergency_contacts.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';

import './contact_list.dart';
import './personal_emergency_contacts_model.dart';
import '../database/db_helper.dart';

class PersonalEmergencyContacts extends StatefulWidget {
  const PersonalEmergencyContacts({required this.deleteFunction, Key? key})
      : super(key: key);

  final Function deleteFunction;

  @override
  _PersonalEmergencyContactsState createState() =>
      _PersonalEmergencyContactsState();
}

class _PersonalEmergencyContactsState
    extends State<PersonalEmergencyContacts> {
  late final DBHelper _dbHelper = DBHelper();
  late Future<List<PersonalEmergency>> _contactsFuture;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() => setState(() => _contactsFuture = _dbHelper.getContacts());

  Future<void> _deleteContact(int id) async {
    await _dbHelper.delete(id);
    _refresh();
  }

  Future<void> _showAddSheet() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add contact',
                  style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextFormField(
                controller: nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Enter a name' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone number',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Enter a number';
                  if (v.trim().length < 7) return 'Number too short';
                  return null;
                },
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () {
                  if (formKey.currentState?.validate() != true) return;
                  _dbHelper.add(PersonalEmergency(
                      nameCtrl.text.trim(), phoneCtrl.text.trim()));
                  Navigator.pop(ctx);
                  _refresh();
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Contact added'),
                  ));
                },
                child: const Text('Add'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<PersonalEmergency>>(
        future: _contactsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final contacts = snapshot.data ?? [];
          if (contacts.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.contact_phone_outlined,
                      size: 72,
                      color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 16),
                  Text('No emergency contacts yet',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text('Tap + to add one',
                      style: TextStyle(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: contacts.length,
            separatorBuilder: (_, __) => const SizedBox(height: 4),
            itemBuilder: (context, i) {
              final contact = contacts[i];
              final initials = contact.name.isNotEmpty
                  ? contact.name[0].toUpperCase()
                  : '?';
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        Theme.of(context).colorScheme.primaryContainer,
                    foregroundColor:
                        Theme.of(context).colorScheme.onPrimaryContainer,
                    child: Text(initials),
                  ),
                  title: Text(contact.name),
                  subtitle: Text(contact.contactNo),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.phone_outlined),
                        onPressed: () => FlutterPhoneDirectCaller.callNumber(
                            contact.contactNo),
                      ),
                      IconButton(
                        icon: Icon(Icons.delete_outline,
                            color: Theme.of(context).colorScheme.error),
                        onPressed: () => _confirmDelete(contact, i),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddSheet,
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('Add contact'),
      ),
    );
  }

  Future<void> _confirmDelete(PersonalEmergency contact, int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete contact'),
        content: Text('Remove ${contact.name}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true) await _deleteContact(contact.id);
  }
}
```

- [ ] **Step 2: Run and verify**

```bash
flutter run
```

Expected: Contacts tab with no contacts shows an icon + "No emergency contacts yet". Tapping `Add contact` FAB slides up a bottom sheet with Name and Phone fields with validation. Adding a contact refreshes the list. Delete shows a confirmation dialog.

- [ ] **Step 3: Commit**

```bash
git add lib/contact/personal_emergency_contacts.dart
git commit -m "feat: contacts — empty state, modal bottom sheet for add, theme-aware colours"
```

---

## Task 7: Location Page — Cleaner Coordinate Display

**Files:**
- Modify: `lib/pages/location_page.dart`

Current problem: Raw `latitude, longitude` numbers in a plain `ListView` — hard to read. Replace with a `Card`.

- [ ] **Step 1: Replace the StreamBuilder section in `lib/pages/location_page.dart`**

Find the `Expanded` widget (around line 209) containing the `StreamBuilder` and replace it with:

```dart
Expanded(
  child: StreamBuilder(
    stream:
        FirebaseFirestore.instance.collection('location').snapshots(),
    builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final docs = snapshot.data!.docs;
      if (docs.isEmpty) {
        return Center(
          child: Text('No locations shared yet',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        );
      }
      return ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: docs.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final doc = docs[index];
          final lat = doc['latitude'];
          final lng = doc['longitude'];
          return Card(
            child: ListTile(
              leading: Icon(Icons.location_pin,
                  color: Theme.of(context).colorScheme.primary),
              title: Text(doc.id),
              subtitle: Text('$lat, $lng'),
              trailing: IconButton(
                icon: const Icon(Icons.directions),
                onPressed: () {
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (context) => MyMap(doc.id)));
                },
              ),
            ),
          );
        },
      );
    },
  ),
),
```

Also add the missing import at the top of the file (already present: `import '../location/mymap.dart'`).

- [ ] **Step 2: Run and verify**

```bash
flutter run
```

Expected: Location tab shows a Card per tracked user with their doc ID, formatted lat/lng, and a directions button. Empty state shows "No locations shared yet".

- [ ] **Step 3: Commit**

```bash
git add lib/pages/location_page.dart
git commit -m "feat: location page — Card-based coordinate display with empty state"
```

---

## Self-Review

### Spec Coverage
- [x] Material 3 theme — Task 1
- [x] Fix nav bar icons/labels, upgrade to NavigationBar — Task 2
- [x] Move sign-out to AppBar — Task 2
- [x] Fix SOS logOut bug — Task 3
- [x] Add confirmation before emergency call — Task 3
- [x] Remove dead social login buttons — Task 5
- [x] FilledButton replaces Container+GestureDetector on auth pages — Tasks 4 & 5
- [x] Forgot password — Task 4
- [x] Form validation on auth pages — Tasks 4 & 5
- [x] Empty state on contacts — Task 6
- [x] Bottom sheet for add contact (replaces AlertDialog) — Task 6
- [x] Better location coordinate display — Task 7

### Placeholder Scan
None found — every step contains full code.

### Type Consistency
- `PersonalEmergency.id` used in Task 6 (`_deleteContact(contact.id)`) — matches the model field used in the original code throughout (`cl.emergencyContactsId.add(contact.id)`) ✓
- `_dbHelper.getContacts()` returns `Future<List<PersonalEmergency>>` — consistent with original DBHelper usage ✓
- `AuthController.instance.login/register/logOut()` — unchanged ✓
