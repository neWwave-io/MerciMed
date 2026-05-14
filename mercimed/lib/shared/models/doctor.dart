class Doctor {
  final String id;
  final String? hospitalId;
  final String name;
  final String? specialty;
  final String? phone;
  final DateTime createdAt;

  const Doctor({
    required this.id,
    this.hospitalId,
    required this.name,
    this.specialty,
    this.phone,
    required this.createdAt,
  });

  factory Doctor.fromJson(Map<String, dynamic> json) => Doctor(
        id: json['id'] as String,
        hospitalId: json['hospital_id'] as String?,
        name: json['name'] as String,
        specialty: json['specialty'] as String?,
        phone: json['phone'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'hospital_id': hospitalId,
        'name': name,
        'specialty': specialty,
        'phone': phone,
        'created_at': createdAt.toIso8601String(),
      };
}
