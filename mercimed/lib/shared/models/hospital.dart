class Hospital {
  final String id;
  final String name;
  final String? address;
  final String? phone;
  final List<String> specialties;
  final DateTime createdAt;

  const Hospital({
    required this.id,
    required this.name,
    this.address,
    this.phone,
    required this.specialties,
    required this.createdAt,
  });

  factory Hospital.fromJson(Map<String, dynamic> json) => Hospital(
        id: json['id'] as String,
        name: json['name'] as String,
        address: json['address'] as String?,
        phone: json['phone'] as String?,
        specialties:
            (json['specialties'] as List<dynamic>?)?.cast<String>() ?? [],
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'address': address,
        'phone': phone,
        'specialties': specialties,
        'created_at': createdAt.toIso8601String(),
      };
}
