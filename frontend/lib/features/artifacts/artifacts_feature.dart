/// Artifacts feature — museum object catalogue.
///
/// The artifact model (`ArtifactModel`), API service (`QrApiService`) and detail
/// screen already existed but nothing ever presented them: `listArtifacts()` had
/// zero callers and the QR scanner had no entry point. This feature adds the
/// catalogue screen, its provider and its card so the webapp's Artifacts
/// destination has a mobile equivalent.
library;

// Providers
export 'providers/artifacts_provider.dart';

// Widgets
export 'widgets/artifact_card.dart';

// Screens
export 'screens/artifacts_screen.dart';
