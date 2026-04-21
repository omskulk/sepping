import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../models/app_user.dart';
import '../models/ping.dart';

/// Thrown by [PingService.dropPing] / [PingService.updateDraft] when the
/// active doesn't have enough credits to cover `costPer × capacity` (or the
/// delta from a capacity bump).
class InsufficientCreditsException implements Exception {
  final int have;
  final int need;
  InsufficientCreditsException(this.have, this.need);
  @override
  String toString() => 'Not enough ping credits (have $have, need $need).';
}

/// Thrown by [PingService.acceptPing] when a PNM tries to claim a slot that
/// is no longer available — either the ping just filled, the PNM is no longer
/// eligible, or they already have a claim. Race-safe via Firestore txn.
class CannotAcceptPingException implements Exception {
  final String reason;
  CannotAcceptPingException(this.reason);
  @override
  String toString() => 'Cannot accept ping: $reason';
}

/// Centralised ping write/read API. Every mutation that affects credits or
/// slot allocation runs inside a Firestore transaction so concurrent edits
/// (two PNMs grabbing the last slot at the same time, an active editing a
/// draft while another tab has it open, etc.) cannot corrupt state.
class PingService {
  PingService({FirebaseFirestore? firestore, FirebaseStorage? storage})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  CollectionReference<Map<String, dynamic>> get _pings =>
      _firestore.collection('pings');
  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  // ---------------------------------------------------------------------------
  // Writes — active side
  // ---------------------------------------------------------------------------

  /// Drops a fresh draft. Visibility starts at `draft` (PNM-invisible). Debits
  /// `creditCostPer × capacity` from the active immediately, per the user's
  /// "debit at drop" decision (2026-04-20).
  Future<Ping> dropPing({
    required AppUser active,
    required double lat,
    required double lng,
    required String taskDescription,
    required int creditCostPer,
    required int capacity,
  }) async {
    assert(capacity >= 1, 'capacity must be >= 1');
    assert(creditCostPer >= 1, 'creditCostPer must be >= 1');
    final totalCost = creditCostPer * capacity;
    final newRef = _pings.doc();
    final activeRef = _users.doc(active.uid);

    return _firestore.runTransaction<Ping>((txn) async {
      final activeSnap = await txn.get(activeRef);
      final currentCredits =
          (activeSnap.data()?['pingCredits'] as num?)?.toInt() ?? 0;
      if (currentCredits < totalCost) {
        throw InsufficientCreditsException(currentCredits, totalCost);
      }

      final ping = Ping(
        id: newRef.id,
        createdBy: active.uid,
        createdByName: active.displayName,
        lat: lat,
        lng: lng,
        taskDescription: taskDescription,
        creditCostPer: creditCostPer,
        capacity: capacity,
        visibility: PingVisibility.draft,
        eligiblePnmUids: const [],
        claims: const [],
        status: PingStatus.open,
        createdAt: DateTime.now(),
        publishedAt: null,
        completedAt: null,
      );

      txn.set(newRef, ping.toDoc());
      txn.update(activeRef, {'pingCredits': currentCredits - totalCost});
      return ping;
    });
  }

  /// Edits a draft. Only mutable fields are exposed. If [capacity] or
  /// [creditCostPer] change the credit balance is trued-up (refund or extra
  /// debit) in the same transaction. Throws [StateError] if the ping is no
  /// longer a draft (capacity / cost lock at publish).
  Future<void> updateDraft({
    required Ping ping,
    String? taskDescription,
    int? capacity,
    int? creditCostPer,
  }) async {
    if (!ping.isDraft) {
      throw StateError('Cannot edit a published ping.');
    }
    final pingRef = _pings.doc(ping.id);
    final activeRef = _users.doc(ping.createdBy);
    final newCapacity = capacity ?? ping.capacity;
    final newCostPer = creditCostPer ?? ping.creditCostPer;
    final newTotal = newCapacity * newCostPer;
    final oldTotal = ping.capacity * ping.creditCostPer;
    final delta = newTotal - oldTotal; // +ve: needs more debit; -ve: refund

    await _firestore.runTransaction<void>((txn) async {
      final activeSnap = await txn.get(activeRef);
      final currentCredits =
          (activeSnap.data()?['pingCredits'] as num?)?.toInt() ?? 0;
      if (delta > 0 && currentCredits < delta) {
        throw InsufficientCreditsException(currentCredits, delta);
      }

      final patch = <String, dynamic>{
        'taskDescription': ?taskDescription,
        'capacity': ?capacity,
        'creditCostPer': ?creditCostPer,
      };
      if (patch.isEmpty) return;

      txn.update(pingRef, patch);
      if (delta != 0) {
        txn.update(activeRef, {'pingCredits': currentCredits - delta});
      }
    });
  }

