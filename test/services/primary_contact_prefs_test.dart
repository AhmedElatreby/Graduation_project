// PrimaryContactPrefs: no primary by default, set() persists and survives a
// reload, set(null) clears a previously stored id.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safetyproject/services/primary_contact_prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('no primary set by default', () async {
    SharedPreferences.setMockInitialValues({});
    await PrimaryContactPrefs.load();
    expect(PrimaryContactPrefs.id.value, isNull);
  });

  test('set persists the id and survives a reload', () async {
    SharedPreferences.setMockInitialValues({});
    await PrimaryContactPrefs.load();

    await PrimaryContactPrefs.set(42);
    expect(PrimaryContactPrefs.id.value, 42);

    // Simulate a fresh read of the same store.
    PrimaryContactPrefs.id.value = null; // scribble over the in-memory value
    await PrimaryContactPrefs.load();
    expect(PrimaryContactPrefs.id.value, 42);
  });

  test('set(null) clears a previously stored id', () async {
    SharedPreferences.setMockInitialValues({});
    await PrimaryContactPrefs.load();
    await PrimaryContactPrefs.set(42);

    await PrimaryContactPrefs.set(null);
    expect(PrimaryContactPrefs.id.value, isNull);

    await PrimaryContactPrefs.load();
    expect(PrimaryContactPrefs.id.value, isNull);
  });

  test('stored value is honoured on load', () async {
    SharedPreferences.setMockInitialValues({'primary_contact_id': 7});
    await PrimaryContactPrefs.load();
    expect(PrimaryContactPrefs.id.value, 7);
  });
}
