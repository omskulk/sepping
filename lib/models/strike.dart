import 'package:cloud_firestore/cloud_firestore.dart';

/// A finalized strike against a single PNM. Created when an NME approves a
/// StrikeRequest. One PNM-per-document, even if the parent request targeted
/// many — fan-out happens at approval time so we can amend or remove an
/// individual PNM's strike without touching the others.
class Strike {
  final String id;
  final String pnmUid;
  final String pnmName;
  final String reason;
  final String issuedBy; // active uid that filed the request
  final String issuedByName;
  final String approvedBy; // NME uid
  final String approvedByName;
  final String? requestId; // back-reference to the StrikeRequest, if any
  final DateTime createdAt;

  // Amendment fields. If non-null the strike has been edited at least once.
  final String? amendedReason;
  final String? amendedBy; // NME uid that performed the amendment
  final DateTime? amendedAt;
  // If true the strike has been struck-through (kept for audit, not counted).
  final bool removed;

  const Strike({
    required this.id,
    required this.pnmUid,
    required this.pnmName,
    required this.reason,
    required this.issuedBy,
    required this.issuedByName,
    required this.approvedBy,
    required this.approvedByName,
    required this.requestId,
    required this.createdAt,
    this.amendedReason,
    this.amendedBy,
    this.amendedAt,
    this.removed = false,
  });

  /// Effective reason: the amended one if present, else the original.
  String get effectiveReason => amendedReason ?? reason;
  bool get isAmended => amendedReason != null;

  factory Strike.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return Strike(
      id: doc.id,
      pnmUid: d['pnmUid'] as String? ?? '',
      pnmName: d['pnmName'] as String? ?? '',
      reason: d['reason'] as String? ?? '',
      issuedBy: d['issuedBy'] as String? ?? '',
      issuedByName: d['issuedByName'] as String? ?? '',
      approvedBy: d['approvedBy'] as String? ?? '',
      approvedByName: d['approvedByName'] as String? ?? '',
      requestId: d['requestId'] as String?,
      createdAt:
          (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      amendedReason: d['amendedReason'] as String?,
      amendedBy: d['amendedBy'] as String?,
      amendedAt: (d['amendedAt'] as Timestamp?)?.toDate(),
      removed: d['removed'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toDoc() => {
        'pnmUid': pnmUid,
        'pnmName': pnmName,
        'reason': reason,
        'issuedBy': issuedBy,
        'issuedByName': issuedByName,
        'approvedBy': approvedBy,
        'approvedByName': approvedByName,
        'requestId': requestId,
        'createdAt': Timestamp.fromDate(createdAt),
        'amendedReason': amendedReason,
        'amendedBy': amendedBy,
        'amendedAt': amendedAt == null ? null : Timestamp.fromDate(amendedAt!),
        'removed': removed,
      };
}
