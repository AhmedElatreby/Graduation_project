# Flutter 3 Dependency Migration Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate all packages from Flutter 2 to Flutter 3.44 compatibility by updating versions, removing discontinued packages, and fixing all deprecated APIs.

**Architecture:** Drop-in package upgrades with targeted API fixes — no structural changes to the app. Each task is isolated to one concern so failures are easy to diagnose.

**Tech Stack:** Flutter 3.44 / Dart 3.12, Firebase (auth/firestore/database), Google Maps, GetX, audioplayers v6, flutter_sms, flutter_polyline_points v2, geolocator v13.

---

## Breaking Changes Summary

| Issue | Files | Change |
|---|---|---|
| SDK constraint blocks Dart 3 | `pubspec.yaml` | `<3.0.0` → `<4.0.0` |
| Discontinued packages | `pubspec.yaml` | Remove `firebase_dynamic_links`, `telephony`, `hypertrack_plugin`, `dcdg` |
| `ElevatedButton(primary:)` removed | `sos.dart`, `location_page.dart`, `googlemap_page.dart` | `primary:` → `backgroundColor:` |
| `AudioCache` removed in audioplayers v2+ | `location_page.dart` | `AudioCache` → `AudioPlayer` + `AssetSource` |
| `telephony` abandoned / incompatible | `sos.dart`, `location_page.dart` | Replace with `flutter_sms` (already a dependency) |
| `flutter_polyline_points` v2 new API | `googlemap_page.dart` | Named params + `PolylineRequest` object |
| `geolocator` v9+ removed `desiredAccuracy` | `googlemap_page.dart` | `desiredAccuracy:` → `locationSettings:` |
| `Color.withOpacity()` deprecated in Flutter 3.27 | `login_page.dart`, `signup_page.dart`, `main_page.dart` | `.withOpacity(x)` → `.withValues(alpha: x)` |

---

## Task 1: Update pubspec.yaml

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Replace the entire `pubspec.yaml` with the updated version**

```yaml
name: safetyproject
description: A new Flutter project.

publish_to: 'none'

version: 1.0.0+1

environment:
  sdk: ">=3.0.0 <4.0.0"

dependencies:
  flutter:
    sdk: flutter

  cupertino_icons: ^1.0.8
  get: ^4.6.6
  avatar_glow: ^3.0.2
  firebase_auth: ^5.0.0
  firebase_core: ^3.0.0
  cloud_firestore: ^5.0.0
  geocoding: ^3.0.0
  geolocator: ^13.0.0
  url_launcher: ^6.3.0
  flutter_sms: ^2.3.5
  location: ^7.0.0
  google_maps_flutter: ^2.9.0
  provider: ^6.1.0
  flutter_polyline_points: ^2.0.0
  http: ^1.2.0
  shake: ^2.2.0
  audioplayers: ^6.0.0
  animated_splash_screen: ^1.3.0
  flutter_phone_direct_caller: ^2.1.1
  sqflite: ^2.3.0
  firebase_database: ^11.0.0
  path_provider: ^2.1.0
  permission_handler: ^11.0.0
  flutter_launcher_icons: ^0.14.0
  share_plus: ^10.0.0
  flutter_native_splash: ^2.4.0
  get_it: ^8.0.0
  characters: ^1.4.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  test: ^1.25.0
  flutter_lints: ^4.0.0

flutter_native_splash:
  color: "#FFFFFF"
  image: assets/splash.png
  android: true
  ios: true

flutter_icons:
  android: true
  ios: true
  image_path: "assets/images/logo.png"

flutter:
  uses-material-design: true

  assets:
    - assets/images/
    - assets/
```

- [ ] **Step 2: Run pub get**

```bash
flutter pub get
```

Expected: Resolves successfully with no "version solving failed" errors. If a specific package fails, run `flutter pub deps` to see the conflict and bump that package to its latest major version.

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore: update all deps to Flutter 3 compatible versions, drop firebase_dynamic_links/telephony/hypertrack_plugin"
```

---

## Task 2: Fix ElevatedButton `primary` → `backgroundColor`

The `primary` parameter of `ElevatedButton.styleFrom()` was renamed to `backgroundColor` in Flutter 3.3 and removed in 3.x. Affects 5 button usages across 3 files.

**Files:**
- Modify: `lib/pages/sos.dart`
- Modify: `lib/pages/location_page.dart`
- Modify: `lib/location/googlemap_page.dart`

- [ ] **Step 1: Fix `lib/pages/sos.dart` — SOS red button (line ~123)**

Old:
```dart
style: ElevatedButton.styleFrom(
    fixedSize: const Size(150, 150),
    shape: const CircleBorder(),
    primary: Colors.red),
