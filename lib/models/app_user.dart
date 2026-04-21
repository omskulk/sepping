import 'package:cloud_firestore/cloud_firestore.dart';

enum UserRole {
  active,
  pnm;

  String get label => switch (this) {
        UserRole.active => 'Active',
        UserRole.pnm => 'PNM',
      };

  String get storageValue => name;

  static UserRole fromString(String? value) {
    return UserRole.values.firstWhere(
      (r) => r.storageValue == value,
      orElse: () => UserRole.pnm,
    );
  }
}

class AppUser {
  final String uid;
  final String email;
  final String displayName;
  final UserRole role;
  final int pingCredits;
  final int completedPings;
  final int strikes;
  final bool isNme;
  final DateTime createdAt;

  const AppUser({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.role,
    required this.pingCredits,
    required this.completedPings,
    required this.strikes,
    required this.isNme,
    required this.createdAt,
  });

  bool get isActive => role == UserRole.active;
  bool get isPnm => role == UserRole.pnm;

  factory AppUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return AppUser(
      uid: doc.id,
      email: d['email'] as String? ?? '',
      displayName: d['displayName'] as String? ?? '',
      role: UserRole.fromString(d['role'] as String?),
      pingCredits: (d['pingCredits'] as num?)?.toInt() ?? 0,
      completedPings: (d['completedPings'] as num?)?.toInt() ?? 0,
      strikes: (d['strikes'] as num?)?.toInt() ?? 0,
      isNme: d['isNme'] as bool? ?? false,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toDoc() => {
        'email': email,
        'displayName': displayName,
        'role': role.storageValue,
        'pingCredits': pingCredits,
        'completedPings': completedPings,
        'strikes': strikes,
        'isNme': isNme,
        'createdAt': Timestamp.fromDate(createdAt),
      };
}
