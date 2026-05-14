class Profile {
  final String id;
  final String? fullName;
  final DateTime? dateOfBirth;
  final String? gender;
  final String? phone;
  final DateTime createdAt;

  const Profile({
    required this.id,
    this.fullName,
    this.dateOfBirth,
    this.gender,
    this.phone,
    required this.createdAt,
  });

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        id: json['id'] as String,
        fullName: json['full_name'] as String?,
        dateOfBirth: json['date_of_birth'] != null
            ? DateTime.parse(json['date_of_birth'] as String)
            : null,
        gender: json['gender'] as String?,
        phone: json['phone'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'full_name': fullName,
        'date_of_birth': dateOfBirth?.toIso8601String().split('T').first,
        'gender': gender,
        'phone': phone,
        'created_at': createdAt.toIso8601String(),
      };

  Profile copyWith({
    String? fullName,
    DateTime? dateOfBirth,
    String? gender,
    String? phone,
  }) =>
      Profile(
        id: id,
        fullName: fullName ?? this.fullName,
        dateOfBirth: dateOfBirth ?? this.dateOfBirth,
        gender: gender ?? this.gender,
        phone: phone ?? this.phone,
        createdAt: createdAt,
      );
}
