// ─────────────────────────────────────────────────────────────────────────────
//  Lumi · SOS countdown
//  Full-screen "sending in 5…4…" overlay shown by shake-to-SOS. Cancel stops
//  everything; letting it reach zero invokes onSend (the caller passes
//  EmergencyAlert.send and handles the result).
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/lumi_theme.dart';

/// Shows the countdown as a barrier-proof full-screen dialog. Resolves after
/// the dialog closes: true if the countdown completed and [onSend] was
/// invoked, false if the user cancelled.
Future<bool> showSosCountdown(
  BuildContext context, {
  required Future<void> Function() onSend,
  int seconds = 5,
}) async {
  final sent = await showDialog<bool>(
    context: context,
    barrierDismissible: false, // Cancel is the only way out
    barrierColor: Colors.black87,
    useSafeArea: false,
    builder: (_) => _SosCountdown(seconds: seconds),
  );
  if (sent == true) {
    await onSend();
    return true;
  }
  return false;
}

class _SosCountdown extends StatefulWidget {
  const _SosCountdown({required this.seconds});
  final int seconds;

  @override
  State<_SosCountdown> createState() => _SosCountdownState();
}

class _SosCountdownState extends State<_SosCountdown> {
  late int _remaining = widget.seconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    HapticFeedback.heavyImpact();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _remaining--);
      if (_remaining <= 0) {
        _timer?.cancel();
        Navigator.of(context).pop(true);
      } else {
        HapticFeedback.heavyImpact();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 30, 26, 24),
          child: Column(
            children: [
              const SizedBox(height: 18),
              Text('Shake detected',
                  style: LumiText.display(24, color: Colors.white)),
              const SizedBox(height: 8),
              Text('Alerting your guardians in',
                  style: LumiText.body(15, color: LumiColors.textSub)),
              Expanded(
                child: Center(
                  child: Container(
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LumiColors.accentGradient,
                      boxShadow: [
                        BoxShadow(
                          color: LumiColors.accent.withOpacity(0.5),
                          blurRadius: 60,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Text('$_remaining',
                        style: LumiText.display(96, color: Colors.white)),
                  ),
                ),
              ),
              // Big, hard-to-miss cancel — the whole point of the countdown.
              SizedBox(
                width: double.infinity,
                height: 74,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: LumiColors.bgDeep,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                  ),
                  child: Text("I'm safe — cancel",
                      style: LumiText.display(19, color: LumiColors.bgDeep)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
