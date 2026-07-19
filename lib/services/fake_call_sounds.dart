// ─────────────────────────────────────────────────────────────────────────────
//  Lumi · Fake-call ring sound
//  Thin seam over flutter_ringtone_player so widget tests can inject a fake
//  and so a plugin failure on odd OEMs degrades silently — the vibration
//  loop and the call screen still sell the act.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';

abstract class FakeCallSounds {
  Future<void> start();
  Future<void> stop();
}

/// Plays the device's actual system default ringtone — the most convincing
/// sound a phone can make, because it's the one this phone makes.
class RingtoneFakeCallSounds implements FakeCallSounds {
  final _player = FlutterRingtonePlayer();

  @override
  Future<void> start() async {
    try {
      await _player.playRingtone(looping: true, volume: 1.0);
    } catch (_) {/* degrade to vibration-only; never crash mid-performance */}
  }

  @override
  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
  }
}
