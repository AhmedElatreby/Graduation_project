// PendingCall persists "the OS blocked the background auto-call"; the app
// consumes it exactly once on next resume and places the call itself.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safetyproject/services/pending_call.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('consume returns true once after set, then false', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await PendingCall.consume(), isFalse);

    await PendingCall.set();
    expect(await PendingCall.consume(), isTrue);
    expect(await PendingCall.consume(), isFalse); // one-shot
  });
}
