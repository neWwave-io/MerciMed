class Hospital {
  final String id;
  final String name;
  final String? address;
  final String? phone;
  final List<String> specialties;
  final DateTime createdAt;

  // Extended directory fields (added for the OCIC partner-hospitals section).
  // All optional so older rows still parse cleanly.
  final String? telegramHandle;
  final String? messengerUrl;
  final String? website;
  final String? logoUrl;
  final bool isOcicAffiliated;
  final double? latitude;
  final double? longitude;
  final String? khmerName;

  const Hospital({
    required this.id,
    required this.name,
    this.address,
    this.phone,
    required this.specialties,
    required this.createdAt,
    this.telegramHandle,
    this.messengerUrl,
    this.website,
    this.logoUrl,
    this.isOcicAffiliated = false,
    this.latitude,
    this.longitude,
    this.khmerName,
  });

  factory Hospital.fromJson(Map<String, dynamic> json) => Hospital(
        id: json['id'] as String,
        name: json['name'] as String,
        address: json['address'] as String?,
        phone: json['phone'] as String?,
        specialties:
            (json['specialties'] as List<dynamic>?)?.cast<String>() ?? const [],
        createdAt: DateTime.parse(json['created_at'] as String),
        telegramHandle: json['telegram_handle'] as String?,
        messengerUrl: json['messenger_url'] as String?,
        website: json['website'] as String?,
        logoUrl: json['logo_url'] as String?,
        isOcicAffiliated: (json['is_ocic_affiliated'] as bool?) ?? false,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        khmerName: json['khmer_name'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'address': address,
        'phone': phone,
        'specialties': specialties,
        'created_at': createdAt.toIso8601String(),
        'telegram_handle': telegramHandle,
        'messenger_url': messengerUrl,
        'website': website,
        'logo_url': logoUrl,
        'is_ocic_affiliated': isOcicAffiliated,
        'latitude': latitude,
        'longitude': longitude,
        'khmer_name': khmerName,
      };
}