```

New:
```dart
style: ElevatedButton.styleFrom(
    fixedSize: const Size(150, 150),
    shape: const CircleBorder(),
    backgroundColor: Colors.red),
```

- [ ] **Step 2: Fix `lib/pages/sos.dart` — SMS cyan button (line ~149)**

Old:
```dart
style: ElevatedButton.styleFrom(
    fixedSize: const Size(150, 150),
    shape: const CircleBorder(),
    primary: Colors.cyan),
```

New:
```dart
style: ElevatedButton.styleFrom(
    fixedSize: const Size(150, 150),
    shape: const CircleBorder(),
    backgroundColor: Colors.cyan),
```

- [ ] **Step 3: Fix `lib/pages/location_page.dart` — Alarm yellow button (line ~66)**

Old:
```dart
style: ElevatedButton.styleFrom(
    fixedSize: const Size(80, 80),
    shape: const CircleBorder(),
    primary: Colors.yellow),
```

New:
```dart
style: ElevatedButton.styleFrom(
    fixedSize: const Size(80, 80),
    shape: const CircleBorder(),
    backgroundColor: Colors.yellow),
```

- [ ] **Step 4: Fix `lib/pages/location_page.dart` — Long-press cyan button (line ~114)**

Old:
```dart
style: ElevatedButton.styleFrom(
    fixedSize: const Size(150, 150),
    shape: const CircleBorder(),
    primary: Colors.cyan),
```

New:
```dart
style: ElevatedButton.styleFrom(
    fixedSize: const Size(150, 150),
    shape: const CircleBorder(),
    backgroundColor: Colors.cyan),
