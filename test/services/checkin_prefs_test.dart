// CheckInPrefs: no timer by default, start()/clear() persist and survive a
// reload, note is optional and cleared independently of a missing endTime.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:safetyproject/services/checkin_prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('no timer running by default', () async {
    SharedPreferences.setMockInitialValues({});
    await CheckInPrefs.load();
    expect(CheckInPrefs.endTime.value, isNull);
    expect(CheckInPrefs.note.value, isNull);
  });

  test('start persists the end time and survives a reload', () async {
    SharedPreferences.setMockInitialValues({});
    await CheckInPrefs.load();

    await CheckInPrefs.start(const Duration(minutes: 20));
    final started = CheckInPrefs.endTime.value;
    expect(started, isNotNull);

    // Simulate a fresh isolate reading the same store.
    CheckInPrefs.endTime.value = null; // scribble over the in-memory value
    await CheckInPrefs.load();
    expect(CheckInPrefs.endTime.value, started);
  });

  test('start persists an optional note', () async {
    SharedPreferences.setMockInitialValues({});
    await CheckInPrefs.load();

    await CheckInPrefs.start(const Duration(minutes: 10),
        note: 'walking home from the station');
    expect(CheckInPrefs.note.value, 'walking home from the station');

    CheckInPrefs.note.value = null;
    await CheckInPrefs.load();
    expect(CheckInPrefs.note.value, 'walking home from the station');
  });

  test('clear removes both the end time and the note', () async {
    SharedPreferences.setMockInitialValues({});
    await CheckInPrefs.load();
    await CheckInPrefs.start(const Duration(minutes: 10), note: 'test');

    await CheckInPrefs.clear();
    expect(CheckInPrefs.endTime.value, isNull);
    expect(CheckInPrefs.note.value, isNull);

    await CheckInPrefs.load();
    expect(CheckInPrefs.endTime.value, isNull);
    expect(CheckInPrefs.note.value, isNull);
  });

  test('starting again without a note clears any previous note', () async {
    SharedPreferences.setMockInitialValues({});
    await CheckInPrefs.load();
    await CheckInPrefs.start(const Duration(minutes: 10), note: 'first note');

    await CheckInPrefs.start(const Duration(minutes: 5));
    expect(CheckInPrefs.note.value, isNull);

    await CheckInPrefs.load();
    expect(CheckInPrefs.note.value, isNull);
  });

  test('load() sees a write made by another isolate to the same store '
      '(regression: F1 — legacy SharedPreferences caches per-isolate; only '
      'reload() re-hits the platform)', () async {
    SharedPreferences.setMockInitialValues({});
    await CheckInPrefs.load(); // caches this isolate's SharedPreferences
    expect(CheckInPrefs.endTime.value, isNull);

    // Simulate another isolate's write: mutate the backing store directly,
    // *not* via setMockInitialValues (which would reset the SharedPreferences
    // singleton's completer and mask the bug by forcing an unrelated refetch
    // path). A real cross-isolate write on-device doesn't reset our
    // in-process cache either — only reload() does.
    final millis =
        DateTime.now().add(const Duration(minutes: 10)).millisecondsSinceEpoch;
    await SharedPreferencesStorePlatform.instance
        .setValue('Int', 'flutter.checkin_end_time_millis', millis);

    await CheckInPrefs.load();
    expect(CheckInPrefs.endTime.value,
        DateTime.fromMillisecondsSinceEpoch(millis));
  });
}
