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
  const ownerDb = owner.firestore();
  await ownerDb.collection('location').doc('owner-uid').set({
    latitude: 1.23,
    longitude: 4.56,
  });

  await assertSucceeds(
    ownerDb.collection('location').doc('owner-uid').get()
  );

  const stranger = testEnv.authenticatedContext('someone-else');
  await assertFails(
    stranger.firestore().collection('location').doc('owner-uid').get()
  );
});
