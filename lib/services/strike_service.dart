import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';
import '../models/strike.dart';
import '../models/strike_request.dart';

/// All strike workflow plumbing in one place. The two-tier flow is:
///
///   1. Any active calls [submitRequest] with one or more PNMs and a shared
///      reason. A /strikeRequests doc is created with status=pending.
///   2. The NME opens the approvals inbox ([watchPendingRequests]) and either
///      [approveRequest] (which fans out to /strikes and increments each PNM's
///      strikes counter) or [denyRequest] (which only flips status).
///   3. The NME can later [amendStrike] (rewrite the reason, audit-preserved)
///      or [removeStrike] (soft-delete; counter decrements).
class StrikeService {
  StrikeService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _requests =>
      _firestore.collection('strikeRequests');
  CollectionReference<Map<String, dynamic>> get _strikes =>
      _firestore.collection('strikes');
  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  // ---------- Submission (any active) ----------

  /// Files a strike request. [pnms] must be non-empty; [reason] is the shared
  /// justification shown to the NME.
  Future<StrikeRequest> submitRequest({
    required AppUser issuer,
    required List<AppUser> pnms,
    required String reason,
  }) async {
    if (pnms.isEmpty) {
      throw ArgumentError('At least one PNM required.');
    }
    if (reason.trim().isEmpty) {
      throw ArgumentError('Reason required.');
    }
    final ref = _requests.doc();
    final req = StrikeRequest(
      id: ref.id,
      pnmUids: pnms.map((p) => p.uid).toList(),
      pnmNames: pnms.map((p) => p.displayName).toList(),
      reason: reason.trim(),
      issuedBy: issuer.uid,
      issuedByName: issuer.displayName,
      status: StrikeRequestStatus.pending,
      approvedPnmUids: const [],
      reviewedBy: null,
      reviewedByName: null,
      createdAt: DateTime.now(),
      reviewedAt: null,
      denyReason: null,
    );
    await ref.set(req.toDoc());
    return req;
  }

  // ---------- Approval inbox (NME) ----------

