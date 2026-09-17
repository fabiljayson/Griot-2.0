/// A user registration that was created offline and will be synced when online.
///
/// This allows users to create accounts without internet connectivity.
/// The registration is stored locally and synced to the server when online.
class OfflineUser {
  const OfflineUser({
    this.id,
    required this.username,
    required this.email,
    required this.password,
    this.firstName = '',
    this.lastName = '',
    this.role = 'visitor',
    this.institution = '',
    this.createdAt,
    this.status = OfflineUserStatus.pending,
    this.serverUserId,
    this.errorMessage,
  });

  final int? id;
  final String username;
  final String email;
  final String password;
  final String firstName;
  final String lastName;
  final String role;
  final String institution;
  final DateTime? createdAt;
  final OfflineUserStatus status;
  final int? serverUserId;
  final String? errorMessage;

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'username': username,
        'email': email,
        'password': password,
        'first_name': firstName,
        'last_name': lastName,
        'role': role,
        'institution': institution,
        'created_at': createdAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
        'status': status.value,
        'server_user_id': serverUserId,
        'error_message': errorMessage,
      };

  factory OfflineUser.fromMap(Map<String, dynamic> map) => OfflineUser(
        id: map['id'] as int?,
        username: map['username'] as String,
        email: map['email'] as String,
        password: map['password'] as String,
        firstName: map['first_name'] as String? ?? '',
        lastName: map['last_name'] as String? ?? '',
        role: map['role'] as String? ?? 'visitor',
        institution: map['institution'] as String? ?? '',
        createdAt: map['created_at'] != null
            ? DateTime.parse(map['created_at'] as String)
            : null,
        status: OfflineUserStatus.fromString(map['status'] as String? ?? 'pending'),
        serverUserId: map['server_user_id'] as int?,
        errorMessage: map['error_message'] as String?,
      );

  OfflineUser copyWith({
    int? id,
    String? username,
    String? email,
    String? password,
    String? firstName,
    String? lastName,
    String? role,
    String? institution,
    DateTime? createdAt,
    OfflineUserStatus? status,
    int? serverUserId,
    String? errorMessage,
  }) =>
      OfflineUser(
        id: id ?? this.id,
        username: username ?? this.username,
        email: email ?? this.email,
        password: password ?? this.password,
        firstName: firstName ?? this.firstName,
        lastName: lastName ?? this.lastName,
        role: role ?? this.role,
        institution: institution ?? this.institution,
        createdAt: createdAt ?? this.createdAt,
        status: status ?? this.status,
        serverUserId: serverUserId ?? this.serverUserId,
        errorMessage: errorMessage ?? this.errorMessage,
      );

  bool get isPending => status == OfflineUserStatus.pending;
  bool get isSynced => status == OfflineUserStatus.synced;
  bool get isFailed => status == OfflineUserStatus.failed;
}

enum OfflineUserStatus {
  pending('pending'),
  syncing('syncing'),
  synced('synced'),
  failed('failed');

  const OfflineUserStatus(this.value);
  final String value;

  factory OfflineUserStatus.fromString(String value) {
    return OfflineUserStatus.values.firstWhere(
      (e) => e.value == value,
      orElse: () => OfflineUserStatus.pending,
    );
  }
}
