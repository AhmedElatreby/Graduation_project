// ─────────────────────────────────────────────────────────────────────────────
//  Lumi · Siren service (singleton)
//  Drop this in:  lib/services/siren.dart
//
//  Why: the alarm used to stop the instant you left the screen because each page
//  created its own AudioPlayer and disposed it in dispose(). This owns ONE player
//  for the whole app, so the sound keeps playing until the clip finishes (or you
//  explicitly stop it) — navigating between tabs no longer kills it.
//
//  Note on full background playback (screen off / app minimised): Android will
//  keep this alarm-usage stream going for a while, but a *guaranteed* background
//  siren needs a foreground-service plugin. This covers "don't stop when I switch
//  screens / leave this page", which is what was breaking.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:audioplayers/audioplayers.dart';

class Siren {
  Siren._();
  static final Siren instance = Siren._();

  final AudioPlayer _player = AudioPlayer();
  bool _configured = false;

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    // Play once through, then stop (don't loop). Change to ReleaseMode.loop if
    // you want it to repeat until manually stopped.
    await _player.setReleaseMode(ReleaseMode.stop);
    await _player.setAudioContext(
      AudioContext(
        android: const AudioContextAndroid(
          isSpeakerphoneOn: true,
          stayAwake: true, // keep the CPU awake so it doesn't cut out
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.alarm, // routes as an ALARM, plays loud
          audioFocus: AndroidAudioFocus.gainTransientMayDuck,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: const {AVAudioSessionOptions.mixWithOthers},
        ),
      ),
    );
    _configured = true;
  }

  bool get isPlaying => _player.state == PlayerState.playing;

  /// Start the siren from the top. Safe to call repeatedly.
  Future<void> play() async {
    await _ensureConfigured();
    await _player.stop();
    await _player.play(AssetSource('alarm.mp3'));
  }

  /// Stop the siren immediately.
  Future<void> stop() => _player.stop();
}
