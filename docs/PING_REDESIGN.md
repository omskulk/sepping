# Ping redesign — capacity, drafts, chapter-wide visibility

## Why this exists

The previous ping model was broken for how the chapter actually runs:

1. **Pings were profile-specific.** Each ping targeted exactly one PNM via
   `assignedTo`. Forced the active to pick a recipient at drop time, killed
   any "whoever grabs it first" dynamic.
2. **Actives couldn't see each other's work.** `watchPingsCreatedBy` scoped
   to the caller. If another active dropped a pickup-the-log ping nearby
   you'd never hear about it.
3. **Cost scaled with eligibility, not with work.** The prior broadcast fix
   (`dropPingToMany`) charged `costPer × eligiblePnms`, so blasting 20 PNMs
   for a 2-credit task cost 40 credits — even though only one body could do
   the task.
4. **No draft stage.** PNMs saw pings the instant they were dropped. No way
   to workshop a ping or commit to a capacity before going live.
5. **No map on the PNM side.** List only. PNMs couldn't pick spatially.

Om's ask (2026-04-20) reshaped the whole thing: pings are default-shared,
actives collaborate on a bulletin, publishing to PNMs is an explicit step,
and cost is tied to capacity rather than audience size.

## The new lifecycle

```
   ┌──────────────┐         drop                    ┌──────────────┐
   │              │ ───────────────────────────────▶│              │
   │  [no ping]   │   creates doc, debits credits   │   DRAFT      │
   │              │                                 │ (actives     │
   └──────────────┘                                 │  only)       │
                                                    └──────┬───────┘
                       edit capacity / cost / task         │  publish
                          trues-up credits ◀─────┐         │  (creator only)
                                                 │         ▼
                                          ┌──────────────────────┐
                                          │  PUBLISHED           │
                                          │  visibility: all     │
                                          │  or specific         │
                                          │  status: open        │
                                          └──────────┬───────────┘
                                                     │ accept
                                                     │ (claim slot)
                                                     ▼
                                          ┌──────────────────────┐
                                          │  PUBLISHED + claims  │
                                          │  when claims==cap →  │
                                          │  status: full        │
                                          └──────────┬───────────┘
                                                     │ each claim
                                                     │ submits proof
                                                     ▼
                                          ┌──────────────────────┐
                                          │  COMPLETED           │
                                          │  all claims have     │
                                          │  photoUrl            │
                                          └──────────────────────┘
```

### Answers that shaped it (from the user, 2026-04-20)

- **Debit timing**: credits debit at **drop** time (not publish). If the
  active edits capacity or cost on the draft, credits true-up in the same
  transaction (refund or top-up).
- **Publish auth**: **only the original creator** can publish their own
  draft. Other actives can see it on the bulletin but cannot push it live.
- **Capacity default**: **1** (first-come-first-served). Editable on the
  draft until publish. Once published, locks.

## Data model

All state lives on the single `/pings/{id}` doc — no subcollections. This
keeps accept/proof/completion mutations to a single transactional write.

```dart
class Ping {
  String id, createdBy, createdByName, taskDescription;
  double lat, lng;
  int creditCostPer;            // cost per claimable slot
  int capacity;                 // total slots
  PingVisibility visibility;    // draft | all | specific
  List<String> eligiblePnmUids; // used when visibility == specific
  List<PingClaim> claims;       // <= capacity
  PingStatus status;            // open | full | completed | cancelled
  DateTime createdAt;
  DateTime? publishedAt, completedAt;
}

class PingClaim {
  String pnmUid, pnmName;
  DateTime acceptedAt;
  String? photoUrl;             // null until proof submitted
  DateTime? completedAt;        // null until proof submitted
}
```

### Visibility

| Value      | PNM can see it? | Appears on bulletin? |
|------------|-----------------|----------------------|
| `draft`    | no              | yes (actives only)   |
| `all`      | every PNM       | no                   |
| `specific` | only if their uid ∈ eligiblePnmUids | no |

### Status

Derived automatically by the service:
- `open`: `claims.length < capacity` and not cancelled/completed.
- `full`: `claims.length == capacity` but at least one claim has no proof.
- `completed`: every claim has a `photoUrl`.
- `cancelled`: reserved (no UI yet).

## Credit economics

Cost = `creditCostPer × capacity`. A 2-credit task with 2 slots = 4 credits.
**Eligibility pool size doesn't affect cost.** Publishing to all 20 PNMs but
capping at 2 slots still costs 4 — matches the "two people picking up a log"
example.

Credits debit at drop. Editing a draft's capacity up or down moves credits
in lock-step, so the balance always equals `starting − Σ (still-published or
still-drafted capacity × cost)`.

## Code map

### Models
- `lib/models/ping.dart` — `Ping`, `PingClaim`, `PingVisibility`,
  `PingStatus`. Helpers: `totalCost`, `slotsRemaining`, `isEligibleForPnm`,
  `hasClaimFrom`, `claimFor`.

