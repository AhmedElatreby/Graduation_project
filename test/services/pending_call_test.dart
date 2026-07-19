// PendingCall persists "the OS blocked the background auto-call"; the app
// consumes it exactly once on next resume and places the call itself.
// The flag carries its set-time: a flag older than maxAge is dropped, not
// dialed — a stale flag surviving into a later session must never surprise-
// call a guardian long after the alert it belonged to.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

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

  test('a flag older than maxAge is dropped, not consumed', () async {
    final stale = DateTime.now()
        .subtract(PendingCall.maxAge + const Duration(seconds: 1))
        .millisecondsSinceEpoch;
    SharedPreferences.setMockInitialValues({'pending_guardian_call': stale});

    expect(await PendingCall.consume(), isFalse);
    // And it was cleared, not left behind to be re-checked forever.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('pending_guardian_call'), isFalse);
  });

  test('a flag just inside maxAge is still consumed', () async {
    final recent = DateTime.now()
        .subtract(PendingCall.maxAge - const Duration(minutes: 1))
        .millisecondsSinceEpoch;
    SharedPreferences.setMockInitialValues({'pending_guardian_call': recent});

    expect(await PendingCall.consume(), isTrue);
    expect(await PendingCall.consume(), isFalse);
  });

  test('a legacy bool flag from an old install is dropped safely', () async {
    SharedPreferences.setMockInitialValues({'pending_guardian_call': true});
    expect(await PendingCall.consume(), isFalse);
  });

  test('consume sees a flag set by another isolate to the same store '
      '(regression: legacy SharedPreferences caches per-isolate; only '
      'reload() re-hits the platform)', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await PendingCall.consume(), isFalse); // caches this isolate

    // Simulate the guard-service isolate's write: mutate the backing store
    // directly, *not* via setMockInitialValues (which resets the singleton's
    // completer and would mask the bug by forcing an unrelated refetch).
    await SharedPreferencesStorePlatform.instance.setValue('Int',
        'flutter.pending_guardian_call', DateTime.now().millisecondsSinceEpoch);

    expect(await PendingCall.consume(), isTrue);
  });
}