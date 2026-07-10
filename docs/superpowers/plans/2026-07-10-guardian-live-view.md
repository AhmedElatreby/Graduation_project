# Guardian Live-View Share Link Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When an alert fires, include a short-lived link in the SMS that
opens a hosted web page showing the user's live-updating location, so a
guardian without the app can actually watch them move.

**Architecture:** A new Firestore collection (`shared_locations`), keyed by
an unguessable random token instead of the user's uid, holds just enough to
render one live map — separate from and never touching the existing
private `location/{uid}` document. A new `LiveLocationService` extracts
Live Location's streaming logic out of `LocationPage`'s widget state into a
plain static service, so `EmergencyAlert.send()` can turn it on when a
foreground alert fires. A small hand-written HTML/JS page, deployed via
Firebase Hosting, is the guardian-facing viewer.

**Tech Stack:** Flutter/Dart, Cloud Firestore, Firebase Hosting, plain
HTML/JS (Firebase JS SDK + Google Maps JavaScript API) for the guest page,
`fake_cloud_firestore`/`firebase_auth_mocks` (new dev dependencies) for
testing Firestore-touching code, Node's built-in test runner +
`@firebase/rules-unit-testing` for security-rule tests.

## Global Constraints

- Share links are valid for **2 hours** from creation, enforced by the
  Firestore rule itself (`expiresAt > request.time`), not a scheduled job.
- The existing `location/{uid}` rule and document are **never modified**.
- The alert SMS's existing static Google Maps pin is **kept**, not
  replaced — the share link is added as an extra line.
- `EmergencyAlert.buildAlertMessage`'s new `shareLink` parameter must leave
  the message byte-for-byte unchanged when omitted (existing behavior for
  every current call site).
- Live Location auto-enables only for a **foreground** alert (the SOS
  button, or a shake detected while the app is open) — never attempt to
  reach a background/killed-app shake alert; that keeps getting only the
  one-shot position it already gets today.
- `LocationPage`'s existing Live Location toggle must look and behave
  identically to today after the `LiveLocationService` extraction — this
  is a behavior-preserving refactor of already-working code, not a
  redesign.

---

### Task 1: Firestore rules for `shared_locations`

**Files:**
- Modify: `firestore.rules`
- Modify: `firebase.json` (adds an `emulators` block)
- Create: `firestore-tests/package.json`
- Create: `firestore-tests/rules.test.js`

**Interfaces:**
- Produces: the `shared_locations/{shareId}` collection's access rules —
  every later task that reads/writes this collection relies on exactly
  this shape: `ownerUid`, `latitude`, `longitude`, `updatedAt`, `expiresAt`
  fields; public read while unexpired; write only from the matching
  authenticated owner.

- [ ] **Step 1: Add the emulator config**

In `firebase.json`, add a top-level `emulators` key (alongside the
existing `flutter` and `firestore` keys):

```json
  "emulators": {
    "firestore": {
      "port": 8080
    },
    "ui": {
      "enabled": false
    }
  }
```

- [ ] **Step 2: Write the failing rules test**

Create `firestore-tests/package.json`:

```json
{
  "name": "firestore-rules-tests",
  "private": true,
  "type": "commonjs",
  "scripts": {
    "test": "firebase emulators:exec --project=demo-lumi-rules-test --only firestore \"node --test rules.test.js\""
  },
  "devDependencies": {
    "@firebase/rules-unit-testing": "^3.0.4"
  }
}
```

Create `firestore-tests/rules.test.js`:

