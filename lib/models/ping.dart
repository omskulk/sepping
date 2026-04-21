import 'package:cloud_firestore/cloud_firestore.dart';

/// Where in the ping lifecycle this doc currently sits.
///
/// - [draft]: created by an active but not yet visible to PNMs. Sits on the
///   active-only bulletin. Creator can still edit `capacity`, `creditCostPer`,
///   and `taskDescription`. Credits were debited at drop.
/// - [all]: published to the entire PNM pool. Anyone who is a PNM can accept.
/// - [specific]: published only to the PNMs listed in `eligiblePnmUids`. Shown
///   in a dedicated "Just for you" section on the PNM side.
enum PingVisibility {
  draft,
  all,
  specific;

  String get storageValue => name;

  static PingVisibility fromString(String? v) =>
      PingVisibility.values.firstWhere((e) => e.storageValue == v,
          orElse: () => PingVisibility.draft);
}

/// Overall ping status (aggregated from claims + publication state).
///
/// - [open]: has at least one free slot OR still a draft.
/// - [full]: `claims.length == capacity`; no more PNMs can accept, but proof
///   hasn't been submitted for every claim yet.
/// - [completed]: every claim has a `photoUrl`.
/// - [cancelled]: creator withdrew (not implemented in v1 but reserved).
enum PingStatus {
  open,
  full,
  completed,
  cancelled;

  String get label => switch (this) {
        PingStatus.open => 'Open',
        PingStatus.full => 'Full',
        PingStatus.completed => 'Completed',
        PingStatus.cancelled => 'Cancelled',
      };

  String get storageValue => name;

  static PingStatus fromString(String? v) => PingStatus.values
      .firstWhere((e) => e.storageValue == v, orElse: () => PingStatus.open);
}

/// A single PNM's stake in a ping. Stored as an element of the `claims` array
/// on the parent ping doc (not its own collection) so a read-modify-write
/// transaction on the ping is all that's needed to mutate slots — no extra
/// subcollection fan-out.
class PingClaim {
  final String pnmUid;
  final String pnmName;
  final DateTime acceptedAt;
  final String? photoUrl;
  final DateTime? completedAt;

  const PingClaim({
    required this.pnmUid,
    required this.pnmName,
    required this.acceptedAt,
    required this.photoUrl,
    required this.completedAt,
  });

  bool get isCompleted => photoUrl != null && completedAt != null;

  Map<String, dynamic> toMap() => {
        'pnmUid': pnmUid,
        'pnmName': pnmName,
        'acceptedAt': Timestamp.fromDate(acceptedAt),
        'photoUrl': photoUrl,
        'completedAt':
            completedAt == null ? null : Timestamp.fromDate(completedAt!),
      };

  factory PingClaim.fromMap(Map<String, dynamic> m) => PingClaim(
        pnmUid: m['pnmUid'] as String? ?? '',
        pnmName: m['pnmName'] as String? ?? '',
        acceptedAt:
            (m['acceptedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        photoUrl: m['photoUrl'] as String?,
        completedAt: (m['completedAt'] as Timestamp?)?.toDate(),
      );

  PingClaim copyWith({String? photoUrl, DateTime? completedAt}) => PingClaim(
        pnmUid: pnmUid,
        pnmName: pnmName,
        acceptedAt: acceptedAt,
        photoUrl: photoUrl ?? this.photoUrl,
        completedAt: completedAt ?? this.completedAt,
      );
}

/// Top-level ping document. One ping = one task that between 1 and [capacity]
/// PNMs can complete. See `docs/PING_REDESIGN.md` for the lifecycle diagram.
class Ping {
  final String id;
  final String createdBy;
  final String createdByName;
  final double lat;
  final double lng;
  final String taskDescription;
  final int creditCostPer;
  final int capacity;
  final PingVisibility visibility;
  final List<String> eligiblePnmUids;
  final List<PingClaim> claims;
  final PingStatus status;
  final DateTime createdAt;
  final DateTime? publishedAt;
  final DateTime? completedAt;

  const Ping({
    required this.id,
    required this.createdBy,
    required this.createdByName,
    required this.lat,
    required this.lng,
    required this.taskDescription,
    required this.creditCostPer,
    required this.capacity,
    required this.visibility,
    required this.eligiblePnmUids,
    required this.claims,
    required this.status,
    required this.createdAt,
    required this.publishedAt,
    required this.completedAt,
  });

  int get totalCost => creditCostPer * capacity;
  int get slotsRemaining => (capacity - claims.length).clamp(0, capacity);
  bool get isDraft => visibility == PingVisibility.draft;
  bool get isPublished => visibility != PingVisibility.draft;
  bool hasClaimFrom(String pnmUid) =>
      claims.any((c) => c.pnmUid == pnmUid);
  PingClaim? claimFor(String pnmUid) =>
      claims.where((c) => c.pnmUid == pnmUid).cast<PingClaim?>().firstWhere(
            (_) => true,
            orElse: () => null,
          );

  /// Can this PNM see this ping? (Actives see everything; security rules
  /// also enforce this — but the same predicate is needed client-side to
  /// drive map/sidebar filtering.)
  bool isEligibleForPnm(String pnmUid) {
    if (isDraft) return false;
    if (visibility == PingVisibility.all) return true;
    return eligiblePnmUids.contains(pnmUid);
  }

  factory Ping.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    final claimsRaw = (d['claims'] as List?) ?? const [];
    return Ping(
      id: doc.id,
      createdBy: d['createdBy'] as String? ?? '',
      createdByName: d['createdByName'] as String? ?? '',
      lat: (d['lat'] as num?)?.toDouble() ?? 0,
      lng: (d['lng'] as num?)?.toDouble() ?? 0,
      taskDescription: d['taskDescription'] as String? ?? '',
      creditCostPer: (d['creditCostPer'] as num?)?.toInt() ?? 1,
      capacity: (d['capacity'] as num?)?.toInt() ?? 1,
      visibility: PingVisibility.fromString(d['visibility'] as String?),
      eligiblePnmUids: ((d['eligiblePnmUids'] as List?) ?? const [])
          .cast<String>()
          .toList(),
      claims: claimsRaw
          .cast<Map<String, dynamic>>()
          .map(PingClaim.fromMap)
          .toList(),
      status: PingStatus.fromString(d['status'] as String?),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      publishedAt: (d['publishedAt'] as Timestamp?)?.toDate(),
      completedAt: (d['completedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toDoc() => {
        'createdBy': createdBy,
        'createdByName': createdByName,
        'lat': lat,
        'lng': lng,
        'taskDescription': taskDescription,
        'creditCostPer': creditCostPer,
        'capacity': capacity,
        'visibility': visibility.storageValue,
        'eligiblePnmUids': eligiblePnmUids,
        'claims': claims.map((c) => c.toMap()).toList(),
        'status': status.storageValue,
        'createdAt': Timestamp.fromDate(createdAt),
        'publishedAt':
            publishedAt == null ? null : Timestamp.fromDate(publishedAt!),
        'completedAt':
            completedAt == null ? null : Timestamp.fromDate(completedAt!),
      };
}
