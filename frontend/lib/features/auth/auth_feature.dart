/// Auth feature — Phase 2.
///
/// Complete authentication system including:
///   - Login / registration screens
///   - JWT token management with flutter_secure_storage
///   - Dio auth interceptor with automatic token refresh
///   - Role-based access (Explorer Mode vs Contributor Studio)
///   - Profile management and account deletion
library;

// Models
export 'models/user_model.dart';

// Providers
export 'providers/auth_provider.dart';

// Repositories
export 'repositories/auth_repository.dart';

// Screens
export 'screens/login_screen.dart';
export 'screens/profile_screen.dart';
export 'screens/register_screen.dart';

// Widgets
export 'widgets/auth_wrapper.dart';
export 'widgets/role_badge.dart';
