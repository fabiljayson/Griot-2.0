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
  ///
  /// [number] is validated before it is placed in the URL. The value is
  /// interpolated into a `wa.me` link, so a string containing `?`, `#` or `/`
  /// would silently rewrite the URL's structure — turning a mistyped build
  /// constant into a request to a different host or path. Rejecting it here is
  /// cheaper than debugging that.
  static Future<bool> openFeedback({
    required String number,
    required String message,
  }) async {
    if (!AppConstants.isValidWhatsAppNumber(number)) {
      debugLog(
        '[WhatsAppFeedbackService] refusing to open feedback: '
        '"$number" is not a valid E.164 number',
      );
      return false;
    }

    final uri = Uri.parse(composeUrl(number: number.trim(), message: message));
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugLog('[WhatsAppFeedbackService] launch failed: $e');
      return false;
    }
  }
}