class Profile {
  final String id;
  final String? email;
  final String? fullName;
  final DateTime? dateOfBirth;
  final String? gender;
  final String? phone;
  final String? avatarUrl;
  final DateTime createdAt;

  const Profile({
    required this.id,
    this.email,
    this.fullName,
    this.dateOfBirth,
    this.gender,
    this.phone,
    this.avatarUrl,
    required this.createdAt,
  });

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        id: json['id'] as String,
        email: json['email'] as String?,
        fullName: json['full_name'] as String?,
        dateOfBirth: json['date_of_birth'] != null
            ? DateTime.parse(json['date_of_birth'] as String)
            : null,
        gender: json['gender'] as String?,
        phone: json['phone'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'full_name': fullName,
        'date_of_birth': dateOfBirth?.toIso8601String().split('T').first,
        'gender': gender,
        'phone': phone,
        'avatar_url': avatarUrl,
        'created_at': createdAt.toIso8601String(),
      };

  Profile copyWith({
    String? email,
    String? fullName,
    DateTime? dateOfBirth,
    String? gender,
    String? phone,
    String? avatarUrl,
  }) =>
      Profile(
        id: id,
        email: email ?? this.email,
        fullName: fullName ?? this.fullName,
        dateOfBirth: dateOfBirth ?? this.dateOfBirth,
        gender: gender ?? this.gender,
        phone: phone ?? this.phone,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        createdAt: createdAt,
      );
}
