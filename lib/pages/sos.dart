// ─────────────────────────────────────────────────────────────────────────────
//  Lumi · SOS (home tab)
//  Replaces:  lib/pages/sos.dart
//  Returns CONTENT only (no Scaffold) — LumiMainNav provides the gradient + bar.
//
//  ★ #5  HOLD-THEN-RELEASE: press & hold the big SOS button — a ring fills; the
//        alert fires only when you LIFT your finger while the ring is full. If
//        you slide your finger off the button, the hold is CANCELLED (nothing
//        sends).
//  ★ #6  Siren now uses the app-wide Siren singleton, so it keeps playing until
//        the clip finishes even if you leave this screen.
//  ★ #7  Two clear quick actions in the SOS page: Send SMS and Call (plus Siren).
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../database/db_helper.dart';
import '../services/emergency_alert.dart';
import '../services/siren.dart';
import '../theme/lumi_theme.dart';
import '../widgets/lumi_widgets.dart';

class SosPage extends StatefulWidget {
  const SosPage({super.key, this.userName = 'there'});
  final String userName;

  @override
  State<SosPage> createState() => _SosPageState();
}

class _SosPageState extends State<SosPage> with TickerProviderStateMixin {
  final DBHelper _dbHelper = DBHelper();

  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2400))
    ..repeat();

  // ── hold-to-send ────────────────────────────────────────────────────────────
  final GlobalKey _sosKey = GlobalKey();
  late final AnimationController _hold = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400));
  bool _armed = false; // finger is down and still on the button

  bool _isProcessing = false;
  int _guardianCount = 0;

  @override
  void initState() {
    super.initState();
    _requestPermission();
    _loadCount();
  }

  Future<void> _loadCount() async {
    final c = await _dbHelper.getContacts();
    if (mounted) setState(() => _guardianCount = c.length);
  }

  @override
  void dispose() {
    _pulse.dispose();
    _hold.dispose();
    super.dispose();
  }

  // ── hold gesture handlers ─────────────────────────────────────────────────
  void _onDown(PointerDownEvent e) {
    if (_isProcessing) return;
    _armed = true;
    HapticFeedback.selectionClick();
    _hold.forward(from: 0);
  }

  void _onMove(PointerMoveEvent e) {
    if (!_armed) return;
    final box = _sosKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(e.position);
    final r = box.size.width / 2;
    final center = Offset(r, r);
    final within = (local - center).distance <= r + 10; // circular hit test
    if (!within) _cancelHold(slidOff: true);
  }

  void _onUp(PointerUpEvent e) {
    if (!_armed) return;
    final full = _hold.value >= 1.0;
    _armed = false;
    if (full) {
      _hold.value = 0;
      HapticFeedback.heavyImpact();
      _handleAction(_triggerFullAlert);
    } else {
      _hold.reverse();
      _snack('Keep holding until the ring fills, then release.',
          LumiColors.textSub);
    }
  }

  void _cancelHold({bool slidOff = false}) {
    if (!_armed) return;
    _armed = false;
    _hold.reverse();
    if (slidOff) {
      HapticFeedback.lightImpact();
      _snack('Cancelled — you slid off the button.', LumiColors.textSub);
    }
  }

  @override
  Widget build(BuildContext context) {
    // NavBarPage's Scaffold uses extendBody: true, which injects the
    // bottomNavigationBar's actual rendered height into MediaQuery's bottom
    // padding for this body subtree — SafeArea consumes exactly that value,
    // so the quick-actions row stays clear of the bar on every device
    // instead of guessing at a fixed pixel count (see location_page.dart).
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 6, 22, 0),
        child: Column(
          children: [
            // greeting row
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Good evening,',
                          style: LumiText.body(13, color: LumiColors.textSub)),
                      Text(widget.userName, style: LumiText.display(20)),
                    ],
                  ),
                ),
                CircleAvatar(
                  radius: 20,
                  backgroundColor: const Color(0xFF222C44),
                  child: Text(
                    widget.userName.isNotEmpty
                        ? widget.userName[0].toUpperCase()
                        : '?',
                    style: LumiText.display(15, color: const Color(0xFFC3CBDC)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            LumiStatusPill(
                label: _guardianCount > 0
                    ? 'Protected · $_guardianCount guardians watching'
                    : 'Add guardians to stay protected'),

            // big SOS — press & hold, release to send
            Expanded(
              child: Center(
                child: Listener(
                  onPointerDown: _onDown,
                  onPointerMove: _onMove,
                  onPointerUp: _onUp,
                  onPointerCancel: (_) => _cancelHold(),
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_pulse, _hold]),
                    builder: (_, child) {
                      return SizedBox(
                        width: 240,
                        height: 240,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // idle pulse rings (fade out while holding)
                            for (int i = 0; i < 3; i++)
                              Builder(builder: (_) {
                                final t = (_pulse.value + i / 3) % 1.0;
                                return Opacity(
                                  opacity: (1 - t) * 0.55 * (1 - _hold.value),
                                  child: Container(
                                    width: 150 + t * 90,
                                    height: 150 + t * 90,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: LumiColors.accent, width: 2),
                                    ),
                                  ),
                                );
                              }),
                            // hold progress ring
                            if (_hold.value > 0)
                              SizedBox(
                                width: 208,
                                height: 208,
                                child: CircularProgressIndicator(
                                  value: _hold.value,
                                  strokeWidth: 6,
                                  backgroundColor:
                                      Colors.white.withValues(alpha: 0.12),
                                  valueColor: const AlwaysStoppedAnimation(
                                      Colors.white),
                                ),
                              ),
                            child!,
                          ],
                        ),
                      );
                    },
                    child: Container(
                      key: _sosKey,
                      width: 184,
                      height: 184,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LumiColors.accentGradient,
                        boxShadow: [
                          BoxShadow(
                            color: LumiColors.accent.withValues(alpha: 0.5),
                            blurRadius: 56,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('SOS',
                              style: LumiText.display(50, color: Colors.white)),
                          const SizedBox(height: 7),
                          AnimatedBuilder(
                            animation: _hold,
                            builder: (_, __) => Text(_holdLabel(),
                                style: GoogleFontsHelper.upper()),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Text(
                'Hold, then release to call your first contact & text everyone your live location.',
                textAlign: TextAlign.center,
                style: LumiText.body(12.5, color: LumiColors.textSub)),
            const SizedBox(height: 16),

            // quick actions — #7: clear SMS + Call, plus Siren
            Row(
              children: [
                _QuickAction(
                    icon: Icons.sms_outlined,
                    label: 'Send SMS',
                    color: LumiColors.blue,
                    onTap: () => _handleAction(_sendTextsToContacts)),
                const SizedBox(width: 10),
                _QuickAction(
                    icon: Icons.call_outlined,
                    label: 'Call',
                    color: LumiColors.green,
                    onTap: () => _handleAction(_callEmergencyContact)),
                const SizedBox(width: 10),
                _QuickAction(
                    icon: Icons.campaign_outlined,
                    label: 'Siren',
                    color: LumiColors.amber,
                    onTap: _siren),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  String _holdLabel() {
    // AnimationController.reverse() rarely lands on exactly 0.0, so a strict
    // equality check here left the label stuck on "KEEP HOLDING" forever
    // after a cancelled hold. A small tolerance (and checking the animation
    // status, not just the raw value) makes it settle back to idle.
    if (!_armed && _hold.status == AnimationStatus.dismissed) {
      return 'HOLD TO ALERT';
    }
    if (_hold.value >= 1.0) return 'RELEASE TO SEND';
    return 'KEEP HOLDING';
  }

  // ── actions ────────────────────────────────────────────────────────────────
  Future<void> _handleAction(Future<void> Function() action) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      final contacts = await _dbHelper.getContacts();
      if (!mounted) return;
      if (contacts.isEmpty) {
        _snack('Add emergency contacts first.', LumiColors.accent);
        return;
      }
      await action();
    } catch (e) {
      if (mounted) _snack('Something went wrong: $e', LumiColors.accent);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // Alert mechanics live in EmergencyAlert so the shake-to-SOS flow shares
  // the exact same code path as this button.
  Future<void> _triggerFullAlert() async {
    final failures = await EmergencyAlert.send();
    if (failures.isNotEmpty && mounted) {
      _snack(failures.join(' · '), LumiColors.accent);
    }
  }

  Future<void> _callEmergencyContact() => EmergencyAlert.callFirstContact();

  Future<void> _sendTextsToContacts() async {
    await EmergencyAlert.sendTexts();
    if (!mounted) return;
    _snack('Emergency SMS sent to your contacts', LumiColors.green);
  }

  Future<void> _siren() async {
    await Siren.instance.play(); // keeps playing after you leave this screen
    if (!mounted) return;
    _snack('Siren activated!', LumiColors.amber);
  }

  void _snack(String msg, Color c) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: c.withValues(alpha: 0.9),
    ));
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: LumiCard(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 5),
              Text(label,
                  style: LumiText.body(11,
                      weight: FontWeight.w600, color: const Color(0xFFB9C2D6))),
            ],
          ),
        ),
      ),
    );
  }
}

/// tiny helper for the uppercase micro-label inside the SOS button
class GoogleFontsHelper {
  static TextStyle upper() => LumiText.body(11.5,
      weight: FontWeight.w700, color: Colors.white.withValues(alpha: 0.85));
}

Future<void> _requestPermission() async {
  for (int attempt = 0; attempt < 2; attempt++) {
    final status = await Permission.location.request();
    if (status.isGranted) return;
    if (status.isPermanentlyDenied) {
      await openAppSettings();
      return;
    }
  }
}
