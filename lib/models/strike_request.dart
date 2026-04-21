import 'package:cloud_firestore/cloud_firestore.dart';

enum StrikeRequestStatus {
  pending,
  approved,
  denied;

  String get label => switch (this) {
        StrikeRequestStatus.pending => 'Pending',
        StrikeRequestStatus.approved => 'Approved',
        StrikeRequestStatus.denied => 'Denied',
      };

  String get storageValue => name;

  static StrikeRequestStatus fromString(String? value) {
    return StrikeRequestStatus.values.firstWhere(
      (s) => s.storageValue == value,
      orElse: () => StrikeRequestStatus.pending,
    );
  }
}

/// A request from any active to strike one or more PNMs with a shared reason.
/// An NME reviews these in the approvals inbox; on approval the request fans
/// out into individual /strikes documents (one per PNM).
///
/// Multi-PNM requests can be partially approved — the NME ticks which PNMs to
/// strike at approval time, and the request stores the final approved subset.
class StrikeRequest {
  final String id;
  final List<String> pnmUids;
  final List<String> pnmNames; // parallel to pnmUids; cached for display
  final String reason;
  final String issuedBy; // active uid
  final String issuedByName;
  final StrikeRequestStatus status;
  final List<String> approvedPnmUids; // subset of pnmUids; populated on approve
  final String? reviewedBy; // NME uid
  final String? reviewedByName;
  final DateTime createdAt;
  final DateTime? reviewedAt;
  final String? denyReason; // optional NME explanation when status=denied

  const StrikeRequest({
    required this.id,
    required this.pnmUids,
    required this.pnmNames,
    required this.reason,
    required this.issuedBy,
    required this.issuedByName,
    required this.status,
    required this.approvedPnmUids,
    required this.reviewedBy,
    required this.reviewedByName,
    required this.createdAt,
    required this.reviewedAt,
    required this.denyReason,
  });

  bool get isPending => status == StrikeRequestStatus.pending;

  factory StrikeRequest.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return StrikeRequest(
      id: doc.id,
      pnmUids: (d['pnmUids'] as List?)?.cast<String>() ?? const [],
      pnmNames: (d['pnmNames'] as List?)?.cast<String>() ?? const [],
      reason: d['reason'] as String? ?? '',
      issuedBy: d['issuedBy'] as String? ?? '',
      issuedByName: d['issuedByName'] as String? ?? '',
      status: StrikeRequestStatus.fromString(d['status'] as String?),
      approvedPnmUids:
          (d['approvedPnmUids'] as List?)?.cast<String>() ?? const [],
      reviewedBy: d['reviewedBy'] as String?,
      reviewedByName: d['reviewedByName'] as String?,
      createdAt:
          (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      reviewedAt: (d['reviewedAt'] as Timestamp?)?.toDate(),
      denyReason: d['denyReason'] as String?,
    );
  }

  Map<String, dynamic> toDoc() => {
        'pnmUids': pnmUids,
        'pnmNames': pnmNames,
        'reason': reason,
        'issuedBy': issuedBy,
        'issuedByName': issuedByName,
        'status': status.storageValue,
        'approvedPnmUids': approvedPnmUids,
        'reviewedBy': reviewedBy,
        'reviewedByName': reviewedByName,
        'createdAt': Timestamp.fromDate(createdAt),
        'reviewedAt':
            reviewedAt == null ? null : Timestamp.fromDate(reviewedAt!),
        'denyReason': denyReason,
      };
}
