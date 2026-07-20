// lib/services/silent_sos_channel.dart
// ─────────────────────────────────────────────────────────────────────────────
//  Lumi · Silent SOS platform bridge
//  Dart side of the native volume-key interception in MainActivity.kt.
//  setEnabled tells native whether to consume KEYCODE_VOLUME_DOWN and
//  suppress the system volume popup; listen() wires native's
//  onVolumeDownPress calls back to a Dart callback.
//  See docs/superpowers/specs/2026-07-20-silent-sos-trigger-design.md
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/services.dart';

class SilentSosChannel {
  SilentSosChannel._();

  static const _channel = MethodChannel('com.elatreby.safety/silent_sos');

  static Future<void> setEnabled(bool enabled) =>
      _channel.invokeMethod('setEnabled', enabled);

  /// Wires [onPress] to fire on every native-reported consumed press.
  /// Call once at startup; the handler stays registered for the app's
  /// lifetime (there's only ever one listener, matching how ShakeDetector
  /// is a single app-wide instance in NavBarPage).
  static void listen(void Function() onPress) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onVolumeDownPress') onPress();
    });
  }
}
