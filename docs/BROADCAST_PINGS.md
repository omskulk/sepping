# Multi-PNM (broadcast) pings

## Why this exists

The original drop-ping dialog forced the active to pick exactly one PNM per
ping. That's wrong for the common case: a scavenger-hunt style task
("take a selfie in front of the library") is almost always sent to the whole
pledge class. Without broadcast, an active would have to open the dialog,
retype the same task, and slide the same cost slider 20 times.

## UX

`DropPingDialog` now has a `SegmentedButton` at the top of the form:

- **All PNMs** *(default)* — assignees are every PNM currently in the user directory.
- **Select** — expands an inline `CheckboxListTile` list so the active can pick
  any subset. Picks are keyed by `uid` (not by `AppUser` object identity) so
  they survive the Firestore snapshot stream rebuilding `AppUser` instances.

The cost slider now shows **cost per PNM** rather than total cost. Beneath it,
`_CostRecap` prints `N cr × K PNMs = total cr · you have X` so the active
can see the real bill before clicking. If `total > available`, the recap
turns red and bolds. The submit button also reflects the fan-out: **DROP 20
PINGS** instead of **DROP PING**.

## Service — `PingService.dropPingToMany`

Single transaction:

1. Read the active's `pingCredits`.
2. If `currentCredits < creditCost × assignees.length`, throw
   `InsufficientCreditsException`.
3. Allocate `assignees.length` ping refs (pre-allocated before the txn body
   so we can reference them inside it — Firestore requires all writes be on
   refs known up-front).
4. For each assignee, `txn.set` a new ping doc with a shared task / location
   / timestamp but distinct `assignedTo` / `assignedToName`.
5. `txn.update` the active's `pingCredits` by the total cost.

Firestore transactions cap at 500 writes. With 20 PNMs × 1 credits update = 21
writes, there's more than enough headroom. If the chapter scales to hundreds
of PNMs, chunk this or move it to a Cloud Function.

## Economics

Cost is **per PNM**. A 2-credit task to 10 PNMs costs 20 credits. Rationale:
each PNM fulfilling the task is its own completion event — credits should
track real work, not the number of times the active clicked DROP PIN.
If cost were flat, actives would spam broadcasts and the credit pool would
stop meaning anything.

## Security rules

No new rules needed. Each fan-out ping is still `createdBy: active.uid`,
which is what the `/pings` create rule already enforces:

```
allow create: if isSignedIn()
  && roleOf(request.auth.uid) == 'active'
  && request.resource.data.createdBy == request.auth.uid
  && request.resource.data.status == 'pending';
```

Every ping doc in the fan-out is independently validated.

## v2 punch list

- Filter / search inside the `Select` checklist (once PNM rosters exceed ~30).
- "Select all", "Select none", and "Invert" helpers above the checklist.
- Saved broadcast templates (reuse a task across weeks without retyping).
- Show a per-PNM completion ratio when revisiting the ping.