```js
// Verifies firestore.rules for the shared_locations collection: a guest
// (no auth) can read an unexpired share, cannot read an expired one, and
// only the matching authenticated owner can write it. Run with `npm test`
// from this directory (spins up the Firestore emulator via firebase-tools,
// already a project dependency of the wider app's tooling).
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');

let testEnv;

test.before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-lumi-rules-test',
    firestore: {
      rules: fs.readFileSync(path.resolve(__dirname, '../firestore.rules'), 'utf8'),
      host: 'localhost',
      port: 8080,
    },
  });
});

test.after(async () => {
  await testEnv.cleanup();
});

test.beforeEach(async () => {
  await testEnv.clearFirestore();
});

test('an unauthenticated guest can read a non-expired share', async () => {
  const owner = testEnv.authenticatedContext('owner-uid');
  await owner.firestore().collection('shared_locations').doc('share1').set({
    ownerUid: 'owner-uid',
    name: 'Ahmed',
    latitude: 1.23,
    longitude: 4.56,
    expiresAt: new Date(Date.now() + 60 * 60 * 1000),
  });

  const guest = testEnv.unauthenticatedContext();
  await assertSucceeds(
    guest.firestore().collection('shared_locations').doc('share1').get()
  );
});

test('an unauthenticated guest cannot read an expired share', async () => {
  const owner = testEnv.authenticatedContext('owner-uid');
  await owner.firestore().collection('shared_locations').doc('share2').set({
    ownerUid: 'owner-uid',
    name: 'Ahmed',
    latitude: 1.23,
    longitude: 4.56,
    expiresAt: new Date(Date.now() - 60 * 1000), // 1 minute ago
  });

  const guest = testEnv.unauthenticatedContext();
  await assertFails(
    guest.firestore().collection('shared_locations').doc('share2').get()
  );
});

test('only the matching authenticated owner can create a share doc', async () => {
  const notOwner = testEnv.authenticatedContext('someone-else');
  await assertFails(
    notOwner.firestore().collection('shared_locations').doc('share3').set({
      ownerUid: 'owner-uid', // doesn't match the authenticated uid
      name: 'Ahmed',
      latitude: 1.23,
      longitude: 4.56,
      expiresAt: new Date(Date.now() + 60 * 60 * 1000),
    })
  );

  const owner = testEnv.authenticatedContext('owner-uid');
  await assertSucceeds(
    owner.firestore().collection('shared_locations').doc('share4').set({
      ownerUid: 'owner-uid',
      name: 'Ahmed',
      latitude: 1.23,
      longitude: 4.56,
      expiresAt: new Date(Date.now() + 60 * 60 * 1000),
    })
  );
});

test('the existing location/{uid} rule is untouched: owner can read their own, a stranger cannot', async () => {
  const owner = testEnv.authenticatedContext('owner-uid');
  await owner.firestore().collection('location').doc('owner-uid').set({
    latitude: 1.23,
    longitude: 4.56,
  });

  await assertSucceeds(
    owner.firestore().collection('location').doc('owner-uid').get()
  );

  const stranger = testEnv.authenticatedContext('someone-else');
  await assertFails(
    stranger.firestore().collection('location').doc('owner-uid').get()
  );
});
```

- [ ] **Step 3: Run the tests to verify they fail**

```bash
cd firestore-tests
npm install
npm test
```

Expected: FAIL — `firestore.rules` has no `shared_locations` match block
yet, so the create/read assertions against it fail (default-deny rule at
the bottom of `firestore.rules` denies everything not explicitly matched).

- [ ] **Step 4: Add the `shared_locations` rules**

In `firestore.rules`, add this new `match` block directly after the
existing `location/{userId}` block, before the final default-deny block:

```
    match /shared_locations/{shareId} {
      // Anyone with the exact shareId can read it, but only while it
      // hasn't expired — no auth required, since guardians have no
      // account. A stray expired doc is harmless to leave forever.
      allow read: if resource.data.expiresAt > request.time;

      // Only the authenticated owner can create or update their own
      // share doc. Nothing ever deletes a share; it just expires.
      allow create: if request.auth != null
          && request.auth.uid == request.resource.data.ownerUid;
      allow update: if request.auth != null
          && request.auth.uid == resource.data.ownerUid;
      allow delete: if false;
    }
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
cd firestore-tests
npm test
```

Expected: PASS (4/4).

- [ ] **Step 6: Commit**

```bash
git add firestore.rules firebase.json firestore-tests/
git commit -m "feat: add Firestore rules for shared_locations guardian view"
```

---

### Task 2: `ShareLinkPrefs` — persisted active share

**Files:**
- Create: `lib/services/share_link_prefs.dart`
- Test: `test/services/share_link_prefs_test.dart`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: `ShareLinkPrefs.shareId` (`ValueNotifier<String?>`),
  `ShareLinkPrefs.expiresAt` (`ValueNotifier<DateTime?>`),
  `ShareLinkPrefs.isActive` (`bool` getter),
  `ShareLinkPrefs.start(String shareId, DateTime expiresAt)`
  (`Future<void>`), `ShareLinkPrefs.load()` (`Future<void>`). Task 3's
  `GuardianShare.createShareLink` calls `start`; Task 5's
  `LiveLocationService` reads `isActive`/`shareId`.

- [ ] **Step 1: Write the failing tests**

Create `test/services/share_link_prefs_test.dart`:

```dart
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
    expect(ShareLinkPrefs.expiresAt.value, expiry);
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
    expect(ShareLinkPrefs.expiresAt.value, secondExpiry);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/services/share_link_prefs_test.dart`
Expected: FAIL — `share_link_prefs.dart` doesn't exist yet.

- [ ] **Step 3: Implement `ShareLinkPrefs`**

Create `lib/services/share_link_prefs.dart`:

