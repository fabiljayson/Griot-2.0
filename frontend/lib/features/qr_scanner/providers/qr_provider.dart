import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/qr_api_service.dart';

/// State for QR scanner operations.
class QrScannerState {
  const QrScannerState({
    this.isScanning = false,
    this.scannedArtifact,
    this.recentScans = const [],
    this.errorMessage,
    this.isLoading = false,
  });

  final bool isScanning;
  final ArtifactModel? scannedArtifact;
  final List<ArtifactModel> recentScans;
  final String? errorMessage;
  final bool isLoading;

  QrScannerState copyWith({
    bool? isScanning,
    ArtifactModel? scannedArtifact,
    List<ArtifactModel>? recentScans,
    String? errorMessage,
    bool? isLoading,
    bool clearArtifact = false,
    bool clearError = false,
  }) {
    return QrScannerState(
      isScanning: isScanning ?? this.isScanning,
      scannedArtifact: clearArtifact
          ? null
          : (scannedArtifact ?? this.scannedArtifact),
      recentScans: recentScans ?? this.recentScans,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

/// Notifier for QR scanner state management.
class QrScannerNotifier extends StateNotifier<QrScannerState> {
  QrScannerNotifier()
    : _apiService = QrApiService.instance,
      super(const QrScannerState());

  final QrApiService _apiService;

  /// Process a scanned QR code URL.
  Future<void> processScannedUrl(String url) async {
    state = state.copyWith(isScanning: true, clearError: true);

    try {
      final artifact = await _apiService.handleScannedUrl(url);

      if (artifact != null) {
        // Record the scan
        await _apiService.recordScan(
          artifactSlug: artifact.slug,
          deviceType: 'mobile',
        );

        state = state.copyWith(
          isScanning: false,
          scannedArtifact: artifact,
          recentScans: [
            artifact,
            ...state.recentScans.where((a) => a.id != artifact.id),
          ].take(10).toList(),
        );
      } else {
        state = state.copyWith(
          isScanning: false,
          errorMessage: 'No artifact found for this QR code',
        );
      }
    } catch (e) {
      state = state.copyWith(
        isScanning: false,
        errorMessage: 'Failed to process QR code: $e',
      );
    }
  }

  /// Look up an artifact by slug.
  Future<void> lookupArtifact(String slug) async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final artifact = await _apiService.getArtifact(slug);
      state = state.copyWith(isLoading: false, scannedArtifact: artifact);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Artifact not found: $e',
      );
    }
  }

  /// Clear the current scanned artifact.
  void clearScan() {
    state = state.copyWith(clearArtifact: true, clearError: true);
  }

  /// Clear error message.
  void clearError() {
    state = state.copyWith(clearError: true);
  }
}

/// QR scanner provider.
final qrScannerProvider =
    StateNotifierProvider<QrScannerNotifier, QrScannerState>((ref) {
      return QrScannerNotifier();
    });

/// Artifact detail provider (for deep link navigation).
final artifactDetailProvider = FutureProvider.family<ArtifactModel?, String>((
  ref,
  slug,
) async {
  final apiService = QrApiService.instance;
  try {
    return await apiService.getArtifact(slug);
  } catch (_) {
    return null;
  }
});
