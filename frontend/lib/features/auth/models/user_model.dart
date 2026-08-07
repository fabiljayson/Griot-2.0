/// User model representing the authenticated user profile.
///
/// Mirrors the backend UserSerializer fields.
class UserModel {
  const UserModel({
    required this.id,
    required this.username,
    this.email = '',
    this.firstName = '',
    this.lastName = '',
    this.role = UserRole.visitor,
    this.institution = '',
    this.dateJoined = '',
  });

  final int id;
  final String username;
  final String email;
  final String firstName;
  final String lastName;
  final UserRole role;
  final String institution;
  final String dateJoined;

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as int? ?? 0,
      username: json['username'] as String? ?? '',
      email: json['email'] as String? ?? '',
      firstName: json['first_name'] as String? ?? '',
      lastName: json['last_name'] as String? ?? '',
      role: UserRole.fromString(json['role'] as String? ?? 'visitor'),
      institution: json['institution'] as String? ?? '',
      dateJoined: json['date_joined'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'email': email,
        'first_name': firstName,
        'last_name': lastName,
        'role': role.value,
        'institution': institution,
        'date_joined': dateJoined,
      };

  /// Display name for the user.
  String get displayName {
    if (firstName.isNotEmpty && lastName.isNotEmpty) {
      return '$firstName $lastName';
    }
    if (firstName.isNotEmpty) return firstName;
    return username;
  }

  /// Whether this user can submit stories.
  bool get canContribute =>
      role == UserRole.contributor ||
      role == UserRole.institutionManager ||
      role == UserRole.admin;

  UserModel copyWith({
    int? id,
    String? username,
    String? email,
    String? firstName,
    String? lastName,
    UserRole? role,
    String? institution,
    String? dateJoined,
  }) {
    return UserModel(
      id: id ?? this.id,
      username: username ?? this.username,
      email: email ?? this.email,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      role: role ?? this.role,
      institution: institution ?? this.institution,
      dateJoined: dateJoined ?? this.dateJoined,
    );
  }
}

/// Application-level user roles.
enum UserRole {
  visitor('visitor', 'Visitor', 'Explorer Mode', '🗺️'),
  contributor('contributor', 'Contributor', 'Storyteller', '✍️'),
  institutionManager('institution_manager', 'Institution Manager', 'Curator', '🏛️'),
  admin('admin', 'Admin', 'Administrator', '👑');

  const UserRole(this.value, this.label, this.modeName, this.emoji);

  final String value;
  final String label;
  final String modeName;
  final String emoji;

  factory UserRole.fromString(String value) {
    return UserRole.values.firstWhere(
      (r) => r.value == value,
      orElse: () => UserRole.visitor,
    );
  }
}

/// JWT token pair returned by the backend.
class TokenPair {
  const TokenPair({
    required this.accessToken,
    required this.refreshToken,
  });

  final String accessToken;
  final String refreshToken;

  factory TokenPair.fromJson(Map<String, dynamic> json) {
    return TokenPair(
      accessToken: json['access'] as String? ?? '',
      refreshToken: json['refresh'] as String? ?? '',
    );
  }
}
