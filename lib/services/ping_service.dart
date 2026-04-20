import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/app_user.dart';
import '../models/ping.dart';

class InsufficientCreditsException implements Exception {
  final int have;
  final int need;
  InsufficientCreditsException(this.have, this.need);
  @override
  String toString() => 'Not enough ping credits (have $have, need $need).';
}

class PingService {
  PingService({FirebaseFirestore? firestore, FirebaseStorage? storage})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  CollectionReference<Map<String, dynamic>> get _pings => _firestore.collection('pings');
  CollectionReference<Map<String, dynamic>> get _users => _firestore.collection('users');

  /// Atomically: check active's credits, decrement them, create the ping.
  /// Client-side transaction is acceptable for MVP. A malicious client could
  /// bypass this by editing code, so tightening requires a Cloud Function.
  Future<Ping> dropPing({
    required AppUser active,
    required AppUser assignee,
    required double lat,
    required double lng,
    required String taskDescription,
    required int creditCost,
  }) async {
    final newPingRef = _pings.doc();
    final activeRef = _users.doc(active.uid);

    final created = await _firestore.runTransaction<Ping>((txn) async {
      final activeSnap = await txn.get(activeRef);
      final currentCredits = (activeSnap.data()?['pingCredits'] as num?)?.toInt() ?? 0;
      if (currentCredits < creditCost) {
        throw InsufficientCreditsException(currentCredits, creditCost);
      }

      final ping = Ping(
        id: newPingRef.id,
        createdBy: active.uid,
        createdByName: active.displayName,
        assignedTo: assignee.uid,
        assignedToName: assignee.displayName,
        lat: lat,
        lng: lng,
        taskDescription: taskDescription,
        creditCost: creditCost,
        status: PingStatus.pending,
        photoUrl: null,
        createdAt: DateTime.now(),
        completedAt: null,
      );

      txn.set(newPingRef, ping.toDoc());
      txn.update(activeRef, {'pingCredits': currentCredits - creditCost});
      return ping;
    });

    return created;
  }

  Stream<List<Ping>> watchPingsAssignedTo(String pnmUid) {
    return _pings
        .where('assignedTo', isEqualTo: pnmUid)
        .snapshots()
        .map((qs) {
      final pings = qs.docs.map(Ping.fromDoc).toList();
      pings.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return pings;
    });
  }

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

  Stream<Ping?> watchPing(String pingId) {
    return _pings.doc(pingId).snapshots().map((s) {
      if (!s.exists) return null;
      return Ping.fromDoc(s);
    });
  }

  /// Uploads the photo, then atomically updates ping status and increments
  /// the PNM's completedPings counter for the leaderboard.
  Future<void> submitProof({
    required Ping ping,
    required Uint8List photoBytes,
    required String contentType,
  }) async {
    final ref = _storage.ref('pings/${ping.id}/proof');
    final uploadTask = await ref.putData(
      photoBytes,
      SettableMetadata(contentType: contentType),
    );
    final url = await uploadTask.ref.getDownloadURL();

    final pingRef = _pings.doc(ping.id);
    final pnmRef = _users.doc(ping.assignedTo);

    await _firestore.runTransaction((txn) async {
      final pingSnap = await txn.get(pingRef);
      final currentStatus = PingStatus.fromString(pingSnap.data()?['status'] as String?);
      if (currentStatus == PingStatus.completed) return;

      final pnmSnap = await txn.get(pnmRef);
      final currentCompleted = (pnmSnap.data()?['completedPings'] as num?)?.toInt() ?? 0;

      txn.update(pingRef, {
        'status': PingStatus.completed.storageValue,
        'photoUrl': url,
        'completedAt': Timestamp.fromDate(DateTime.now()),
      });
      txn.update(pnmRef, {'completedPings': currentCompleted + 1});
    });
  }
}
