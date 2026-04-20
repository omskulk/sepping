import 'package:cloud_firestore/cloud_firestore.dart';

enum PingStatus {
  pending,
  completed;

  String get label => switch (this) {
        PingStatus.pending => 'Pending',
        PingStatus.completed => 'Completed',
      };

  String get storageValue => name;

  static PingStatus fromString(String? value) {
    return PingStatus.values.firstWhere(
      (s) => s.storageValue == value,
      orElse: () => PingStatus.pending,
    );
  }
}

class Ping {
  final String id;
  final String createdBy;
  final String createdByName;
  final String assignedTo;
  final String assignedToName;
  final double lat;
  final double lng;
  final String taskDescription;
  final int creditCost;
  final PingStatus status;
  final String? photoUrl;
  final DateTime createdAt;
  final DateTime? completedAt;

  const Ping({
    required this.id,
    required this.createdBy,
    required this.createdByName,
    required this.assignedTo,
    required this.assignedToName,
    required this.lat,
    required this.lng,
    required this.taskDescription,
    required this.creditCost,
    required this.status,
    required this.photoUrl,
    required this.createdAt,
    required this.completedAt,
  });

  factory Ping.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return Ping(
      id: doc.id,
      createdBy: d['createdBy'] as String? ?? '',
      createdByName: d['createdByName'] as String? ?? '',
      assignedTo: d['assignedTo'] as String? ?? '',
      assignedToName: d['assignedToName'] as String? ?? '',
      lat: (d['lat'] as num?)?.toDouble() ?? 0,
      lng: (d['lng'] as num?)?.toDouble() ?? 0,
      taskDescription: d['taskDescription'] as String? ?? '',
      creditCost: (d['creditCost'] as num?)?.toInt() ?? 1,
      status: PingStatus.fromString(d['status'] as String?),
      photoUrl: d['photoUrl'] as String?,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      completedAt: (d['completedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toDoc() => {
        'createdBy': createdBy,
        'createdByName': createdByName,
        'assignedTo': assignedTo,
        'assignedToName': assignedToName,
        'lat': lat,
        'lng': lng,
        'taskDescription': taskDescription,
        'creditCost': creditCost,
        'status': status.storageValue,
        'photoUrl': photoUrl,
        'createdAt': Timestamp.fromDate(createdAt),
        'completedAt': completedAt == null ? null : Timestamp.fromDate(completedAt!),
      };
}
