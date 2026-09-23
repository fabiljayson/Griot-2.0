import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/debug/debug_log.dart';

/// Composes and opens WhatsApp feedback messages to the Griot AI developer.
abstract final class WhatsAppFeedbackService {
  /// Deep link that opens a WhatsApp chat with [number] and pre-fills
  /// [message] in the compose box.
  ///
  /// Left pure so it can be unit-tested without a device or platform channel.
  static String composeUrl({
    required String number,
    required String message,
  }) =>
      'https://wa.me/$number?text=${Uri.encodeComponent(message)}';

  /// Opens WhatsApp with the default feedback draft pre-filled.
  ///
  /// Returns `false` when no app on the device can handle the link.
  static Future<bool> openDefaultFeedback() => openFeedback(
        number: AppConstants.feedbackWhatsAppNumber,
        message: AppConstants.feedbackWhatsAppDraft,
      );

  /// Opens WhatsApp with [message] pre-filled for [number].
  static Future<bool> openFeedback({
    required String number,
    required String message,
  }) async {
    final uri = Uri.parse(composeUrl(number: number, message: message));
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugLog('[WhatsAppFeedbackService] launch failed: $e');
      return false;
    }
  }
}