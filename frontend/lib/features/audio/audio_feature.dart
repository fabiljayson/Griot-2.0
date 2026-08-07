/// Audio feature — Phase 4.1.
///
/// Complete audio player system including:
///   - Persistent sticky audio player sheet
///   - Variable playback speed (0.75x – 2.0x) + sleep timer
///   - Full-screen player view with controls
///   - Progress tracking and seek functionality
library;

// Models
export 'models/audio_model.dart';

// Services
export 'services/audio_player_service.dart';

// Providers
export 'providers/audio_provider.dart';

// Widgets
export 'widgets/audio_player_sheet.dart';