```dart
// ─────────────────────────────────────────────────────────────────────────────
//  Lumi · Active guardian share link
//  Which shared_locations document (if any) the Live Location stream
//  should also mirror fresh GPS fixes into. A missing shareId or an
//  expiresAt in the past both mean "nothing to mirror into" — isActive is
//  the single source of truth callers check, not two separate booleans
//  that could drift out of sync.
//  See docs/superpowers/specs/2026-07-10-guardian-live-view-design.md
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ShareLinkPrefs {
  ShareLinkPrefs._();

  static const _shareIdKey = 'guardian_share_id';
  static const _expiresAtKey = 'guardian_share_expires_at_millis';

  static final ValueNotifier<String?> shareId = ValueNotifier(null);
  static final ValueNotifier<DateTime?> expiresAt = ValueNotifier(null);

  static bool get isActive =>
      shareId.value != null &&
      expiresAt.value != null &&
      DateTime.now().isBefore(expiresAt.value!);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    shareId.value = prefs.getString(_shareIdKey);
    final millis = prefs.getInt(_expiresAtKey);
    expiresAt.value =
        millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  /// Always replaces any previous share — there is only ever one active
  /// share tracked at a time (see the design doc's documented trade-off).
  static Future<void> start(String shareId, DateTime expiresAt) async {
    ShareLinkPrefs.shareId.value = shareId;
    ShareLinkPrefs.expiresAt.value = expiresAt;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_shareIdKey, shareId);
    await prefs.setInt(_expiresAtKey, expiresAt.millisecondsSinceEpoch);
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/services/share_link_prefs_test.dart`
Expected: PASS (4/4)

- [ ] **Step 5: Commit**

```bash
git add lib/services/share_link_prefs.dart test/services/share_link_prefs_test.dart
git commit -m "feat: add ShareLinkPrefs for the active guardian share"
```

---

### Task 3: `GuardianShare.createShareLink`

**Files:**
- Modify: `pubspec.yaml` (adds `fake_cloud_firestore` and
  `firebase_auth_mocks` dev dependencies)
- Create: `lib/services/guardian_share.dart`
- Test: `test/services/guardian_share_test.dart`

