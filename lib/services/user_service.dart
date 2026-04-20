import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';

class UserService {
  UserService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _users => _firestore.collection('users');

  Stream<AppUser?> watchUser(String uid) {
    return _users.doc(uid).snapshots().map((snap) {
      if (!snap.exists) return null;
      return AppUser.fromDoc(snap);
    });
  }

  Future<AppUser?> getUser(String uid) async {
    final snap = await _users.doc(uid).get();
    if (!snap.exists) return null;
    return AppUser.fromDoc(snap);
  }

  Stream<List<AppUser>> watchPnms() {
    return _users
        .where('role', isEqualTo: UserRole.pnm.storageValue)
        .snapshots()
        .map((qs) => qs.docs.map(AppUser.fromDoc).toList()
          ..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase())));
  }

  /// Leaderboard: PNMs sorted by completedPings desc. Sort client-side so we don't
  /// need a composite Firestore index for a small chapter-sized collection.
  Stream<List<AppUser>> watchLeaderboard() {
    return _users
        .where('role', isEqualTo: UserRole.pnm.storageValue)
        .snapshots()
        .map((qs) {
      final users = qs.docs.map(AppUser.fromDoc).toList();
      users.sort((a, b) => b.completedPings.compareTo(a.completedPings));
      return users;
    });
  }
}
