// ShareLinkPrefs: no active share by default, start() persists and
// survives a reload, isActive is false once expiresAt is in the past.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safetyproject/services/share_link_prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('no active share by default', () async {
    SharedPreferences.setMockInitialValues({});
    await ShareLinkPrefs.load();
    expect(ShareLinkPrefs.shareId.value, isNull);
    expect(ShareLinkPrefs.expiresAt.value, isNull);
    expect(ShareLinkPrefs.isActive, isFalse);
  });

  test('start persists the share and survives a reload', () async {
    SharedPreferences.setMockInitialValues({});
    await ShareLinkPrefs.load();

    final expiry = DateTime.now().add(const Duration(hours: 2));
    await ShareLinkPrefs.start('abc123', expiry);
    expect(ShareLinkPrefs.shareId.value, 'abc123');
    expect(ShareLinkPrefs.isActive, isTrue);

    // Simulate a fresh read of the same store.
    ShareLinkPrefs.shareId.value = null;
    ShareLinkPrefs.expiresAt.value = null;
    await ShareLinkPrefs.load();
    expect(ShareLinkPrefs.shareId.value, 'abc123');
    // Compare with millisecond precision (SharedPreferences truncates microseconds)
    expect(ShareLinkPrefs.expiresAt.value,
        DateTime.fromMillisecondsSinceEpoch(expiry.millisecondsSinceEpoch));
  });

  test('isActive is false once expiresAt is in the past', () async {
    SharedPreferences.setMockInitialValues({});
    await ShareLinkPrefs.load();

    await ShareLinkPrefs.start(
        'old-share', DateTime.now().subtract(const Duration(minutes: 1)));
    expect(ShareLinkPrefs.isActive, isFalse);
  });

  test('a second start() replaces the previous share entirely', () async {
    SharedPreferences.setMockInitialValues({});
    await ShareLinkPrefs.load();
    await ShareLinkPrefs.start(
        'first', DateTime.now().add(const Duration(hours: 2)));

    final secondExpiry = DateTime.now().add(const Duration(hours: 2));
    await ShareLinkPrefs.start('second', secondExpiry);
    expect(ShareLinkPrefs.shareId.value, 'second');
    // Compare with millisecond precision (SharedPreferences truncates microseconds)
    expect(ShareLinkPrefs.expiresAt.value,
        DateTime.fromMillisecondsSinceEpoch(secondExpiry.millisecondsSinceEpoch));
  });
}
