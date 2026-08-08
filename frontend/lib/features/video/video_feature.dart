/// Video feature — Phase 4.2.
///
/// Complete AI video generation and playback system including:
///   - Luma AI Dream Machine integration (mock for dev)
///   - Inline video player with controls
///   - Video generation request UI with prompt builder
///   - Background status polling with exponential backoff
///   - Status tracking and notifications
library;

// Models
export 'models/video_model.dart';

// Services
export 'services/video_api_service.dart';
export 'services/video_status_poller.dart';

// Providers
export 'providers/video_provider.dart';

// Widgets
export 'widgets/video_player_widget.dart';
export 'widgets/video_generation_sheet.dart';
export 'widgets/video_status_badge.dart';
