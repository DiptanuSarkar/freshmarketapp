class UserProfile {
  const UserProfile({
    required this.id,
    required this.email,
    this.phone,
    required this.fullName,
    this.avatarUrl,
    this.dateOfBirth,
    this.isActive = true,
  });

  final String id;
  final String email;
  final String? phone;
  final String fullName;
  final String? avatarUrl;
  final DateTime? dateOfBirth;
  final bool isActive;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      email: json['email'] as String? ?? '',
      phone: json['phone'] as String?,
      fullName: json['full_name'] as String? ?? 'Fresh Customer',
      avatarUrl: json['avatar_url'] as String?,
      dateOfBirth: json['date_of_birth'] != null
          ? DateTime.tryParse(json['date_of_birth'].toString())
          : null,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toUpdateJson() {
    return {
      'full_name': fullName,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      if (dateOfBirth != null)
        'date_of_birth': dateOfBirth!.toIso8601String().substring(0, 10),
    };
  }

  UserProfile copyWith({
    String? fullName,
    String? avatarUrl,
    DateTime? dateOfBirth,
    String? phone,
  }) {
    return UserProfile(
      id: id,
      email: email,
      phone: phone ?? this.phone,
      fullName: fullName ?? this.fullName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      isActive: isActive,
    );
  }
}