  Stream<List<StrikeRequest>> watchPendingRequests() {
    return _requests
        .where('status', isEqualTo: StrikeRequestStatus.pending.storageValue)
        .snapshots()
        .map((qs) {
      final list = qs.docs.map(StrikeRequest.fromDoc).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  /// All requests an active has filed (history view, optional).
  Stream<List<StrikeRequest>> watchRequestsByIssuer(String issuerUid) {
    return _requests
        .where('issuedBy', isEqualTo: issuerUid)
        .snapshots()
        .map((qs) {
      final list = qs.docs.map(StrikeRequest.fromDoc).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  /// NME approves a request. [approvedPnmUids] must be a subset of the request's
  /// [pnmUids] — the NME may have unticked some PNMs. Atomically:
  ///   - flips request status to approved
  ///   - creates one /strikes doc per approved PNM
  ///   - increments each approved PNM's users.strikes counter
  Future<void> approveRequest({
    required StrikeRequest request,
    required AppUser nme,
    required Set<String> approvedPnmUids,
  }) async {
    if (!nme.isNme) {
      throw StateError('Only the NME can approve strike requests.');
    }
    if (request.status != StrikeRequestStatus.pending) {
      throw StateError('Request is no longer pending.');
    }
    final approved = approvedPnmUids
        .where((uid) => request.pnmUids.contains(uid))
        .toList();
    if (approved.isEmpty) {
      throw ArgumentError(
          'Approve at least one PNM, or use denyRequest to reject the whole request.');
    }

    await _firestore.runTransaction((txn) async {
      // Re-read to guard against double-approve races.
      final reqRef = _requests.doc(request.id);
      final reqSnap = await txn.get(reqRef);
      final currentStatus = StrikeRequestStatus.fromString(
          reqSnap.data()?['status'] as String?);
      if (currentStatus != StrikeRequestStatus.pending) {
        throw StateError('Request was already reviewed.');
      }

      // Pre-read every PNM in the approved set so we can increment their counters.
      final pnmRefs = {
        for (final uid in approved) uid: _users.doc(uid),
      };
      final pnmSnaps = <String, DocumentSnapshot<Map<String, dynamic>>>{};
      for (final uid in approved) {
        pnmSnaps[uid] = await txn.get(pnmRefs[uid]!);
      }

      // Build map uid -> name from the request (parallel arrays).
      final nameByUid = <String, String>{
        for (var i = 0; i < request.pnmUids.length; i++)
          request.pnmUids[i]:
              i < request.pnmNames.length ? request.pnmNames[i] : ''
      };

      final now = DateTime.now();

      // Fan out: one /strikes doc per approved PNM.
      for (final uid in approved) {
        final strikeRef = _strikes.doc();
        final strike = Strike(
          id: strikeRef.id,
          pnmUid: uid,
          pnmName: nameByUid[uid] ?? '',
          reason: request.reason,
          issuedBy: request.issuedBy,
          issuedByName: request.issuedByName,
          approvedBy: nme.uid,
          approvedByName: nme.displayName,
          requestId: request.id,
          createdAt: now,
        );
        txn.set(strikeRef, strike.toDoc());

        final currentStrikes =
            (pnmSnaps[uid]?.data()?['strikes'] as num?)?.toInt() ?? 0;
        txn.update(pnmRefs[uid]!, {'strikes': currentStrikes + 1});
      }

      txn.update(reqRef, {
        'status': StrikeRequestStatus.approved.storageValue,
        'approvedPnmUids': approved,
        'reviewedBy': nme.uid,
        'reviewedByName': nme.displayName,
        'reviewedAt': Timestamp.fromDate(now),
      });
    });
  }

  /// NME denies a request outright. No /strikes documents created.
  Future<void> denyRequest({
    required StrikeRequest request,
    required AppUser nme,
    String? denyReason,
  }) async {
    if (!nme.isNme) {
      throw StateError('Only the NME can deny strike requests.');
    }
    if (request.status != StrikeRequestStatus.pending) {
      throw StateError('Request is no longer pending.');
    }
    await _requests.doc(request.id).update({
      'status': StrikeRequestStatus.denied.storageValue,
      'reviewedBy': nme.uid,
      'reviewedByName': nme.displayName,
      'reviewedAt': Timestamp.fromDate(DateTime.now()),
      if (denyReason != null && denyReason.trim().isNotEmpty)
        'denyReason': denyReason.trim(),
    });
  }

  // ---------- Strike reads ----------

  /// All strikes against one PNM (used by the PNM's own "my strikes" view and
  /// by the active-side amendments screen).
  Stream<List<Strike>> watchStrikesForPnm(String pnmUid) {
    return _strikes
        .where('pnmUid', isEqualTo: pnmUid)
        .snapshots()
        .map((qs) {
      final list = qs.docs.map(Strike.fromDoc).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  /// Every strike across the chapter — drives the amendments screen list.
  Stream<List<Strike>> watchAllStrikes() {
    return _strikes.snapshots().map((qs) {
      final list = qs.docs.map(Strike.fromDoc).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  // ---------- Amendments (NME) ----------

  /// Rewrite a strike's reason. Original reason is preserved on the doc as
  /// `reason`; the new wording lives on `amendedReason` so the audit trail is
  /// intact.
  Future<void> amendStrike({
    required Strike strike,
    required AppUser nme,
    required String newReason,
  }) async {
    if (!nme.isNme) throw StateError('Only the NME can amend strikes.');
    if (newReason.trim().isEmpty) {
      throw ArgumentError('Amendment reason required.');
    }
    await _strikes.doc(strike.id).update({
      'amendedReason': newReason.trim(),
      'amendedBy': nme.uid,
      'amendedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  /// Soft-removes a strike: flips removed=true and decrements the PNM's
  /// strikes counter. The strike doc stays around for the audit log.
  Future<void> removeStrike({
    required Strike strike,
    required AppUser nme,
  }) async {
    if (!nme.isNme) throw StateError('Only the NME can remove strikes.');
    if (strike.removed) return; // idempotent
    await _firestore.runTransaction((txn) async {
      final strikeRef = _strikes.doc(strike.id);
      final pnmRef = _users.doc(strike.pnmUid);
      final strikeSnap = await txn.get(strikeRef);
      final alreadyRemoved =
          strikeSnap.data()?['removed'] as bool? ?? false;
      if (alreadyRemoved) return;
      final pnmSnap = await txn.get(pnmRef);
      final current = (pnmSnap.data()?['strikes'] as num?)?.toInt() ?? 0;
      txn.update(strikeRef, {'removed': true});
      txn.update(pnmRef, {'strikes': current > 0 ? current - 1 : 0});
    });
  }
}