### Service
`lib/services/ping_service.dart` — all writes wrapped in Firestore
transactions:

| Method | Who | What |
|--------|-----|------|
| `dropPing` | active | creates draft, debits `costPer × capacity` |
| `updateDraft` | creator | mutates task/capacity/cost, trues-up credits |
| `publishPing` | creator | sets visibility to `all` or `specific`, stamps `publishedAt` |
| `acceptPing` | PNM | appends claim if eligible, slots free, not already claimed; flips status to `full` when last slot goes |
| `submitProof` | PNM | uploads to `pings/{id}/proof_{pnmUid}`, marks their claim completed, increments their `completedPings`, flips status to `completed` when last claim lands proof |

Streams:
- `watchAllPings` — whole collection (active map + bulletin).
- `watchPingsCreatedBy(uid)` — creator's pings ("my activity").
- `watchAvailablePingsForPnm(uid)` — published + eligible + not full (or
  already claimed by me). Built on top of `_watchPingsVisibleToPnm`.
- `watchMyClaimedPings(uid)` — where I already have a claim. Same base.

**Rule-compatible PNM fetch (`_watchPingsVisibleToPnm`)**: PNMs cannot do an
unfiltered `.snapshots()` on `/pings` — Firestore rejects queries whose
WHERE clauses don't prove every matched doc satisfies the read rule. So
the PNM path splits into two scoped queries that are each self-decidable:

1. `where('visibility', '==', 'all')`
2. `where('visibility', '==', 'specific').where('eligiblePnmUids', array-contains, pnmUid)`

These are merged and deduped-by-id client-side. Without this split, PNMs
silently see zero pings even though the rule nominally permits them.

### UI — active side

- `screens/active/active_home.dart` — three panes responsive: shared map of
  all pings (markers colored by status), bulletin of drafts (creator sees
  PUBLISH button, others read-only), my published pings.
- `screens/active/drop_ping_dialog.dart` — simplified draft editor: task,
  capacity stepper (default 1, 1–20), cost-per-slot slider (1–5), live
  total. No PNM picker.
- `screens/active/publish_ping_dialog.dart` — creator-only. Locks task /
  capacity / cost; picks All vs Select audience; for Select shows a PNM
  checklist.

### UI — PNM side

- `screens/pnm/pnm_home.dart` — map + dual-section sidebar:
  - Map markers: violet for specific, azure for all-PNM, green for already
    claimed by me.
  - Sidebar sections: **Just for you** (specific), **Chapter-wide** (all),
    **In progress** (claimed, not completed), **Completed**.
- `screens/pnm/ping_detail_screen.dart` — multi-state action bar:
  ACCEPT (N/cap free) → SUBMIT PROOF → COMPLETED. Also shows the full
  claims list with each PNM's accepted/completed timestamps + their photo
  (only surfaced for the viewer's own claim in v1).

## Security model

`firestore.rules` enforces:

- **Read**: actives see everything; PNMs see only published pings where
  they're eligible (`all` or `specific` with their uid listed).
- **Create**: active, creator is caller, visibility == `draft`, status ==
  `open`, zero claims, `capacity >= 1`.
- **Update**: creator OR any PNM. Precise-delta enforcement at the rule
  layer is painful; the client transactions are the source of truth, which
  matches the existing trust level around `pingCredits` on the active side.
  A Cloud Function hardening pass is explicitly a v2 item.
- **Delete**: forbidden. Cancellation would soft-transition status to
  `cancelled` (not wired in v1).

## Race safety

All state-mutating methods run inside `runTransaction`:
- Two PNMs grab the last slot → transaction retries; the second read sees
  the first claim and throws `CannotAcceptPingException('All slots are
  taken.')`.
- Active edits a draft in two tabs simultaneously → last-write-wins, but
  credit math is always derived from the read inside the same txn, so the
  balance stays consistent.
- PNM double-clicks SUBMIT PROOF → second txn sees the completed claim and
  no-ops (`myClaim.isCompleted` guard).

## Google Maps pin deprecation

The `google.maps.Marker is deprecated` console warning comes from **inside**
the `google_maps_flutter_web` plugin. Google has stated no discontinuation
is scheduled and promises 12 months' notice. Not actionable on our side
until the plugin ships `AdvancedMarkerElement` support.

## V2 punch list

- Cloud Function hardening to enforce the exact delta rules for PNM updates.
- Cancel-with-refund flow for draft owners.
- Proof thumbnails in the active's claims list (currently only the viewer's
  own proof is surfaced).
- Notifications when a slot fills or a proof lands.
- Marker clustering once pings > 50.
- Migrating pre-existing Firestore pings — not done; safer to wipe and
  re-seed since everything there is test data.
