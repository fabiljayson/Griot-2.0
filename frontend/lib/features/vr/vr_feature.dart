/// VR feature — launch the Unity VR application from an artifact page.
///
/// The phone never renders the scene. It asks the backend for a single-use
/// launch token, validates the `griotvr://` link it gets back, and hands it to
/// the Unity application, which then talks to the API on its own. Nothing
/// secret travels in the link, and nothing about the scene lives in this app.
library;

// Constants & deep-link grammar
export 'vr_constants.dart';

// Models
export 'models/vr_launch_ticket.dart';

// Services
export 'services/vr_api_service.dart';
export 'services/vr_launcher.dart';

// Providers
export 'providers/vr_provider.dart';

// Widgets
export 'widgets/explore_in_vr_button.dart';
