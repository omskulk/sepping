# Seeding & resetting test data

Three Node scripts in `/scripts/` populate, wipe, or reset the Firestore project
without touching real chapter data. They use the Firebase **Admin SDK** with the
service account key at `/serviceAccountKey.json` (gitignored).

## One-time setup

```bash
cd scripts
npm install
```

That installs `firebase-admin`. Nothing else is needed — the scripts pick up
`../serviceAccountKey.json` automatically via `firebase-init.js`.

If you don't have the key yet:
1. Firebase Console → Project Settings → Service Accounts → **Generate new private key**.
2. Move the downloaded JSON to `/serviceAccountKey.json` (the path the scripts expect).
3. The `.gitignore` already has `serviceAccountKey.json` — it will not be committed.

## `npm run seed` — populate test users

Creates **26 users** all sharing one password (`Test1234!`):

| Email                                       | Role   | Notes                            |
| ------------------------------------------- | ------ | -------------------------------- |
| `nme@sepping.test`                          | active | `isNme: true` (NME powers)       |
| `active01@sepping.test` … `active05`        | active | regular actives                  |
| `pnm01@sepping.test` … `pnm20`              | pnm    | 20 PNMs to test multi-strike     |

Every doc gets `isTestUser: true` so `unseed.js` can find them later.

The script is **idempotent** — running it a second time updates existing
records instead of erroring. Safe to re-run after schema changes; existing
users get the new fields merged in.

## `npm run unseed` — wipe just the test users

Finds every user with `isTestUser: true` and deletes:

1. Their `/strikes` and `/strikeRequests` documents
2. Pings they created or were assigned
3. Their `/users` document
4. Their Firebase Auth record

Real chapter data is **never touched** because real users won't carry the
`isTestUser` flag.

## `npm run reset-cycle` — end-of-cycle nuke

Simulates the end of a rush cycle. Deletes:

- Every PNM (user doc + auth record)
- The entire `/strikes` collection
- The entire `/strikeRequests` collection
- Every ping created by or assigned to a deleted PNM

**Actives and the NME are preserved.** This includes test actives if they
exist — `reset-cycle.js` is intentionally indiscriminate among PNMs (test or
not), because that's the real-world action: nuke last cycle, start fresh.

The script **prompts for `YES` confirmation** before doing anything because it
can't be undone.

## Common workflows

**Daily dev loop:**
```bash
npm run unseed   # clean slate
npm run seed     # repopulate
flutter run -d chrome
```

**Test the strike flow without re-running seed:**
```bash
# (already seeded earlier today — just clear pings/strikes)
npm run unseed && npm run seed   # cheapest way; ~3 seconds
```

**Demoing to chapter, then resetting before real use:**
```bash
npm run seed              # populate for demo
# ...do the demo...
npm run unseed            # wipe the test users only
# real chapter members can sign up normally and your prod data is clean
```

## Promoting a real user to NME

Seeding only creates the *test* NME. To promote a real chapter member after
they've signed up:

1. Firebase Console → Firestore → `users` → find their doc by uid or email
2. Add field `isNme: true` (boolean)
3. Save

That's it — they'll see the NME-only menu items the next time the app polls
their user doc (instant on next snapshot tick).

## Why no Firestore Emulator setup?

Considered, decided against for now. The seed/unseed pair makes prod
pollution recoverable in a few seconds, and using the real Firestore lets you
test the actual security rules instead of permissive emulator defaults.

If prod pollution becomes a daily annoyance, the path forward is:
1. `firebase init emulators` (Auth, Firestore, Storage)
2. Add a debug-mode flag in `main.dart` that calls
   `FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080)` etc.
3. Re-point the seed scripts at the emulator host.

That's a half-day of work; defer until needed.
