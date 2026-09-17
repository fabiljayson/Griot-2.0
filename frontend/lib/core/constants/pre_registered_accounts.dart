/// Pre-registered test accounts for the Griot AI platform.
///
/// These accounts are pre-configured in the database and can be used
/// for testing and demonstration purposes. They work offline and will
/// sync to the server when connectivity is restored.
class PreRegisteredAccounts {
  PreRegisteredAccounts._();

  /// All pre-registered accounts.
  static const List<PreRegisteredAccount> accounts = [
    // Visitor accounts
    PreRegisteredAccount(
      username: 'visitor1',
      email: 'visitor1@griot-ai.com',
      password: 'Visitor123!',
      firstName: 'Amara',
      lastName: 'Nkomo',
      role: 'visitor',
      description: 'Explorer mode visitor account',
    ),
    PreRegisteredAccount(
      username: 'visitor2',
      email: 'visitor2@griot-ai.com',
      password: 'Visitor123!',
      firstName: 'Kofi',
      lastName: 'Asante',
      role: 'visitor',
      description: 'Explorer mode visitor account',
    ),
    PreRegisteredAccount(
      username: 'visitor3',
      email: 'visitor3@griot-ai.com',
      password: 'Visitor123!',
      firstName: 'Fatima',
      lastName: 'Diallo',
      role: 'visitor',
      description: 'Explorer mode visitor account',
    ),

    // Contributor accounts
    PreRegisteredAccount(
      username: 'contributor1',
      email: 'contributor1@griot-ai.com',
      password: 'Contributor123!',
      firstName: 'Nana',
      lastName: 'Yemo',
      role: 'contributor',
      description: 'Storyteller contributor account',
    ),
    PreRegisteredAccount(
      username: 'contributor2',
      email: 'contributor2@griot-ai.com',
      password: 'Contributor123!',
      firstName: 'Ama',
      lastName: 'Ata',
      role: 'contributor',
      description: 'Storyteller contributor account',
    ),
    PreRegisteredAccount(
      username: 'griot_ama',
      email: 'griot@griot-ai.com',
      password: 'Griot2024!',
      firstName: 'Ama',
      lastName: 'Ata',
      role: 'contributor',
      description: 'Featured griot contributor',
    ),

    // Institution Manager accounts
    PreRegisteredAccount(
      username: 'manager1',
      email: 'manager1@griot-ai.com',
      password: 'Manager123!',
      firstName: 'Jean',
      lastName: 'Moulin',
      role: 'institution_manager',
      institution: 'National Museum of Cameroon',
      description: 'Museum curator account',
    ),
    PreRegisteredAccount(
      username: 'museum_bamoun',
      email: 'bamoun@griot-ai.com',
      password: 'Bamoun2024!',
      firstName: 'Sultan',
      lastName: 'Ibrahim',
      role: 'institution_manager',
      institution: 'Bamoun Palace Museum',
      description: 'Bamoun museum curator',
    ),

    // Admin accounts
    PreRegisteredAccount(
      username: 'admin',
      email: 'admin@griot-ai.com',
      password: 'Admin2024!',
      firstName: 'Super',
      lastName: 'Admin',
      role: 'admin',
      description: 'Full administrator access',
    ),
    PreRegisteredAccount(
      username: 'admin_test',
      email: 'admin.test@griot-ai.com',
      password: 'TestAdmin123!',
      firstName: 'Test',
      lastName: 'Administrator',
      role: 'admin',
      description: 'Test administrator account',
    ),
  ];

  /// Get all accounts for a specific role.
  static List<PreRegisteredAccount> getAccountsByRole(String role) {
    return accounts.where((account) => account.role == role).toList();
  }

  /// Get account by username.
  static PreRegisteredAccount? getAccountByUsername(String username) {
    try {
      return accounts.firstWhere((account) => account.username == username);
    } catch (_) {
      return null;
    }
  }

  /// Get all visitor accounts.
  static List<PreRegisteredAccount> get visitorAccounts =>
      getAccountsByRole('visitor');

  /// Get all contributor accounts.
  static List<PreRegisteredAccount> get contributorAccounts =>
      getAccountsByRole('contributor');

  /// Get all institution manager accounts.
  static List<PreRegisteredAccount> get managerAccounts =>
      getAccountsByRole('institution_manager');

  /// Get all admin accounts.
  static List<PreRegisteredAccount> get adminAccounts =>
      getAccountsByRole('admin');
}

/// A pre-registered account with credentials.
class PreRegisteredAccount {
  const PreRegisteredAccount({
    required this.username,
    required this.email,
    required this.password,
    required this.firstName,
    required this.lastName,
    required this.role,
    this.institution = '',
    required this.description,
  });

  final String username;
  final String email;
  final String password;
  final String firstName;
  final String lastName;
  final String role;
  final String institution;
  final String description;

  /// Display name combining first and last name.
  String get displayName => '$firstName $lastName';

  /// Role display label.
  String get roleLabel {
    switch (role) {
      case 'visitor':
        return 'Visitor (Explorer Mode)';
      case 'contributor':
        return 'Contributor (Storyteller)';
      case 'institution_manager':
        return 'Institution Manager (Curator)';
      case 'admin':
        return 'Administrator';
      default:
        return role;
    }
  }

  /// Convert to a map for registration.
  Map<String, dynamic> toRegistrationMap() => {
        'username': username,
        'email': email,
        'password': password,
        'first_name': firstName,
        'last_name': lastName,
        'role': role,
        if (institution.isNotEmpty) 'institution': institution,
      };
}
