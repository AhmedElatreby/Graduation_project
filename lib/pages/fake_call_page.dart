// lib/pages/fake_call_page.dart
// ─────────────────────────────────────────────────────────────────────────────
//  Lumi · Fake-call screens
//  IncomingCallPage: generic dark incoming-call look — ringtone + vibration,
//  Decline/Answer. InCallPage: running timer and cosmetic controls. Neither
//  touches any alert path; the whole feature is an act.
//  Back-gesture is disabled while ringing — like a real call, Decline is the
//  only way out.
//  See docs/superpowers/specs/2026-07-19-fake-call-design.md
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/fake_call_controller.dart';
import '../services/fake_call_prefs.dart';
import '../services/fake_call_sounds.dart';
import '../theme/lumi_theme.dart';

class IncomingCallPage extends StatefulWidget {
  const IncomingCallPage({super.key, this.sounds, this.controller});

  final FakeCallSounds? sounds;
  final FakeCallController? controller;

  @override
  State<IncomingCallPage> createState() => _IncomingCallPageState();
}

class _IncomingCallPageState extends State<IncomingCallPage> {
  late final FakeCallSounds _sounds = widget.sounds ?? RingtoneFakeCallSounds();
  late final FakeCallController _controller =
      widget.controller ?? FakeCallController.instance;
  Timer? _vibrate;

  @override
  void initState() {
    super.initState();
    _sounds.start();
    // The ringtone plugin doesn't vibrate; a 1s haptic pulse reads as a
    // ringing phone in the hand (and is the whole fallback if audio fails).
    _vibrate = Timer.periodic(
        const Duration(seconds: 1), (_) => HapticFeedback.vibrate());
  }

  @override
  void dispose() {
    _vibrate?.cancel();
    _sounds.stop();
    super.dispose();
  }

  void _decline() {
    _controller.end();
    Navigator.of(context).pop();
  }

  void _answer() {
    _vibrate?.cancel();
    _sounds.stop();
    _controller.answer();
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => InCallPage(controller: _controller)));
  }

  @override
  Widget build(BuildContext context) {
    final name = FakeCallPrefs.callerName.value;
    final number = FakeCallPrefs.callerNumber.value;
    return PopScope(
      canPop: false, // a real call can't be back-swiped away
      child: Scaffold(
        backgroundColor: const Color(0xFF0B0F1A),
        body: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 64),
              Text('Incoming call',
                  style: LumiText.body(13, color: LumiColors.textSub)),
              const SizedBox(height: 26),
              CircleAvatar(
                radius: 46,
                backgroundColor: LumiColors.surface,
                child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
                    style: LumiText.display(34)),
              ),
              const SizedBox(height: 18),
              Text(name, style: LumiText.display(28)),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Mobile · ',
                      style: LumiText.body(14, color: LumiColors.textSub)),
                  Text(number,
                      style: LumiText.body(14, color: LumiColors.textSub)),
                ],
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 56),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _RoundAction(
                      icon: Icons.call_end,
                      label: 'Decline',
                      color: LumiColors.accent,
                      onTap: _decline,
                    ),
                    _RoundAction(
                      icon: Icons.call,
                      label: 'Answer',
                      color: LumiColors.green,
                      onTap: _answer,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class InCallPage extends StatefulWidget {
  const InCallPage({super.key, this.controller});

  final FakeCallController? controller;

  @override
  State<InCallPage> createState() => _InCallPageState();
}

class _InCallPageState extends State<InCallPage> {
  late final FakeCallController _controller =
      widget.controller ?? FakeCallController.instance;
  Timer? _tick;
  int _seconds = 0;
  bool _muted = false;
  bool _speaker = false;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String get _elapsed {
    final m = _seconds ~/ 60;
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _hangUp() {
    _controller.end();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final name = FakeCallPrefs.callerName.value;
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F1A),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 64),
            CircleAvatar(
              radius: 40,
              backgroundColor: LumiColors.surface,
              child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
                  style: LumiText.display(30)),
            ),
            const SizedBox(height: 16),
            Text(name, style: LumiText.display(24)),
            const SizedBox(height: 6),
            Text(_elapsed, style: LumiText.body(15, color: LumiColors.textSub)),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _CosmeticToggle(
                  icon: _muted ? Icons.mic_off : Icons.mic,
                  label: 'Mute',
                  active: _muted,
                  onTap: () => setState(() => _muted = !_muted),
                ),
                _CosmeticToggle(
                  icon: Icons.dialpad,
                  label: 'Keypad',
                  active: false,
                  onTap: () {}, // looks tappable; does nothing
                ),
                _CosmeticToggle(
                  icon: Icons.volume_up,
                  label: 'Speaker',
                  active: _speaker,
                  onTap: () => setState(() => _speaker = !_speaker),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 44),
              child: _RoundAction(
                icon: Icons.call_end,
                label: '',
                color: LumiColors.accent,
                onTap: _hangUp,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
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
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 30),
          ),
          if (label.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(label, style: LumiText.body(13, color: LumiColors.textSub)),
          ],
        ],
      ),
    );
  }
}

class _CosmeticToggle extends StatelessWidget {
  const _CosmeticToggle({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: active
                  ? Colors.white.withValues(alpha: 0.25)
                  : Colors.white.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 8),
          Text(label, style: LumiText.body(12, color: LumiColors.textSub)),
        ],
      ),
    );
  }
}
