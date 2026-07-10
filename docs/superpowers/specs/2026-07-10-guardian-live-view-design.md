# Guardian live-view share link — design

**Date:** 2026-07-10 · **Status:** approved

## What

When an alert fires — SOS hold, shake-to-SOS, or (once built) a missed
check-in — the app creates a short-lived, unguessable share link and
includes it in the alert SMS, alongside the existing static Google Maps
pin. Opening the link shows a small hosted web page with a live-updating
map of the user's position, refreshing automatically for **2 hours**, after
which the page shows "This share has expired." Guardians never need an
account or the app installed.

**Live Location auto-enable, and its real limit:** firing an alert while
the app is in the **foreground** (the SOS button, or a shake detected while
the app is open) also auto-enables Live Location streaming, so the shared
page keeps moving rather than showing one static point. This required
extracting Live Location's streaming logic out of `LocationPage`'s widget
state into its own small static service (`LiveLocationService`, see below)
so `EmergencyAlert.send()` — a plain static call with no widget access —
can start it. A **background-triggered** shake alert (app backgrounded or
killed, caught by the shake-guard foreground service) cannot reach this at
all: that isolate has no Flutter widget tree to stream GPS from, and
building a background GPS-polling mechanism to work around that is a
separate, materially larger project, out of scope here. A background alert
still only ever gets the one-shot position already captured for the SMS's
static pin — same as today.