```

- [ ] **Step 5: Fix `lib/location/googlemap_page.dart` — Show Route red button (line ~494)**

Old:
```dart
style: ElevatedButton.styleFrom(
  primary: Colors.red,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(20.0),
  ),
),
```

New:
```dart
style: ElevatedButton.styleFrom(
  backgroundColor: Colors.red,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(20.0),
  ),
),
```

- [ ] **Step 6: Verify no `primary:` remains in ElevatedButton usages**

```bash
grep -n "primary:" lib/pages/sos.dart lib/pages/location_page.dart lib/location/googlemap_page.dart
```

Expected: no output (zero matches).

- [ ] **Step 7: Commit**

```bash
git add lib/pages/sos.dart lib/pages/location_page.dart lib/location/googlemap_page.dart
git commit -m "fix: replace deprecated ElevatedButton primary: with backgroundColor:"
```

---

## Task 3: Fix `AudioCache` → `AudioPlayer` in `location_page.dart`

`AudioCache` was removed in `audioplayers` v2. The new API uses `AudioPlayer` directly with `AssetSource`.

**Files:**
- Modify: `lib/pages/location_page.dart`

- [ ] **Step 1: Replace the import (no change needed — `audioplayers` import covers both)**

The existing import `import 'package:audioplayers/audioplayers.dart';` already exports `AudioPlayer` and `AssetSource`. No import change needed.

- [ ] **Step 2: Replace the field declaration (line ~21)**

Old:
```dart
final audioPlayer = AudioCache();
```

New:
```dart
final audioPlayer = AudioPlayer();
```

- [ ] **Step 3: Replace the alarm button's play call (line ~66–68)**

Old:
```dart
onPressed: () {
  AudioCache player = AudioCache(prefix: 'assets/');
  player.play('alarm.mp3');
  ScaffoldMessenger.of(context).showSnackBar(
```

New:
```dart
onPressed: () async {
  await audioPlayer.play(AssetSource('alarm.mp3'));
  ScaffoldMessenger.of(context).showSnackBar(
```

- [ ] **Step 4: Add dispose for the player in the State class**

After `_stopListening()` method, add:

```dart
@override
void dispose() {
  audioPlayer.dispose();
  super.dispose();
}
```

- [ ] **Step 5: Verify no `AudioCache` references remain**

```bash
grep -rn "AudioCache" lib/
```

Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add lib/pages/location_page.dart
git commit -m "fix: replace removed AudioCache with AudioPlayer from audioplayers v6"
```

---

## Task 4: Replace `telephony` with `flutter_sms`

`telephony: ^0.1.4` is abandoned and incompatible with Flutter 3. `flutter_sms` is already declared as a dependency and provides equivalent send-SMS functionality. `sendDirect: true` sends silently on Android without opening the SMS compose UI.

**Files:**
- Modify: `lib/pages/sos.dart`
- Modify: `lib/pages/location_page.dart`

- [ ] **Step 1: Update `lib/pages/sos.dart` — remove telephony import (line 6)**

Remove:
```dart
import 'package:telephony/telephony.dart';
```

Add in its place:
```dart
import 'package:flutter_sms/flutter_sms.dart';
```

- [ ] **Step 2: Replace `_sendSingleText` at the bottom of `lib/pages/sos.dart` (lines ~258–263)**

Old:
```dart
void _sendSingleText(String number, String message) async {
  final Telephony telephony = Telephony.instance;
  bool? permissionsGranted = await telephony.requestPhoneAndSmsPermissions;

  telephony.sendSms(to: number, message: message);
}
```

New:
```dart
void _sendSingleText(String number, String message) async {
  await sendSMS(message: message, recipients: [number], sendDirect: true);
}
```

- [ ] **Step 3: Update `lib/pages/location_page.dart` — remove telephony import (line 9)**

Remove:
```dart
import 'package:telephony/telephony.dart';
```

Add in its place:
```dart
import 'package:flutter_sms/flutter_sms.dart';
```

- [ ] **Step 4: Replace `_sendSingleText` at the bottom of `lib/pages/location_page.dart` (lines ~378–382)**

Old:
```dart
void _sendSingleText(String number, String message) async {
  final Telephony telephony = Telephony.instance;
  bool? permissionsGranted = await telephony.requestPhoneAndSmsPermissions;

  telephony.sendSms(to: number, message: message);
}
```

New:
```dart
void _sendSingleText(String number, String message) async {
  await sendSMS(message: message, recipients: [number], sendDirect: true);
}
```

- [ ] **Step 5: Verify no telephony references remain**

```bash
grep -rn "telephony\|Telephony" lib/
```

Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add lib/pages/sos.dart lib/pages/location_page.dart
git commit -m "fix: replace abandoned telephony package with flutter_sms"
```

---

## Task 5: Fix `flutter_polyline_points` v2 API in `googlemap_page.dart`

In v2.0, `getRouteBetweenCoordinates` replaced positional args with named params and a `PolylineRequest` object.

**Files:**
- Modify: `lib/location/googlemap_page.dart`

- [ ] **Step 1: Replace the `_createPolylines` method call (around line 275–280)**

Old:
```dart
PolylineResult result = await polylinePoints.getRouteBetweenCoordinates(
  Secrets.API_KEY,
  PointLatLng(startLatitude, startLongitude),
  PointLatLng(destinationLatitude, destinationLongitude),
  travelMode: TravelMode.transit,
);
```

New:
```dart
PolylineResult result = await polylinePoints.getRouteBetweenCoordinates(
  googleApiKey: Secrets.API_KEY,
  request: PolylineRequest(
    origin: PointLatLng(startLatitude, startLongitude),
    destination: PointLatLng(destinationLatitude, destinationLongitude),
    mode: TravelMode.transit,
  ),
);
```

- [ ] **Step 2: Verify the change compiles**

```bash
flutter analyze lib/location/googlemap_page.dart
```

Expected: no errors on this file (warnings about other things may appear but no errors).

- [ ] **Step 3: Commit**

```bash
git add lib/location/googlemap_page.dart
git commit -m "fix: update flutter_polyline_points to v2 PolylineRequest API"
```

---

## Task 6: Fix `geolocator` v9+ API in `googlemap_page.dart`

`desiredAccuracy` parameter was removed in geolocator v9. Use `locationSettings` instead.

**Files:**
- Modify: `lib/location/googlemap_page.dart`

- [ ] **Step 1: Replace `getCurrentPosition` call in `_getCurrentLocation()` (line ~95)**

Old:
```dart
await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high)
```

New:
```dart
await Geolocator.getCurrentPosition(
  locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
)
```

- [ ] **Step 2: Verify**

```bash
flutter analyze lib/location/googlemap_page.dart
```

Expected: zero errors on the geolocator call.

- [ ] **Step 3: Commit**

```bash
git add lib/location/googlemap_page.dart
git commit -m "fix: update geolocator getCurrentPosition to locationSettings API (v9+)"
```

---

## Task 7: Fix `Color.withOpacity()` deprecation

`withOpacity()` was deprecated in Flutter 3.27 in favor of `withValues(alpha:)`. Affects 3 files.

**Files:**
- Modify: `lib/pages/login_page.dart`
- Modify: `lib/pages/signup_page.dart`
- Modify: `lib/navigation_bar/main_page.dart`

- [ ] **Step 1: Fix `lib/pages/login_page.dart` — two occurrences (lines ~77 and ~109)**

Replace:
```dart
color: Colors.grey.withOpacity(0.2)
```
With:
```dart
color: Colors.grey.withValues(alpha: 0.2)
```

Replace:
```dart
color: Colors.grey.withOpacity(0.2)
```
With:
```dart
color: Colors.grey.withValues(alpha: 0.2)
```

- [ ] **Step 2: Fix `lib/pages/signup_page.dart` — two occurrences (lines ~78 and ~110)**

Replace:
```dart
color: Colors.grey.withOpacity(0.2)
```
With:
```dart
color: Colors.grey.withValues(alpha: 0.2)
```

Replace:
```dart
color: Colors.grey.withOpacity(0.1)
```
With:
```dart
color: Colors.grey.withValues(alpha: 0.1)
```

- [ ] **Step 3: Fix `lib/navigation_bar/main_page.dart` — one occurrence (line ~46)**

Replace:
```dart
unselectedItemColor: Colors.grey.withOpacity(0.7),
```
With:
```dart
unselectedItemColor: Colors.grey.withValues(alpha: 0.7),
```

- [ ] **Step 4: Verify no withOpacity remains**

```bash
grep -rn "withOpacity" lib/
```

Expected: no output.

- [ ] **Step 5: Commit**

```bash
git add lib/pages/login_page.dart lib/pages/signup_page.dart lib/navigation_bar/main_page.dart
git commit -m "fix: replace deprecated withOpacity() with withValues(alpha:)"
```

---

## Task 8: Final analysis pass and cleanup

Run a full analysis, fix any remaining issues, and confirm the project is clean.

**Files:** Any files flagged by analysis

- [ ] **Step 1: Run full analysis**

```bash
flutter analyze
```

Note any errors (not warnings). Common remaining errors after this migration:
- Missing `firebase_options.dart` — Firebase projects migrated to FlutterFire CLI need `options: DefaultFirebaseOptions.currentPlatform` in `Firebase.initializeApp()`. If this error appears, it means the Google services files are missing; this is an environment setup issue, not a code issue — skip for now and note it.
- `const` constructor issues — fix inline.
- Unused imports from removed packages — delete those import lines.

- [ ] **Step 2: Fix any import leftovers from removed packages**

```bash
grep -rn "firebase_dynamic_links\|telephony\|hypertrack_plugin\|dcdg" lib/
```

Expected: no output. If any remain, delete those import lines.

- [ ] **Step 3: Attempt a debug build (optional but recommended)**

```bash
flutter build apk --debug 2>&1 | tail -30
```

Expected: `Built build/app/outputs/flutter-apk/app-debug.apk` or a list of Kotlin/Gradle errors (those are environment issues, not code issues).

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "chore: clean up remaining analysis warnings after Flutter 3 migration"
```

---

## Notes

- **Firebase initialization**: If you get `No Firebase App '[DEFAULT]' has been created`, run `flutterfire configure` to regenerate `firebase_options.dart` and update `main.dart` to pass `options: DefaultFirebaseOptions.currentPlatform`.
- **flutter_sms `sendDirect`**: On iOS, silent background SMS is not possible; the SMS compose sheet will open. This is an OS restriction, not a package limitation.
- **Google Maps API key**: Still in `lib/secrets.dart`. Consider moving it to `android/app/src/main/AndroidManifest.xml` as a manifest meta-data entry and to the iOS `AppDelegate`.
