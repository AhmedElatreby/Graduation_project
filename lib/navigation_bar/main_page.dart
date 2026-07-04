// ─────────────────────────────────────────────────────────────────────────────
//  Lumi · main navigation (custom tab bar)
//  Replaces:  lib/navigation_bar/main_page.dart
//  Hosts the 4 content pages over the midnight gradient, with the Lumi tab bar
//  (SOS emphasised). Keeps AuthController sign-out.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:shake/shake.dart';

import '../contact/personal_emergency_contacts.dart';
import '../location/googlemap_page.dart';
import '../oauth/auth_controller.dart';
import '../pages/location_page.dart';
import '../pages/sos.dart';
import '../services/emergency_alert.dart';
import '../services/shake_prefs.dart';
import '../theme/lumi_theme.dart';
import '../widgets/lumi_logo.dart';
import '../widgets/sos_countdown.dart';

class NavBarPage extends StatefulWidget {
  const NavBarPage({super.key, required this.email});
  final String email;

  @override
  State<NavBarPage> createState() => _NavBarPageState();
}

class _NavBarPageState extends State<NavBarPage> {
  int _index = 1; // start on SOS

  // ── shake-to-SOS ────────────────────────────────────────────────────────────
  // Lives here (not in SosPage) so shaking works on every tab; dies with this
  // page on logout. See docs/superpowers/specs/2026-07-04-shake-to-sos-design.md
  ShakeDetector? _shakeDetector;
  bool _countdownShowing = false;

  late final List<Widget> _pages = [
    const LocationPage(),
    SosPage(userName: _nameFromEmail(widget.email)),
    const PersonalEmergencyContacts(),
    GoogleMapPage(), // your existing map (keeps its own Scaffold)
  ];

  @override
  void initState() {
    super.initState();
    ShakePrefs.enabled.addListener(_syncShakeDetector);
    _syncShakeDetector();
  }

  @override
  void dispose() {
    ShakePrefs.enabled.removeListener(_syncShakeDetector);
    _shakeDetector?.stopListening();
    _shakeDetector = null;
    super.dispose();
  }

  void _syncShakeDetector() {
    if (ShakePrefs.enabled.value) {
      _shakeDetector ??= ShakeDetector.autoStart(
        onPhoneShake: (_) => _onShake(),
        // Two distinct shakes required — cuts down pocket/bag false alarms.
        minimumShakeCount: 2,
      );
    } else {
      _shakeDetector?.stopListening();
      _shakeDetector = null;
    }
  }

  Future<void> _onShake() async {
    if (_countdownShowing || !mounted) return;
    _countdownShowing = true;
    try {
      setState(() => _index = 1); // jump to the SOS tab behind the overlay
      final sent = await showSosCountdown(context, onSend: () async {
        final failures = await EmergencyAlert.send();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(failures.isEmpty
              ? 'Emergency alert sent to your guardians'
              : failures.join(' · ')),
          backgroundColor:
              (failures.isEmpty ? LumiColors.green : LumiColors.accent)
                  .withOpacity(0.9),
        ));
      });
      if (!sent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Cancelled — no alert sent'),
          backgroundColor: LumiColors.surface.withOpacity(0.95),
        ));
      }
    } finally {
      _countdownShowing = false;
    }
  }

  String _nameFromEmail(String e) {
    final base = e.contains('@') ? e.split('@').first : e;
    if (base.isEmpty) return 'there';
    return base[0].toUpperCase() + base.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final isMap = _index == 3;
    return Scaffold(
      extendBody: true,
      backgroundColor: LumiColors.bgDeep,
      body: Container(
        decoration: isMap
            ? null
            : const BoxDecoration(gradient: LumiColors.screenGradient),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              if (!isMap) _topBar(),
              Expanded(child: IndexedStack(index: _index, children: _pages)),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _LumiTabBar(
        index: _index,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 14, 2),
      child: Row(
        children: [
          const LumiMark(size: 30),
          const SizedBox(width: 10),
          Text('Lumi', style: LumiText.display(18)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.logout, color: LumiColors.textSub, size: 20),
            onPressed: () => AuthController.instance.logOut(),
          ),
        ],
      ),
    );
  }
}

class _LumiTabBar extends StatelessWidget {
  const _LumiTabBar({required this.index, required this.onTap});
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xF2080B14), // 0.92 opacity midnight
        border: Border(top: BorderSide(color: LumiColors.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 70,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _tab(0, Icons.location_on_outlined, Icons.location_on, 'Track'),
              _sosTab(1),
              _tab(2, Icons.people_outline, Icons.people, 'Contacts'),
              _tab(3, Icons.map_outlined, Icons.map, 'Map'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tab(int i, IconData icon, IconData active, String label) {
    final on = index == i;
    final color = on ? LumiColors.accent : LumiColors.textFaint;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onTap(i),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(on ? active : icon, color: color, size: 22),
          const SizedBox(height: 4),
          Text(label,
              style: LumiText.body(10,
                  weight: on ? FontWeight.w700 : FontWeight.w600,
                  color: color)),
        ],
      ),
    );
  }

  Widget _sosTab(int i) {
    final on = index == i;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onTap(i),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              gradient: on ? LumiColors.accentGradient : null,
              color: on ? null : const Color(0xFF1A2030),
              borderRadius: BorderRadius.circular(11),
              boxShadow: on
                  ? [
                      BoxShadow(
                          color: LumiColors.accent.withOpacity(0.5),
                          blurRadius: 14,
                          offset: const Offset(0, 5))
                    ]
                  : null,
            ),
            alignment: Alignment.center,
            child: Text('SOS',
                style: LumiText.display(11,
                    color: on ? Colors.white : LumiColors.textFaint)),
          ),
          const SizedBox(height: 4),
          Text('SOS',
              style: LumiText.body(10,
                  weight: FontWeight.w700,
                  color: on ? LumiColors.accent : LumiColors.textFaint)),
        ],
      ),
    );
  }
}
