# Strike tracking

A two-tier accountability system for PNMs during onboarding.

## Why this exists

Actives need a way to flag PNMs who miss obligations (late, no-shows, attitude,
whatever). But individual actives shouldn't unilaterally issue strikes — the
**New Member Educator (NME)** is the official keeper of accountability and the
only one who can finalize a strike.

So the workflow is:

1. **Any active** files a *strike request* against one or more PNMs with a
   shared reason. Multi-PNM is the common case ("we all got one strike one
   time" — Om).
2. **The NME** reviews the request in their inbox, can partially approve
   (uncheck individual PNMs), or deny outright with an optional explanation.
3. On approval the request **fans out** into individual `/strikes` documents —
   one per approved PNM — and each PNM's `users.strikes` counter increments.
4. The NME can later **amend** a strike (rewrite the reason, original is
   preserved) or **soft-remove** it (counter decrements, audit record stays).

There are no auto-flags or thresholds — strikes are pure tracking, not
enforcement (per Om's spec).

## Data model

### `users/{uid}` — two new fields

| Field    | Type | Default | Meaning                                              |
| -------- | ---- | ------- | ---------------------------------------------------- |
| `isNme`  | bool | `false` | Boolean flag promoting an active to NME powers       |
| `strikes`| int  | `0`     | Live count of non-removed strikes against this user  |

`isNme` is intentionally a flag, not a third role, because the NME is also a
regular active in every other respect. Promotion has **no app UI** — flip it
manually in Firebase Console (or via `seed.js` for the test NME).

### `/strikeRequests/{reqId}` — pending NME review

```ts
{
  pnmUids: string[],          // who the strike targets
  pnmNames: string[],         // parallel array, cached for display
  reason: string,             // shared justification
  issuedBy: string,           // active uid that filed it
  issuedByName: string,
  status: 'pending' | 'approved' | 'denied',
  approvedPnmUids: string[],  // populated on approve (subset of pnmUids)
  reviewedBy: string | null,  // NME uid
  reviewedByName: string | null,
  createdAt: timestamp,
  reviewedAt: timestamp | null,
  denyReason: string | null,  // optional NME note on denial
}
```

### `/strikes/{strikeId}` — finalized strike

```ts
{
  pnmUid: string,             // exactly one PNM per strike doc
  pnmName: string,
  reason: string,             // original
  issuedBy: string, issuedByName: string,
  approvedBy: string,         // NME uid
  approvedByName: string,
  requestId: string | null,   // back-reference to the source request
  createdAt: timestamp,

  // amendments (NME-only)
  amendedReason: string | null,
  amendedBy: string | null,
  amendedAt: timestamp | null,

  // soft-remove (NME-only)
  removed: boolean,
}
```

Use `Strike.effectiveReason` to read the right one ("amended if present").
Strikes are **never hard-deleted** — `removed: true` flips the visibility and
decrements the user counter, but the audit record persists.

## Code map

| File                                                      | Role                                                    |
| --------------------------------------------------------- | ------------------------------------------------------- |
| `lib/models/app_user.dart`                                | Added `isNme` and `strikes` fields                      |
| `lib/models/strike.dart`                                  | New — `Strike` model with amendment / removal fields    |
| `lib/models/strike_request.dart`                          | New — `StrikeRequest` model with multi-PNM support      |
| `lib/services/strike_service.dart`                        | New — submit / approve / deny / amend / remove          |
| `lib/screens/active/strike_request_form.dart`             | New — multi-PNM picker + reason                         |
| `lib/screens/active/strike_approvals_screen.dart`         | New — NME inbox with per-PNM checkboxes                 |
| `lib/screens/active/strike_amendments_screen.dart`        | New — NME audit / edit / soft-delete                    |
| `lib/screens/pnm/my_strikes_screen.dart`                  | New — PNM read-only view of their own strikes           |
| `lib/screens/shared/app_scaffold.dart`                    | Added `_StrikeMenu` PopupMenuButton in app bar          |
| `lib/main.dart`                                           | Registered `Provider<StrikeService>`                    |
| `firestore.rules`                                         | Added `/strikes` and `/strikeRequests` rules; tightened |
| `lib/services/auth_service.dart`                          | Updated `signUp` to write the new `AppUser` fields      |

## How navigation hooks in

The app bar (in `app_scaffold.dart`) gets a single new icon: `Icons.gavel`,
which opens a popup menu with role-aware items:

- PNM sees: **My strikes**
- Active sees: **Submit strike request**
- NME (active + `isNme=true`) also sees: **Strike approvals**, **Strike amendments**

Same menu shows on both home screens because they share `AppScaffold`.

## Firestore security model

Implemented in `firestore.rules`:

- `/users/{uid}.strikes` is **NOT** writable by the user themselves — that's a
  v1 hardening compared to the old "allow update if isSelf" rule. Only the
  NME can mutate the strikes counter on someone else's doc, and only that
  one field.
- `/users/{uid}.isNme` is also locked from self-mutation. Promotion is a
  Firestore Console operation by design.
- `/strikeRequests`: any active can create their own; only the NME can
  approve / deny; nobody can delete.
- `/strikes`: only the NME can create or update; nobody can delete (audit).

Read access is broad on purpose (chapter context matters): all signed-in users
see /users, all signed-in see /pings, the affected PNM and any active see
/strikes, the issuer and the NME see their `/strikeRequests`.

## Testing the flow

After running `cd scripts && npm install && npm run seed` (see
`docs/SEEDING.md`):

1. Sign in as any **active** (`active01@sepping.test`, password `Test1234!`).
   Open the gavel menu → **Submit strike request**. Tick a few PNMs, type a
   reason, submit. You should get a snackbar.
2. Sign out, sign in as the **NME** (`nme@sepping.test`, same password). Open
   gavel → **Strike approvals**. The request appears with all PNMs checked.
   Uncheck one, approve. The request disappears from the inbox.
3. Open gavel → **Strike amendments**. The approved strikes appear; edit one's
   reason, then remove another. Confirm removal moves it to the "REMOVED"
   section with a strike-through.
4. Sign out, sign in as a struck PNM (e.g. `pnm03@sepping.test`). Open gavel →
   **My strikes**. You see the strike(s) with reasons.

## v2 punch list

- Server-side enforcement via Cloud Functions (mirrors the existing ping v2
  punch list — currently any motivated user could decrement their own counter
  in a forked client).
- Notifications when a strike lands or a request gets reviewed (FCM).
- A formal `UserRole.nme` role replacing the boolean, if NMEs end up needing
  meaningfully different UI from regular actives.
- Per-cycle archival instead of `reset-cycle.js` wipe — add a `cycleLabel`
  field, archive on rollover, surface a "previous cycles" view for retros.
