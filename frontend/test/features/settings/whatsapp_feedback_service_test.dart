import 'package:flutter_test/flutter_test.dart';
import 'package:griot_ai/core/constants/app_constants.dart';
import 'package:griot_ai/features/settings/services/whatsapp_feedback_service.dart';

void main() {
  group('WhatsAppFeedbackService.composeUrl', () {
    test('builds a wa.me deep link for the number', () {
      final url = WhatsAppFeedbackService.composeUrl(
        number: '237692996791',
        message: 'Hello',
      );
      expect(url, 'https://wa.me/237692996791?text=Hello');
    });

    test('URL-encodes spaces and punctuation in the message', () {
      final url = WhatsAppFeedbackService.composeUrl(
        number: '237692996791',
        message: 'Bonjour! Comment ça va?',
      );
      expect(
        url,
        'https://wa.me/237692996791?text='
        'Bonjour!%20Comment%20%C3%A7a%20va%3F',
      );
    });

    test('encodes newlines so the draft keeps its structure', () {
      final url = WhatsAppFeedbackService.composeUrl(
        number: '237692996791',
        message: 'line1\nline2',
      );
      expect(url, contains('text=line1%0Aline2'));
    });
  });

  group('feedback constants', () {
    test('draft addresses the developer by name', () {
      expect(
        AppConstants.feedbackWhatsAppDraft,
        contains(AppConstants.developerName),
      );
    });

    test('targets the public feedback number', () {
      expect(AppConstants.feedbackWhatsAppNumber, '237692996791');
    });
  });
}