Out of scope: guardian-initiated actions back to the sharer (no "I'm on my
way" button), a history of past shares, multiple simultaneous active
shares, editing/extending a share's expiry once created, background GPS
streaming for a killed/backgrounded app.

## Why this shape

- **A separate collection, not new access to `location/{uid}`:** the
  existing rule (`firestore.rules`) — "only the signed-in owner can read or
  write their own location" — is exactly right and must not be touched or
  weakened to accommodate guests. A new `shared_locations/{shareId}`
  collection, keyed by a long random token instead of the user's uid, keeps
  the blast radius of "readable by anyone with a link" scoped to opt-in
  emergency shares only, with zero risk of ever affecting the private
  per-user document.
- **Expiry enforced by Firestore itself, not a Cloud Function:** comparing
  `resource.data.expiresAt > request.time` directly in the security rule
  means an expired share becomes unreadable at the database layer the
  moment it lapses — no scheduled job needed to delete anything, no new
  backend component (this project has no Cloud Functions today) required
  just to enforce "this link stops working."
- **Only on an actual alert, not on toggling Live Location:** matches the
  same reasoning as the check-in timer's design — a share link is real
  standing infrastructure (a working, publicly-reachable URL) and should
  only ever exist because a real emergency was declared, never merely
  because the user turned on a switch during an ordinary walk.
- **A hand-written static page, not compiled Flutter Web:** this project's
  `web/` directory and web `firebase_options.dart` entry are default
  scaffolding from `flutterfire configure`, never actually deployed —
  standing up Firebase Hosting for the first time is new either way, but a
  small hand-written HTML/JS page (Firebase JS SDK + Google Maps JavaScript
  API) loads near-instantly for a guardian tapping a link mid-emergency,
  where a full Flutter Web bundle's slower first paint is a real cost, not
  a cosmetic one.
- **Added to the SMS, not replacing the static pin:** the static
  `maps.google.com/?q=lat,lng` link keeps working with zero dependencies
  (no page load, no JavaScript, no Firestore reachability) as an instant
  fallback if the hosted page or a guardian's connection ever fails.
- **The alert SMS pipeline is the single place this hooks in:** exactly
  like the primary-contact and (planned) check-in-timer features, this
  reuses `EmergencyAlert.send`/`sendBackground` as the one funnel so SOS,
  shake, and check-in alerts can never drift apart on whether a guardian
  gets a live link.

## Data model

New Firestore collection `shared_locations/{shareId}`, where `shareId` is a
32-byte value from `Random.secure()` (Dart's CSPRNG — no new package
needed), base64url-encoded. Each document:

```
{
  ownerUid: string,       // whose location this is (for the write rule only)
  name: string,           // first-name-only display, e.g. "Ahmed" — reuses
                          // the same email-local-part derivation SosPage
                          // already uses for its "Good evening, X" greeting
  latitude: number,
  longitude: number,
  updatedAt: Timestamp,   // server timestamp, refreshed on every position update
  expiresAt: Timestamp,   // set once at creation, never extended
}
```

`firestore.rules` gains, alongside the existing `location/{userId}` match
block (which is untouched):

```
match /shared_locations/{shareId} {
  // Anyone with the exact shareId can read it, but only while it hasn't
  // expired — no auth required, since guardians have no account.
  allow read: if resource.data.expiresAt > request.time;

  // Only the authenticated owner can create or update their own share doc.
  allow create: if request.auth != null
      && request.auth.uid == request.resource.data.ownerUid;
  allow update: if request.auth != null
      && request.auth.uid == resource.data.ownerUid;

  allow delete: if false; // shares just expire, nothing ever deletes them
}
```

A stray, expired document is harmless to leave in Firestore forever (small,
schemaless collection, no cost concern at this project's scale) — no
cleanup job is needed.

## App-side flow

New `lib/services/guardian_share.dart`:

- `GuardianShare.createShareLink({required String? coords})` — called from
  `EmergencyAlert.send`/`sendBackground` right where `coords` is already
  resolved. Returns `null` (no link included, message unchanged) if the
  user isn't signed in or `coords` is null — a share link is a bonus on top
  of an already-working alert, never a precondition for sending it. On
  success: generates a `shareId`, writes the initial `shared_locations` doc
  with a `expiresAt` 2 hours out, persists the active share via a new
  `ShareLinkPrefs` (below), and returns the full shareable URL. Always
  creates a brand-new `shareId` — a second alert within an existing share's
  2-hour window does not reuse or extend it, it simply mints another,
  independent one (each SMS always contains a currently-fresh link; an
  older still-valid one from an earlier alert continues working
  unaffected until its own expiry).
- `EmergencyAlert.buildAlertMessage(String? coords, {String? shareLink})`
  gains a second optional parameter, appended on its own line when present
  (`'...find me: <pin>\nLive location: <shareLink>'`) — mirrors exactly how
  the check-in timer plan already adds a `note` parameter to this same
  method; whichever of the two features lands second in the codebase
  extends the already-extended signature rather than the two conflicting.

New `lib/services/share_link_prefs.dart` (mirrors `ShakePrefs`/
`CheckInPrefs`'s shape): persists the currently-active `shareId` and its
`expiresAt` so the location-streaming code (below) can mirror each new GPS
fix into `shared_locations/{shareId}` for as long as a share is active and
unexpired. `ShareLinkPrefs.isActive` (`shareId != null && expiresAt != null
&& DateTime.now().isBefore(expiresAt!)`) gates that extra write.

### `LiveLocationService` extraction

Today, Live Location's `StreamSubscription`, start/stop logic, and its
write to `location/{uid}` all live directly on `_LocationPageState` (`_sub`,
`_listenLocation()`, `_stopListening()` in `lib/pages/location_page.dart`),
callable only because the Track page's own switch has a `BuildContext` and
widget-instance access. `EmergencyAlert.send()` (called from the SOS
button) has neither — it's a plain static method — so it cannot reach that
instance method to turn Live Location on.

New `lib/services/live_location_service.dart` extracts exactly that logic
into a static service: `LiveLocationService.isLive`
(`ValueNotifier<bool>`), `LiveLocationService.start()`, `.stop()` — the
subscription itself becomes a static field on this service instead of
per-widget state, and its listener callback writes to `location/{uid}` (as
today) and, when `ShareLinkPrefs.isActive`, also mirrors the same fix into
`shared_locations/{shareId}`. `LocationPage`'s Live Location `Switch`
becomes a thin wrapper: `onChanged: (v) => v ? LiveLocationService.start()
: LiveLocationService.stop()`, and its "Sharing now"/"Off" label binds to
`LiveLocationService.isLive` instead of local widget state. This is a
behavior-preserving extraction — the Track page's Live Location toggle
must look and work exactly as it does today after this change; the only
new caller is `EmergencyAlert.send()`, which calls
`LiveLocationService.start()` if it isn't already running, right before
building the alert message.

`ShareLinkPrefs` tracks only the single most-recently-created share — a
direct consequence of "no multiple simultaneous shares" being out of
scope. If a second alert fires and mints a new share while an earlier one
(from a prior alert, still within its own 2-hour window) is still open in
a guardian's browser, the location stream switches to mirroring into the
new doc only; the earlier link stops receiving position updates (it keeps
showing whatever position was last written to it, and its page still
correctly shows "live," not "expired," until its own `expiresAt` passes).
Accepted as an understood trade-off rather than solved here.

## Web page

New `public/share.html` (plus its own small `.js`), deployed via Firebase
Hosting — `firebase.json` gains a `hosting` block pointing `public` at this
new directory. On load: reads `id` from the URL query string, opens a
Firestore real-time listener (`onSnapshot`) on `shared_locations/{id}` via
the Firebase JS SDK, and:
- If the document doesn't exist or the read is denied (expired, per the
  rule above) — or is fetched successfully but its own `expiresAt` has
  already passed — shows "This share has expired."
- Otherwise renders a Google Map (JavaScript Maps API) centered on the
  latest `latitude`/`longitude`, updating the marker's position on every
  snapshot, with the `name` field and a "last updated Xs ago" label that
  ticks locally between snapshots.

The Firebase project config embedded in this page (API key, project id)
is the same kind of value already present in `lib/firebase_options.dart`
and is not a secret — Firebase's client SDKs are designed to ship these
publicly; all actual access control is enforced by the Firestore rule
above, not by hiding this configuration.

## Error handling

- No guardians, not signed in, or `coords` unavailable: `createShareLink`
  returns `null`, the alert SMS is sent exactly as it is today (static pin
  only, or the "location unavailable" message) — a share-link failure never
  blocks or alters the rest of the alert pipeline.
- A Firestore write failure while creating or updating a share doc is
  caught and swallowed the same way this codebase already treats
  non-critical alert-adjacent failures (e.g. `EmergencyAlert.sendBackground`
  already degrades GPS failures to a `null` coords rather than throwing) —
  the alert's SMS/call still proceed.
- The guardian's page has exactly two states to handle: "live" and
  "expired" (including "never existed," which looks identical to
  "expired" — no information is leaked about whether a given shareId was
  ever valid).

## Testing

- New `test/services/guardian_share_test.dart`: `createShareLink` returns
  `null` when not signed in; returns `null` when `coords` is null; on
  success, writes a `shared_locations` doc with the expected fields and an
  `expiresAt` ~2 hours out, and the returned URL contains the same
  `shareId` the doc was written under.
- New `test/services/share_link_prefs_test.dart` (mirrors the existing
  `shake_prefs_test.dart`/`checkin_prefs_test.dart` pattern): defaults to
  inactive; `start()` persists and survives a reload; `isActive` is false
  once `expiresAt` is in the past even without calling `clear()`.
- `buildAlertMessage`'s new `shareLink` parameter gets the same kind of
  test as the existing `coords`/`note` parameters: present vs. absent,
  byte-for-byte unchanged when omitted.
- No new automated test for the `LiveLocationService` extraction itself
  beyond confirming `flutter analyze`/`flutter test` are clean and the
  existing Track-page behavior is unchanged on-device — this is the same
  "widget/page-level wiring verified on-device" category as the rest of
  `location_page.dart`, not a regression in test rigor.
- The Firestore rule itself is verified with the Firebase emulator suite
  (`firebase emulators:exec` + the `@firebase/rules-unit-testing`
  package) — not a Flutter/Dart test — asserting: an unauthenticated read
  of a non-expired share succeeds; an unauthenticated read of an expired
  share is denied; a write from a uid that doesn't match `ownerUid` is
  denied.
- `public/share.html`'s JS has no automated test (no test runner exists for
  this new static-page surface) — verified manually: open a real share
  link on a second device/browser and confirm the marker moves as the
  sharing device's GPS updates, and confirm an expired/invalid id shows the
  expired state.
