/// QR Scanner feature — Phase 5.2.
///
/// Complete museum artifact QR code scanning system including:
///   - In-app camera QR scanner with traditional border motif overlays
///   - Deep link handling for `https://africanteller.org/artifact/<slug>`
///   - Artifact lookup and detail views
///   - Scan tracking and analytics
///   - Manual URL input fallback
library;

// Models & Services
export 'services/qr_api_service.dart';

// Providers
export 'providers/qr_provider.dart';

// Widgets
export 'widgets/qr_scanner_widget.dart';

// Screens
export 'screens/artifact_detail_screen.dart';