**Interfaces:**
- Consumes: `ShareLinkPrefs.start` (Task 2).
- Produces: `GuardianShare.createShareLink({required String? coords,
  FirebaseFirestore? firestore, FirebaseAuth? auth})` → `Future<String?>`
  (the full shareable URL, or `null` if it couldn't be created). Task 4's
  `EmergencyAlert.send`/`sendBackground` call exactly this.

This is the first test in this codebase to touch `FirebaseFirestore`/
`FirebaseAuth` directly — no prior test does, so this task adds the
standard fake packages for it (`fake_cloud_firestore`,
`firebase_auth_mocks`), matching the existing codebase convention of
optional constructor parameters for test seams (e.g.
`callFirstContact({List<PersonalEmergency>? contacts})` already does this).

- [ ] **Step 1: Add the test dependencies**

In `pubspec.yaml`, under `dev_dependencies:`, add (after the existing
`fake_async: ^1.3.1` line):

```yaml
  fake_cloud_firestore: ^3.1.0
  firebase_auth_mocks: ^0.14.1
```

Run: `flutter pub get`
Expected: resolves cleanly.

- [ ] **Step 2: Write the failing tests**

Create `test/services/guardian_share_test.dart`:

```dart
// GuardianShare.createShareLink: no link without a signed-in user or
// coords; on success, writes the expected shared_locations fields and
// returns a URL containing the same shareId, and persists it via
// ShareLinkPrefs.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safetyproject/services/guardian_share.dart';
import 'package:safetyproject/services/share_link_prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('returns null when nobody is signed in', () async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(signedIn: false);

    final link = await GuardianShare.createShareLink(
      coords: '50.73,-1.85',
      firestore: firestore,
      auth: auth,
    );

    expect(link, isNull);
  });

  test('returns null when coords is null', () async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'user-1', email: 'a@a.com'),
    );

    final link = await GuardianShare.createShareLink(
      coords: null,
      firestore: firestore,
      auth: auth,
    );

    expect(link, isNull);
  });

  test('on success, writes the expected fields and returns a matching URL',
      () async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'user-1', email: 'ahmed@example.com'),
    );

    final link = await GuardianShare.createShareLink(
      coords: '50.73,-1.85',
      firestore: firestore,
      auth: auth,
    );

    expect(link, isNotNull);
    final uri = Uri.parse(link!);
    final shareId = uri.queryParameters['id'];
    expect(shareId, isNotNull);
    expect(shareId, isNotEmpty);

    final doc =
        await firestore.collection('shared_locations').doc(shareId).get();
    expect(doc.exists, isTrue);
    final data = doc.data()!;
    expect(data['ownerUid'], 'user-1');
    expect(data['name'], 'Ahmed'); // derived from the email's local part
    expect(data['latitude'], 50.73);
    expect(data['longitude'], -1.85);
    expect(data['expiresAt'], isA<Timestamp>());
    final expiresAt = (data['expiresAt'] as Timestamp).toDate();
    final expectedExpiry = DateTime.now().add(const Duration(hours: 2));
    expect(expiresAt.difference(expectedExpiry).inMinutes.abs() < 1, isTrue);

    expect(ShareLinkPrefs.shareId.value, shareId);
    expect(ShareLinkPrefs.isActive, isTrue);
  });

  test('a second call always mints a new, independent shareId', () async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'user-1', email: 'a@a.com'),
    );

    final firstLink = await GuardianShare.createShareLink(
        coords: '50.73,-1.85', firestore: firestore, auth: auth);
    final secondLink = await GuardianShare.createShareLink(
        coords: '50.74,-1.86', firestore: firestore, auth: auth);

    final firstId = Uri.parse(firstLink!).queryParameters['id'];
    final secondId = Uri.parse(secondLink!).queryParameters['id'];
    expect(firstId, isNot(secondId));

    // The first share's doc still exists, untouched, alongside the second.
    final firstDoc =
        await firestore.collection('shared_locations').doc(firstId).get();
    expect(firstDoc.exists, isTrue);
    expect(firstDoc.data()!['latitude'], 50.73);
  });
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `flutter test test/services/guardian_share_test.dart`
Expected: FAIL — `guardian_share.dart` doesn't exist yet.

- [ ] **Step 4: Implement `GuardianShare`**

Create `lib/services/guardian_share.dart`:

```dart
// ─────────────────────────────────────────────────────────────────────────────
//  Lumi · Guardian live-view share links
//  Creates a short-lived, unguessable share for the guardian-facing web
//  page (public/share.html) to read. Deliberately a separate Firestore
//  collection from location/{uid} — that document's owner-only rule is
//  never touched or weakened to accommodate guests.
//  See docs/superpowers/specs/2026-07-10-guardian-live-view-design.md
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'share_link_prefs.dart';

class GuardianShare {
  GuardianShare._();

  static const _validity = Duration(hours: 2);
  static const _collection = 'shared_locations';
  static const _baseUrl = 'https://safety-project-71d83.web.app/share.html';

  /// Creates a fresh, independent share for the current position. Returns
  /// null (no link, alert message unchanged) if nobody is signed in or
  /// [coords] is unavailable — a share link is a bonus on top of an
  /// already-working alert, never a precondition for sending it. Always
  /// mints a brand-new shareId; an earlier still-valid share from a prior
  /// alert is left running, untouched.
  static Future<String?> createShareLink({
    required String? coords,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  }) async {
    final user = (auth ?? FirebaseAuth.instance).currentUser;
    if (user == null || coords == null) return null;

    final parts = coords.split(',');
    if (parts.length != 2) return null;
    final lat = double.tryParse(parts[0]);
    final lng = double.tryParse(parts[1]);
    if (lat == null || lng == null) return null;

    final db = firestore ?? FirebaseFirestore.instance;
    final shareId = _generateToken();
    final expiresAt = DateTime.now().add(_validity);

    await db.collection(_collection).doc(shareId).set({
      'ownerUid': user.uid,
      'name': _firstName(user.email),
      'latitude': lat,
      'longitude': lng,
      'updatedAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(expiresAt),
    });

    await ShareLinkPrefs.start(shareId, expiresAt);
    return '$_baseUrl?id=$shareId';
  }

  /// Same derivation SosPage already uses for its "Good evening, X"
  /// greeting, reused here so the guardian sees a matching first name.
  static String _firstName(String? email) {
    if (email == null || email.isEmpty) return 'Someone';
    final base = email.contains('@') ? email.split('@').first : email;
    if (base.isEmpty) return 'Someone';
    return base[0].toUpperCase() + base.substring(1);
  }

  static String _generateToken() {
    final bytes = List<int>.generate(24, (_) => Random.secure().nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/services/guardian_share_test.dart`
Expected: PASS (4/4)

- [ ] **Step 6: Run the full test suite**

Run: `flutter test`
Expected: all tests PASS.

- [ ] **Step 7: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/services/guardian_share.dart test/services/guardian_share_test.dart
git commit -m "feat: add GuardianShare.createShareLink"
```

---

### Task 4: Wire the share link into `EmergencyAlert`

**Files:**
- Modify: `lib/services/emergency_alert.dart`
- Test: `test/services/emergency_alert_test.dart`

**Interfaces:**
- Consumes: `GuardianShare.createShareLink` (Task 3).
- Produces: `EmergencyAlert.buildAlertMessage(String? coords, {String?
  shareLink})` — no other call site's signature changes.

- [ ] **Step 1: Write the failing tests**

In `test/services/emergency_alert_test.dart`, add this import:

```dart
import 'package:safetyproject/services/guardian_share.dart';
```

Add these tests inside `main()`, after the existing `buildAlertMessage`
test:

```dart
  test('buildAlertMessage appends the share link on its own line when '
      'provided', () {
    expect(
      EmergencyAlert.buildAlertMessage('50.73,-1.85',
          shareLink: 'https://safety-project-71d83.web.app/share.html?id=abc'),
      'I need help, please find me: https://maps.google.com/?q=50.73,-1.85\n'
      'Live location: https://safety-project-71d83.web.app/share.html?id=abc',
    );
    // No share link: byte-for-byte identical to today's message.
    expect(
      EmergencyAlert.buildAlertMessage('50.73,-1.85'),
      'I need help, please find me: https://maps.google.com/?q=50.73,-1.85',
    );
  });

  test('sendBackground includes a share link in the SMS when one can be '
      'created', () async {
    // sendBackground itself hits telephony/geolocator plugins with no
    // mocked platform channel in this suite (see the existing
    // "sendTexts refuses to run..." test's own comment on this) — this
    // test targets buildAlertMessage + GuardianShare.createShareLink
    // directly instead, the same seam-testing approach Task 2 of the
    // primary-guardian-contact plan used for resolveCallTarget.
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'user-1', email: 'a@a.com'),
    );

    final link = await GuardianShare.createShareLink(
      coords: '50.73,-1.85',
      firestore: firestore,
      auth: auth,
    );

    expect(
      EmergencyAlert.buildAlertMessage('50.73,-1.85', shareLink: link),
      'I need help, please find me: https://maps.google.com/?q=50.73,-1.85\n'
      'Live location: $link',
    );
  });
```

Add these imports to the top of the same test file (needed by the second
new test above):

```dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/services/emergency_alert_test.dart`
Expected: FAIL — `buildAlertMessage` doesn't accept a `shareLink` named
argument yet (compile error).

- [ ] **Step 3: Implement the `shareLink` parameter and wire it into both send paths**

In `lib/services/emergency_alert.dart`, add the import:

```dart
import 'guardian_share.dart';
```

Replace `buildAlertMessage`:

```dart
  /// The SMS body. Extracted so the foreground composer path and the
  /// background silent path can never drift apart.
  static String buildAlertMessage(String? coords) => coords == null
      ? 'I need help! (My location is unavailable right now.)'
      : 'I need help, please find me: https://maps.google.com/?q=$coords';
```

with:

```dart
  /// The SMS body. Extracted so the foreground composer path and the
  /// background silent path can never drift apart. [shareLink] (a
  /// GuardianShare URL) is appended on its own line when present, leaving
  /// the message byte-for-byte unchanged when it's null — every existing
  /// call site that doesn't pass one sees no change.
  static String buildAlertMessage(String? coords, {String? shareLink}) {
    final base = coords == null
        ? 'I need help! (My location is unavailable right now.)'
        : 'I need help, please find me: https://maps.google.com/?q=$coords';
    return shareLink == null ? base : '$base\nLive location: $shareLink';
  }
```

Update `sendTexts` to create and include a share link. Replace:

```dart
  /// Texts every guardian the location link. Throws on failure.
  static Future<void> sendTexts({List<PersonalEmergency>? contacts}) async {
    await _requireGranted(Permission.sms, 'SMS');
    final list = contacts ?? await DBHelper().getContacts();
    final coords = await currentCoordinates();
    final message = buildAlertMessage(coords);
    final recipients = list.map((c) => c.contactNo).toList();
```

with:

```dart
  /// Texts every guardian the location link. Throws on failure.
  static Future<void> sendTexts({List<PersonalEmergency>? contacts}) async {
    await _requireGranted(Permission.sms, 'SMS');
    final list = contacts ?? await DBHelper().getContacts();
    final coords = await currentCoordinates();
    final shareLink = await GuardianShare.createShareLink(coords: coords);
    final message = buildAlertMessage(coords, shareLink: shareLink);
    final recipients = list.map((c) => c.contactNo).toList();
```

Update `sendBackground` the same way. Replace:

```dart
    String? coords;
    try {
      coords = await (coordsFuture ?? currentCoordinates())
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      coords = null; // background GPS may be denied/slow — degrade, don't die
    }
    final message = buildAlertMessage(coords);
```

with:

```dart
    String? coords;
    try {
      coords = await (coordsFuture ?? currentCoordinates())
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      coords = null; // background GPS may be denied/slow — degrade, don't die
    }
    String? shareLink;
    try {
      shareLink = await GuardianShare.createShareLink(coords: coords);
    } catch (_) {
      shareLink = null; // a share-link failure must never block the alert
    }
    final message = buildAlertMessage(coords, shareLink: shareLink);
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/services/emergency_alert_test.dart`
Expected: PASS (9/9)

- [ ] **Step 5: Run the full test suite**

Run: `flutter test`
Expected: all tests PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/services/emergency_alert.dart test/services/emergency_alert_test.dart
git commit -m "feat: include a guardian live-view link in the alert SMS"
```

---

### Task 5: `LiveLocationService` extraction

**Files:**
- Create: `lib/services/live_location_service.dart`
- Modify: `lib/pages/location_page.dart`
- Modify: `lib/navigation_bar/main_page.dart` (stop it on logout)

**Interfaces:**
- Consumes: `ShareLinkPrefs.isActive/shareId` (Task 2).
- Produces: `LiveLocationService.isLive` (`ValueNotifier<bool>`),
  `LiveLocationService.start()` (`Future<void>`), `LiveLocationService.stop()`
  (`void`). Task 6's `EmergencyAlert.send()` calls `start()`.

This is a **behavior-preserving refactor** — `LocationPage`'s Live
Location toggle, its "Sharing now"/"Off" label, and its Firestore write to
`location/{uid}` must work identically to today after this task. No new
test file is required by this task (the write behavior itself is already
untested today — same category as the rest of `location_page.dart`); the
existing widget test suite passing unchanged is the regression check.

- [ ] **Step 1: Implement `LiveLocationService`**

Create `lib/services/live_location_service.dart`:

```dart
// ─────────────────────────────────────────────────────────────────────────────
//  Lumi · Live location streaming
//  Extracted out of LocationPage's widget state so a plain static caller
//  (EmergencyAlert.send(), which has no BuildContext) can turn Live
//  Location on when a foreground alert fires. The Track page's toggle is
//  now a thin wrapper around this — behavior is unchanged from before
//  this extraction.
//  See docs/superpowers/specs/2026-07-10-guardian-live-view-design.md
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:location/location.dart' as loc;

import 'share_link_prefs.dart';

class LiveLocationService {
  LiveLocationService._();

  static final loc.Location _location = loc.Location();
  static StreamSubscription<loc.LocationData>? _sub;

  static final ValueNotifier<bool> isLive = ValueNotifier(false);

  /// Starts streaming fixes to Firestore for the signed-in user. No-op if
  /// already running or nobody is signed in (mirrors the snackbar-free
  /// "just don't start" behavior LocationPage already had for this case).
  static Future<void> start() async {
    if (_sub != null) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    await _location.changeSettings(
        interval: 300, accuracy: loc.LocationAccuracy.high);
    _sub = _location.onLocationChanged.handleError((_) => stop()).listen(
        (d) async {
      await FirebaseFirestore.instance.collection('location').doc(uid).set({
        'latitude': d.latitude,
        'longitude': d.longitude,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (ShareLinkPrefs.isActive) {
        await FirebaseFirestore.instance
            .collection('shared_locations')
            .doc(ShareLinkPrefs.shareId.value)
            .set({
          'latitude': d.latitude,
          'longitude': d.longitude,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    });
    isLive.value = true;
  }

  static void stop() {
    _sub?.cancel();
    _sub = null;
    isLive.value = false;
  }
}
```

- [ ] **Step 2: Update `LocationPage` to use it**

In `lib/pages/location_page.dart`, remove these now-redundant members from
`_LocationPageState`:

```dart
  final loc.Location location = loc.Location();
  StreamSubscription<loc.LocationData>? _sub;

  bool get _isLive => _sub != null;
```

Remove the `location.changeSettings(...)` call from `initState` — leave
`_requestPermission()`. `initState` becomes:

```dart
  @override
  void initState() {
    super.initState();
    _requestPermission();
  }
```

Remove `_sub?.cancel();` from `dispose()` — `dispose()` becomes:

```dart
  @override
  void dispose() {
    // NOTE: we intentionally do NOT stop the siren here — it should keep playing
    // even if you leave this tab.
    super.dispose();
  }
```

Remove the `_listenLocation`/`_stopListening` methods entirely (the ones
under the `// ── logic (yours, trimmed) ──` comment, right before
`_siren()`).

Add the import:

```dart
import '../services/live_location_service.dart';
```

Replace every remaining use of `_isLive` in `build()` — there are two: the
`_MapPreview(isLive: _isLive)` call and the Live Location card's `Switch`
row. Wrap just that card in a `ValueListenableBuilder`. Replace:

```dart
              // map preview (decorative — tap to open full Map tab if you wire it)
              _MapPreview(isLive: _isLive),
              const SizedBox(height: 10),

              // live toggle
              LumiCard(
                child: Row(
                  children: [
                    _TileIcon(
                        icon: Icons.my_location,
                        bg: LumiColors.accent.withOpacity(0.14),
                        fg: LumiColors.accent),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Live location',
                              style:
                                  LumiText.body(14.5, weight: FontWeight.w700)),
                          Text(_isLive ? 'Sharing now' : 'Off',
                              style:
                                  LumiText.body(12, color: LumiColors.textSub)),
                        ],
                      ),
                    ),
                    Switch(
                      value: _isLive,
                      activeColor: Colors.white,
                      activeTrackColor: LumiColors.accent,
                      onChanged: (v) =>
                          v ? _listenLocation() : _stopListening(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 9),
```

with:

```dart
              // map preview (decorative — tap to open full Map tab if you wire it)
              ValueListenableBuilder<bool>(
                valueListenable: LiveLocationService.isLive,
                builder: (_, isLive, __) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _MapPreview(isLive: isLive),
                    const SizedBox(height: 10),

                    // live toggle
                    LumiCard(
                      child: Row(
                        children: [
                          _TileIcon(
                              icon: Icons.my_location,
                              bg: LumiColors.accent.withOpacity(0.14),
                              fg: LumiColors.accent),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Live location',
                                    style: LumiText.body(14.5,
                                        weight: FontWeight.w700)),
                                Text(isLive ? 'Sharing now' : 'Off',
                                    style: LumiText.body(12,
                                        color: LumiColors.textSub)),
                              ],
                            ),
                          ),
                          Switch(
                            value: isLive,
                            activeColor: Colors.white,
                            activeTrackColor: LumiColors.accent,
                            onChanged: (v) => v
                                ? LiveLocationService.start()
                                : LiveLocationService.stop(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 9),
```

Check whether `dart:async` (for `StreamSubscription`) is still used
elsewhere in this file after removing `_sub` — if `Timer` (from the Track
page's own display-refresh work, if already present) or nothing else uses
it, remove the now-unused `import 'dart:async';`; otherwise leave it. Check
whether `import 'package:location/location.dart' as loc;` is still needed
— it isn't referenced anywhere else in this file once `location`/`_sub`
are removed, so remove that import too.

- [ ] **Step 3: Stop Live Location on logout**

In `lib/navigation_bar/main_page.dart`, add the import:

```dart
import '../services/live_location_service.dart';
```

In `_NavBarPageState.dispose()`, add a call alongside the existing
`ShakeGuardService.stop()` logout cleanup. Replace:

```dart
    if (!kIsWeb && Platform.isAndroid) ShakeGuardService.stop(); // logout
    super.dispose();
```

with:

```dart
    if (!kIsWeb && Platform.isAndroid) ShakeGuardService.stop(); // logout
    LiveLocationService.stop(); // logout — all platforms, not Android-only
    super.dispose();
```

- [ ] **Step 4: Format and verify with static analysis**

Run: `dart format lib/pages/location_page.dart lib/services/live_location_service.dart lib/navigation_bar/main_page.dart`
Run: `flutter analyze lib/pages/location_page.dart lib/services/live_location_service.dart lib/navigation_bar/main_page.dart`
Expected: no new errors (pre-existing `deprecated_member_use` infos already
in these files are unrelated).

- [ ] **Step 5: Run the full test suite**

Run: `flutter test`
Expected: all tests PASS — in particular, any existing Track-page widget
tests must still pass unchanged (this task must not alter observable
behavior).

- [ ] **Step 6: On-device verification**

Build and install a debug APK, then on the Track page: confirm the Live
Location switch still turns on/off, the "Sharing now"/"Off" label still
updates, and the "Recent Pings" card still shows updating coordinates —
identical to its behavior before this task.

- [ ] **Step 7: Commit**

```bash
git add lib/pages/location_page.dart lib/services/live_location_service.dart lib/navigation_bar/main_page.dart
git commit -m "refactor: extract Live Location streaming into LiveLocationService"
```

---

### Task 6: Auto-enable Live Location on a foreground alert

**Files:**
- Modify: `lib/services/emergency_alert.dart`

**Interfaces:**
- Consumes: `LiveLocationService.start` (Task 5).
- Produces: no new public interface — `EmergencyAlert.send()`'s existing
  signature and return type are unchanged.

- [ ] **Step 1: Add the import and the call**

In `lib/services/emergency_alert.dart`, add the import:

```dart
import 'live_location_service.dart';
```

In the existing `send()` method (the foreground path — used by the SOS
button and a foreground-detected shake, never `sendBackground`, per this
plan's Global Constraints), add the call right at the top. Replace:

```dart
  static Future<List<String>> send() async {
    final contacts = await DBHelper().getContacts();
    if (contacts.isEmpty) return ['Add emergency contacts first.'];

    final failures = <String>[];
```

with:

```dart
  static Future<List<String>> send() async {
    final contacts = await DBHelper().getContacts();
    if (contacts.isEmpty) return ['Add emergency contacts first.'];

    // Foreground-only: this is what lets the guardian's shared page keep
    // moving instead of showing one static point. A background/killed-app
    // alert (sendBackground) has no widget tree to stream GPS from, so it
    // isn't attempted there — see this plan's Global Constraints.
    await LiveLocationService.start();

    final failures = <String>[];
```

- [ ] **Step 2: Run the full test suite**

Run: `flutter test`
Expected: all tests PASS — `LiveLocationService.start()` returns early
(no-op) when nobody is signed in, which is the state every existing
`send()` test already runs under, so no existing test's behavior changes.

- [ ] **Step 3: Run static analysis**

Run: `flutter analyze lib/services/emergency_alert.dart`
Expected: no new errors.

- [ ] **Step 4: On-device verification**

With a safe placeholder guardian roster, confirm: pressing and releasing
the SOS hold button turns the Track page's Live Location switch on (visit
the Track tab after triggering SOS and confirm "Sharing now"), in addition
to the alert SMS/call already working as before.

- [ ] **Step 5: Commit**

```bash
git add lib/services/emergency_alert.dart
git commit -m "feat: auto-enable Live Location when a foreground alert fires"
```

---

### Task 7: Guardian-facing web page and Hosting deploy config

**Files:**
- Create: `public/share.html`
- Modify: `firebase.json` (adds a `hosting` block)

**Interfaces:**
- Consumes: the `shared_locations/{shareId}` document shape from Task 1
  (`ownerUid`, `name`, `latitude`, `longitude`, `updatedAt`, `expiresAt`)
  and the URL shape from Task 3 (`?id=<shareId>`).
- Produces: nothing further downstream — this is the last task.

This page has no automated test (no test runner exists for this new
static-page surface, and the design doc calls this out explicitly) —
verified manually per Step 3 below.

- [ ] **Step 1: Add the Hosting config**

In `firebase.json`, add a `hosting` block (alongside the existing
`flutter`, `firestore`, and `emulators` keys):

```json
  "hosting": {
    "public": "public",
    "ignore": ["firebase.json", "**/.*"]
  }
```

- [ ] **Step 2: Write `public/share.html`**

Create the `public/` directory and `public/share.html`:

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Lumi — Live location</title>
  <style>
    html, body { margin: 0; height: 100%; font-family: -apple-system, Roboto, Arial, sans-serif; background: #06080E; color: #E8ECF4; }
    #map { position: absolute; inset: 0; }
    #banner { position: absolute; top: 0; left: 0; right: 0; padding: 14px 18px; background: rgba(6,8,14,0.85); z-index: 10; }
    #banner h1 { margin: 0 0 4px; font-size: 16px; }
    #banner p { margin: 0; font-size: 13px; color: #9AA5B8; }
    #expired { position: absolute; inset: 0; display: none; align-items: center; justify-content: center; text-align: center; padding: 24px; }
    #expired.show { display: flex; }
    #expired.show ~ #map { display: none; }
  </style>
</head>
<body>
  <div id="banner">
    <h1 id="name">Loading…</h1>
    <p id="updated"></p>
  </div>
  <div id="map"></div>
  <div id="expired">
    <div>
      <h1>This share has expired</h1>
      <p>Ask them to send a new alert if they still need help.</p>
    </div>
  </div>

  <script type="module">
    import { initializeApp } from "https://www.gstatic.com/firebasejs/10.12.0/firebase-app.js";
    import { getFirestore, doc, onSnapshot } from "https://www.gstatic.com/firebasejs/10.12.0/firebase-firestore.js";

    // Same values already public in lib/firebase_options.dart's web config
    // — Firebase client config is not a secret; access control is enforced
    // entirely by firestore.rules, not by hiding this object.
    const firebaseConfig = {
      apiKey: "AIzaSyDfBEDDNcpZNakUiOFeAkVJmof8gxgpCFk",
      projectId: "safety-project-71d83",
      appId: "1:405608367816:web:5552f3e67ba106024a07fd",
    };

    const app = initializeApp(firebaseConfig);
    const db = getFirestore(app);

    const params = new URLSearchParams(window.location.search);
    const shareId = params.get("id");

    const nameEl = document.getElementById("name");
    const updatedEl = document.getElementById("updated");
    const expiredEl = document.getElementById("expired");

    let map, marker;
    function ensureMap(lat, lng) {
      if (map) return;
      map = new google.maps.Map(document.getElementById("map"), {
        center: { lat, lng },
        zoom: 16,
      });
      marker = new google.maps.Marker({ position: { lat, lng }, map });
    }

    function showExpired() {
      expiredEl.classList.add("show");
    }

    if (!shareId) {
      showExpired();
    } else {
      onSnapshot(
        doc(db, "shared_locations", shareId),
        (snap) => {
          if (!snap.exists()) { showExpired(); return; }
          const data = snap.data();
          const expiresAt = data.expiresAt?.toDate?.();
          if (expiresAt && expiresAt.getTime() < Date.now()) { showExpired(); return; }

          nameEl.textContent = `${data.name ?? "Someone"}'s live location`;
          updatedEl.textContent = "Live — updating automatically";
          ensureMap(data.latitude, data.longitude);
          marker.setPosition({ lat: data.latitude, lng: data.longitude });
          map.panTo({ lat: data.latitude, lng: data.longitude });
        },
        () => showExpired() // a read denial (expired, per firestore.rules) lands here too
      );
    }
  </script>
  <script src="https://maps.googleapis.com/maps/api/js?key=AIzaSyBFWjw90iH5rkDve37AUtJ67BZVk1XQAaI"></script>
</body>
</html>
```

The `firebaseConfig` values above match `lib/firebase_options.dart`'s
existing `web` block exactly; the Maps JS key reuses the same value
already in `android/app/src/main/AndroidManifest.xml`'s
`com.google.android.geo.API_KEY` (a Maps API key is not platform-locked by
default, though restricting it to specific referrers/package names in
Google Cloud Console is a reasonable follow-up hardening step, not
required for this to function). Neither value is a secret — see the code
comment above `firebaseConfig`.

- [ ] **Step 3: Manual verification and deploy**

```bash
firebase deploy --only hosting,firestore:rules
```

Then, with a safe placeholder guardian roster:
1. Trigger a foreground SOS alert (or shake) with Live Location off
   beforehand — confirm it turns on (Task 6) and the SMS contains a second
   link alongside the static Maps pin.
2. Open that link on a separate device/browser — confirm the map renders
   centered on the current position and the "Live — updating
   automatically" label shows.
3. Move the sending device (or wait for a new GPS fix) — confirm the
   marker updates without reloading the page.
4. Manually edit a share's `expiresAt` in the Firebase console to the past
   (or wait out a real 2-hour window) — reload the link and confirm "This
   share has expired" shows.
5. Open a URL with a nonsense `id` — confirm it also shows the expired
   state, not an error or a blank page.

- [ ] **Step 4: Commit**

```bash
git add public/share.html firebase.json
git commit -m "feat: add guardian-facing live-view web page and Hosting config"
```
