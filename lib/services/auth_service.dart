import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/app_user.dart';

class AuthService {
  AuthService({FirebaseAuth? auth, FirebaseFirestore? firestore})
      : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  static const int activeStartingCredits = 10;

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<void> signIn({required String email, required String password}) async {
    await _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
  }

  Future<void> signUp({
    required String email,
    required String password,
    required String displayName,
    required UserRole role,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final uid = cred.user!.uid;
    await cred.user!.updateDisplayName(displayName);

    final user = AppUser(
      uid: uid,
      email: email.trim(),
      displayName: displayName,
      role: role,
      pingCredits: role == UserRole.active ? activeStartingCredits : 0,
      completedPings: 0,
      strikes: 0,
      isNme: false,
      createdAt: DateTime.now(),
    );
    await _firestore.collection('users').doc(uid).set(user.toDoc());
  }

  Future<void> signOut() => _auth.signOut();

  /// Translate FirebaseAuthException codes into user-friendly strings.
  static String describeError(Object err) {
    if (err is FirebaseAuthException) {
      return switch (err.code) {
        'invalid-email' => 'Invalid email address.',
        'user-disabled' => 'This account has been disabled.',
        'user-not-found' || 'invalid-credential' => 'No account matches those credentials.',
        'wrong-password' => 'Wrong password.',
        'email-already-in-use' => 'An account already exists with that email.',
        'weak-password' => 'Password must be at least 6 characters.',
        _ => err.message ?? 'Authentication failed.',
      };
    }
    return err.toString();
  }
}
