import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_colors.dart';

/// Beautiful quote card widget for sharing story excerpts.
///
/// Can be exported as an image using RepaintBoundary.
class QuoteCard extends StatelessWidget {
  const QuoteCard({
    super.key,
    required this.quote,
    required this.attribution,
    this.moralLesson,
    this.backgroundColor = AppColors.parchment,
    this.textColor = AppColors.charcoal,
    this.accentColor = AppColors.terracotta,
    this.repaintKey,
  });

  final String quote;
  final String attribution;
  final String? moralLesson;
  final Color backgroundColor;
  final Color textColor;
  final Color accentColor;
  final GlobalKey? repaintKey;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: repaintKey,
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Decorative quote mark
            Text(
              '"',
              style: TextStyle(
                fontSize: 80,
                fontWeight: FontWeight.w700,
                color: accentColor.withValues(alpha: 0.3),
                height: 0.8,
              ),
            ),
            const SizedBox(height: 8),

            // Quote text
            Text(
              quote,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w500,
                color: textColor,
                height: 1.5,
                fontStyle: FontStyle.italic,
                fontFamilyFallback: ['Georgia', 'serif'],
              ),
            ),
            const SizedBox(height: 16),

            // Attribution
            Row(
              children: [
                Container(width: 40, height: 2, color: accentColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '— $attribution',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: textColor.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ],
            ),

            // Moral lesson (if provided)
            if (moralLesson != null && moralLesson!.isNotEmpty) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: accentColor.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lightbulb_outline, size: 18, color: accentColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        moralLesson!,
                        style: TextStyle(
                          fontSize: 12,
                          color: textColor.withValues(alpha: 0.8),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 20),

            // Branding
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'AFRICAN TELLER',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'africanteller.org',
                  style: TextStyle(
                    fontSize: 11,
                    color: textColor.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Capture the widget as an image.
  static Future<ByteData?> captureImage(GlobalKey key) async {
    try {
      final boundary =
          key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData;
    } catch (e) {
      return null;
    }
  }
}

/// Modal bottom sheet for generating and sharing quote cards.
class QuoteCardGenerator extends StatefulWidget {
  const QuoteCardGenerator({
    super.key,
    required this.quote,
    required this.attribution,
    this.moralLesson,
  });

  final String quote;
  final String attribution;
  final String? moralLesson;

  static Future<void> show(
    BuildContext context, {
    required String quote,
    required String attribution,
    String? moralLesson,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => QuoteCardGenerator(
        quote: quote,
        attribution: attribution,
        moralLesson: moralLesson,
      ),
    );
  }

  @override
  State<QuoteCardGenerator> createState() => _QuoteCardGeneratorState();
}

class _QuoteCardGeneratorState extends State<QuoteCardGenerator> {
  Color _selectedAccent = AppColors.terracotta;
  final _cardKey = GlobalKey();

  static const _accentColors = [
    AppColors.terracotta,
    AppColors.ochre,
    AppColors.savannahGreen,
    Color(0xFF4B0082),
    Color(0xFF8B4513),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: AppColors.parchment,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.charcoalMuted.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Text(
                  'Create Share Card',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),

          // Color picker
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Text('Accent: '),
                ..._accentColors.map((color) {
                  final isSelected = color == _selectedAccent;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedAccent = color),
                    child: Container(
                      width: 32,
                      height: 32,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? Colors.white : Colors.transparent,
                          width: 3,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: color.withValues(alpha: 0.5),
                                  blurRadius: 8,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Card preview
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: QuoteCard(
                repaintKey: _cardKey,
                quote: widget.quote,
                attribution: widget.attribution,
                moralLesson: widget.moralLesson,
                accentColor: _selectedAccent,
              ),
            ),
          ),

          // Share button
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: () => _shareCard(),
                icon: const Icon(Icons.share),
                label: const Text(
                  'Share Quote Card',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _selectedAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _shareCard() async {
    // Try to capture the card as an image
    final byteData = await QuoteCard.captureImage(_cardKey);

    if (byteData != null && mounted) {
      // Share the image bytes
      final buffer = byteData.buffer.asUint8List();
      // Create temp file for sharing
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/african_teller_quote.png');
      await file.writeAsBytes(buffer);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          text: '${widget.quote}\n\n— ${widget.attribution}\n\n#AfricanTeller',
        ),
      );
    } else {
      // Fallback to text share
      final shareText =
          '${widget.quote}\n\n— ${widget.attribution}\n\nDiscover more on African Teller: https://africanteller.org\n\n#AfricanTeller #Cameroon #CulturalHeritage';
      await SharePlus.instance.share(ShareParams(text: shareText));
    }

    if (mounted) {
      Navigator.pop(context);
    }
  }
}
