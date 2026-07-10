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
