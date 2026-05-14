class Relationship {
  final String id;
  final String requesterId;
  final String targetId;
  final String? relationshipType;
  final String status;
  final DateTime createdAt;

  const Relationship({
    required this.id,
    required this.requesterId,
    required this.targetId,
    this.relationshipType,
    required this.status,
    required this.createdAt,
  });

  factory Relationship.fromJson(Map<String, dynamic> json) => Relationship(
        id: json['id'] as String,
        requesterId: json['requester_id'] as String,
        targetId: json['target_id'] as String,
        relationshipType: json['relationship_type'] as String?,
        status: json['status'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'requester_id': requesterId,
        'target_id': targetId,
        'relationship_type': relationshipType,
        'status': status,
        'created_at': createdAt.toIso8601String(),
      };
}
