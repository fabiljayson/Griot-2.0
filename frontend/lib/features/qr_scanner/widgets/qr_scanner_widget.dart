import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/theme/app_colors.dart';
import '../providers/qr_provider.dart';
import '../services/qr_api_service.dart';

/// Full-screen QR code scanner with traditional African border motif overlay.
///
/// Features:
///   - Camera-based QR scanning
///   - Traditional decorative border overlay
///   - Flash toggle
///   - Manual URL input fallback
///   - Scan result handling
class QrScannerScreen extends ConsumerStatefulWidget {
  const QrScannerScreen({super.key});

  static Future<ArtifactModel?> show(BuildContext context) {
    return Navigator.of(context).push<ArtifactModel>(
      MaterialPageRoute(
        builder: (_) => const QrScannerScreen(),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  ConsumerState<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends ConsumerState<QrScannerScreen>
    with SingleTickerProviderStateMixin {
  MobileScannerController? _scannerController;
  bool _isFlashOn = false;
  bool _isProcessing = false;
  late AnimationController _animationController;
  late Animation<double> _scanLineAnimation;

  @override
  void initState() {
    super.initState();
    _initScanner();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _scanLineAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  void _initScanner() {
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
  }

  @override
  void dispose() {
    _scannerController?.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;

    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    final url = barcode.rawValue!;
    setState(() => _isProcessing = true);

    // Process the scanned URL
    ref.read(qrScannerProvider.notifier).processScannedUrl(url);
  }

  void _toggleFlash() {
    _scannerController?.toggleTorch();
    setState(() => _isFlashOn = !_isFlashOn);
  }

  void _showManualInput() {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter Artifact URL'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'https://africanteller.org/artifact/...',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final url = controller.text.trim();
              if (url.isNotEmpty) {
                Navigator.pop(context);
                ref.read(qrScannerProvider.notifier).processScannedUrl(url);
              }
            },
            child: const Text('Look Up'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scannerState = ref.watch(qrScannerProvider);

    // Handle scan result — pop with artifact
    ref.listen<QrScannerState>(qrScannerProvider, (prev, next) {
      if (next.scannedArtifact != null && prev?.scannedArtifact == null) {
        Navigator.of(context).pop(next.scannedArtifact);
      }
    });

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan QR Code'),
        actions: [
          IconButton(
            icon: Icon(
              _isFlashOn ? Icons.flash_on : Icons.flash_off,
              color: _isFlashOn ? AppColors.ochre : Colors.white,
            ),
            onPressed: _toggleFlash,
          ),
          IconButton(
            icon: const Icon(Icons.keyboard),
            onPressed: _showManualInput,
            tooltip: 'Enter URL manually',
          ),
        ],
      ),
      body: Stack(
        children: [
          // Camera preview
          if (_scannerController != null)
            MobileScanner(controller: _scannerController!, onDetect: _onDetect),

          // Scan overlay with traditional border motif
          CustomPaint(
            painter: _ScanOverlayPainter(scanAnimation: _scanLineAnimation),
            size: Size.infinite,
          ),

          // Processing indicator
          if (_isProcessing || scannerState.isScanning)
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                    color: AppColors.terracotta,
                    strokeWidth: 3,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Looking up artifact...',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

          // Error message
          if (scannerState.errorMessage != null)
            Positioned(
              bottom: 100,
              left: 24,
              right: 24,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  scannerState.errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ),

          // Bottom instruction text
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Point camera at museum artifact QR code',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom painter for the scan overlay with traditional African border motif.
class _ScanOverlayPainter extends CustomPainter {
  _ScanOverlayPainter({required this.scanAnimation})
    : super(repaint: scanAnimation);

  final Animation<double> scanAnimation;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    // Semi-transparent overlay
    final overlayPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.6)
      ..style = PaintingStyle.fill;

    final scanAreaSize = size.width * 0.7;
    final scanArea = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: scanAreaSize,
      height: scanAreaSize,
    );

    // Draw overlay with cutout
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRect(scanArea)
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, overlayPaint);

    // Draw corner brackets (traditional motif)
    final bracketLength = scanAreaSize * 0.15;
    paint.color = AppColors.terracotta;
    paint.strokeCap = StrokeCap.round;

    // Top-left
    canvas.drawLine(
      scanArea.topLeft,
      scanArea.topLeft + Offset(bracketLength, 0),
      paint,
    );
    canvas.drawLine(
      scanArea.topLeft,
      scanArea.topLeft + Offset(0, bracketLength),
      paint,
    );

    // Top-right
    canvas.drawLine(
      scanArea.topRight,
      scanArea.topRight - Offset(bracketLength, 0),
      paint,
    );
    canvas.drawLine(
      scanArea.topRight,
      scanArea.topRight + Offset(0, bracketLength),
      paint,
    );

    // Bottom-left
    canvas.drawLine(
      scanArea.bottomLeft,
      scanArea.bottomLeft + Offset(bracketLength, 0),
      paint,
    );
    canvas.drawLine(
      scanArea.bottomLeft,
      scanArea.bottomLeft - Offset(0, bracketLength),
      paint,
    );

    // Bottom-right
    canvas.drawLine(
      scanArea.bottomRight,
      scanArea.bottomRight - Offset(bracketLength, 0),
      paint,
    );
    canvas.drawLine(
      scanArea.bottomRight,
      scanArea.bottomRight - Offset(0, bracketLength),
      paint,
    );

    // Draw animated scan line
    final scanLineY = scanArea.top + (scanArea.height * scanAnimation.value);
    final scanLinePaint = Paint()
      ..shader =
          LinearGradient(
            colors: [
              AppColors.terracotta.withValues(alpha: 0),
              AppColors.terracotta,
              AppColors.terracotta.withValues(alpha: 0),
            ],
          ).createShader(
            Rect.fromLTWH(scanArea.left, scanLineY, scanArea.width, 2),
          );

    canvas.drawLine(
      Offset(scanArea.left + 8, scanLineY),
      Offset(scanArea.right - 8, scanLineY),
      scanLinePaint..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _ScanOverlayPainter oldDelegate) => true;
}
