// test/services/silent_sos_channel_test.dart
// The Dart side of the native volume-key bridge: setEnabled invokes the
// right method/argument on the channel, and listen() wires incoming
// native calls to the given callback. The native (Kotlin) half of this
// bridge is verified on-device — see the plan's final task.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safetyproject/services/silent_sos_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.elatreby.safety/silent_sos');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('setEnabled invokes the native method with the bool argument', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return null;
    });

    await SilentSosChannel.setEnabled(true);
    expect(received?.method, 'setEnabled');
    expect(received?.arguments, true);
  });

  test('listen() fires the callback when native calls onVolumeDownPress',
      () async {
    var presses = 0;
    SilentSosChannel.listen(() => presses++);

    final message =
        channel.codec.encodeMethodCall(const MethodCall('onVolumeDownPress'));
    await messenger.handlePlatformMessage(channel.name, message, (_) {});

    expect(presses, 1);
  });
}