  /// Publishes a draft. Locks capacity / cost (via the rules) by transitioning
  /// `visibility` away from `draft`. If [eligiblePnmUids] is non-empty,
  /// visibility becomes `specific`; otherwise `all`.
  Future<void> publishPing({
    required Ping ping,
    List<String> eligiblePnmUids = const [],
  }) async {
    if (!ping.isDraft) {
      throw StateError('Ping is already published.');
    }
    final visibility = eligiblePnmUids.isEmpty
        ? PingVisibility.all
        : PingVisibility.specific;
    await _pings.doc(ping.id).update({
      'visibility': visibility.storageValue,
      'eligiblePnmUids': eligiblePnmUids,
      'publishedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  // ---------------------------------------------------------------------------
  // Writes — PNM side
  // ---------------------------------------------------------------------------

  /// First-come-first-served slot grab. Re-reads the ping inside a transaction
  /// to avoid racing two PNMs against the last slot. If the ping is full,
  /// already claimed by this PNM, or the PNM isn't eligible, throws
  /// [CannotAcceptPingException] with a human-readable reason.
  Future<void> acceptPing({
    required Ping ping,
    required AppUser pnm,
  }) async {
    final pingRef = _pings.doc(ping.id);

    await _firestore.runTransaction<void>((txn) async {
      final snap = await txn.get(pingRef);
      if (!snap.exists) {
        throw CannotAcceptPingException('Ping no longer exists.');
      }
      final live = Ping.fromDoc(snap);
      if (live.isDraft) {
        throw CannotAcceptPingException('Ping is still a draft.');
      }
      if (!live.isEligibleForPnm(pnm.uid)) {
        throw CannotAcceptPingException('You are not eligible for this ping.');
      }
      if (live.hasClaimFrom(pnm.uid)) {
        throw CannotAcceptPingException('You already accepted this ping.');
      }
      if (live.claims.length >= live.capacity) {
        throw CannotAcceptPingException('All slots are taken.');
      }

      final newClaim = PingClaim(
        pnmUid: pnm.uid,
        pnmName: pnm.displayName,
        acceptedAt: DateTime.now(),
        photoUrl: null,
        completedAt: null,
      );
      final updatedClaims = [...live.claims, newClaim];
      final newStatus = updatedClaims.length >= live.capacity
          ? PingStatus.full
          : PingStatus.open;

      txn.update(pingRef, {
        'claims': updatedClaims.map((c) => c.toMap()).toList(),
        'status': newStatus.storageValue,
      });
    });
  }

  /// Submits proof for *this PNM's* claim. Uploads the photo to a per-PNM
  /// path (so two simultaneous proofs on the same ping can't overwrite each
  /// other), then transactionally:
  ///   - Marks this PNM's claim completed (photoUrl + completedAt).
  ///   - Increments the PNM's `completedPings` counter (leaderboard).
  ///   - If every claim is now completed, sets ping status to `completed`
  ///     and stamps `completedAt`.
  Future<void> submitProof({
    required Ping ping,
    required AppUser pnm,
    required Uint8List photoBytes,
    required String contentType,
  }) async {
    if (!ping.hasClaimFrom(pnm.uid)) {
      throw StateError('You have no claim on this ping.');
    }

    // Split the flow into stages so the caller gets a specific error for
    // each failure mode — "Dart exception thrown from converted Future" by
    // itself is useless, and almost every failure in this method bubbles up
    // as exactly that when we don't inspect FirebaseException fields.
    final ref = _storage.ref('pings/${ping.id}/proof_${pnm.uid}');
    late final String url;
    try {
      final upload = await ref.putData(
        photoBytes,
        SettableMetadata(contentType: contentType),
      );
      url = await upload.ref.getDownloadURL();
    } on FirebaseException catch (e, st) {
      debugPrint('submitProof upload FirebaseException: '
          'code=${e.code} message=${e.message}\n$st');
      throw Exception('Upload failed (${e.code}): ${e.message ?? e.code}');
    } catch (e, st) {
      debugPrint('submitProof upload unknown: $e\n$st');
      rethrow;
    }

    final pingRef = _pings.doc(ping.id);
    final pnmRef = _users.doc(pnm.uid);

    try {
      await _firestore.runTransaction<void>((txn) async {
        // CRITICAL: Firestore txns require ALL reads before ANY writes.
        // Doing `txn.get()` after `txn.update()` raises a non-FirebaseException
        // JS error that doesn't get caught by `on FirebaseException`. The
        // user-facing symptom was a generic "Dart exception thrown from
        // converted Future" — useless. Both reads happen up front now.
        final snap = await txn.get(pingRef);
        if (!snap.exists) return;
        final pnmSnap = await txn.get(pnmRef);

        final live = Ping.fromDoc(snap);
        final myClaim = live.claimFor(pnm.uid);
        if (myClaim == null) return;
        if (myClaim.isCompleted) return; // idempotent guard

        final now = DateTime.now();
        final updated = live.claims
            .map((c) => c.pnmUid == pnm.uid
                ? c.copyWith(photoUrl: url, completedAt: now)
                : c)
            .toList();

        final allDone = updated.every((c) => c.isCompleted);
        final patch = <String, dynamic>{
          'claims': updated.map((c) => c.toMap()).toList(),
        };
        if (allDone) {
          patch['status'] = PingStatus.completed.storageValue;
          patch['completedAt'] = Timestamp.fromDate(now);
        }
        txn.update(pingRef, patch);

        final currentCompleted =
            (pnmSnap.data()?['completedPings'] as num?)?.toInt() ?? 0;
        txn.update(pnmRef, {'completedPings': currentCompleted + 1});
      });
    } on FirebaseException catch (e, st) {
      debugPrint('submitProof txn FirebaseException: '
          'code=${e.code} message=${e.message}\n$st');
      throw Exception(
          'Could not record completion (${e.code}): ${e.message ?? e.code}. '
          'If this says permission-denied, redeploy Firestore rules.');
    } catch (e, st) {
      debugPrint('submitProof txn unknown: $e\n$st');
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Reads
  // ---------------------------------------------------------------------------

  /// Every ping in the collection. Used by the active-side map + bulletin.
  /// At MVP chapter sizes (<100 pings) the bandwidth cost is trivial. Add a
  /// `where('status', '!=', 'completed')` filter or a TTL purge if it grows.
  Stream<List<Ping>> watchAllPings() {
    return _pings.snapshots().map((qs) {
      final pings = qs.docs.map(Ping.fromDoc).toList();
      pings.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return pings;
    });
  }

  /// Pings authored by [activeUid]. Used by "my activity" pane on ActiveHome.
  Stream<List<Ping>> watchPingsCreatedBy(String activeUid) {
    return _pings
        .where('createdBy', isEqualTo: activeUid)
        .snapshots()
        .map((qs) {
      final pings = qs.docs.map(Ping.fromDoc).toList();
      pings.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return pings;
    });
  }

  /// All pings a PNM is **authorised** to read: either `visibility == 'all'`
  /// OR `visibility == 'specific'` with their uid in the eligible list.
  ///
  /// Why two queries instead of one `snapshots()`? Firestore evaluates read
  /// rules against the *query's filters*, not post-fetch. An unfiltered
  /// `.snapshots()` on `/pings` can't satisfy "visibility in {all, specific
  /// where I'm listed}" from the filters alone, so the whole query is
  /// rejected and the stream silently emits []. Splitting into two scoped
  /// queries — each fully decidable from its `.where(...)` clauses — is the
  /// Firestore-canonical fix. Results are merged/deduped here.
  Stream<List<Ping>> _watchPingsVisibleToPnm(String pnmUid) {
    final allVisible = _pings
        .where('visibility', isEqualTo: PingVisibility.all.storageValue)
        .snapshots()
        .map((qs) => qs.docs.map(Ping.fromDoc).toList());
    final targetedAtMe = _pings
        .where('visibility',
            isEqualTo: PingVisibility.specific.storageValue)
        .where('eligiblePnmUids', arrayContains: pnmUid)
        .snapshots()
        .map((qs) => qs.docs.map(Ping.fromDoc).toList());
    return _mergePingStreams([allVisible, targetedAtMe]);
  }

  /// Pings the PNM is currently allowed to see AND can still act on.
  /// Layered on top of [_watchPingsVisibleToPnm], which respects rules.
  Stream<List<Ping>> watchAvailablePingsForPnm(String pnmUid) {
    return _watchPingsVisibleToPnm(pnmUid).map((list) {
      return list.where((p) {
        if (p.status == PingStatus.completed) return false;
        if (p.status == PingStatus.cancelled) return false;
        if (p.hasClaimFrom(pnmUid)) return true; // in-progress stays visible
        return p.claims.length < p.capacity;
      }).toList();
    });
  }

  /// All pings the PNM has claimed (in-progress or done).
  Stream<List<Ping>> watchMyClaimedPings(String pnmUid) {
    return _watchPingsVisibleToPnm(pnmUid)
        .map((list) => list.where((p) => p.hasClaimFrom(pnmUid)).toList());
  }

  /// Every completed ping in the chapter, regardless of original visibility.
  /// Backed by `where('status', '==', 'completed')` — that filter is enough
  /// to satisfy the "completed pings are public" branch of the read rule,
  /// so PNMs who weren't in the original eligibility list can still read
  /// the doc here. Used by the shared HistoryScreen.
  Stream<List<Ping>> watchCompletedPings() {
    return _pings
        .where('status', isEqualTo: PingStatus.completed.storageValue)
        .snapshots()
        .map((qs) {
      final pings = qs.docs.map(Ping.fromDoc).toList();
      pings.sort((a, b) {
        final at = a.completedAt ?? a.createdAt;
        final bt = b.completedAt ?? b.createdAt;
        return bt.compareTo(at);
      });
      return pings;
    });
  }

  Stream<Ping?> watchPing(String pingId) {
    return _pings.doc(pingId).snapshots().map((s) {
      if (!s.exists) return null;
      return Ping.fromDoc(s);
    });
  }
}

/// Combines N ping streams into a single sorted, deduped stream. Emits each
/// time any source emits, but only once every source has emitted at least
/// once — otherwise a slow Firestore query would make the union flicker.
/// Dedupes by `Ping.id` so a ping that somehow appears in both queries (e.g.
/// a data race while publishing changes visibility) isn't double-counted.
Stream<List<Ping>> _mergePingStreams(List<Stream<List<Ping>>> sources) {
  final controller = StreamController<List<Ping>>.broadcast();
  final latest = List<List<Ping>>.filled(sources.length, const <Ping>[]);
  final seen = List<bool>.filled(sources.length, false);
  final subs = <StreamSubscription>[];

  void emit() {
    if (!seen.every((s) => s)) return;
    final byId = <String, Ping>{};
    for (final list in latest) {
      for (final p in list) {
        byId[p.id] = p;
      }
    }
    final merged = byId.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    controller.add(merged);
  }

  for (var i = 0; i < sources.length; i++) {
    final idx = i;
    subs.add(sources[i].listen(
      (v) {
        latest[idx] = v;
        seen[idx] = true;
        emit();
      },
      onError: controller.addError,
    ));
  }
  controller.onCancel = () async {
    for (final s in subs) {
      await s.cancel();
    }
  };
  return controller.stream;
}
