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

    test('the compiled-in number is itself valid', () {
      // Guards against a bad --dart-define shipping a number that
      // openFeedback would then refuse to launch.
      expect(
        AppConstants.isValidWhatsAppNumber(AppConstants.feedbackWhatsAppNumber),
        isTrue,
      );
    });
  });

  group('AppConstants.isValidWhatsAppNumber', () {
    test('accepts E.164 numbers with and without a plus', () {
      expect(AppConstants.isValidWhatsAppNumber('237692996791'), isTrue);
      expect(AppConstants.isValidWhatsAppNumber('+237692996791'), isTrue);
      expect(AppConstants.isValidWhatsAppNumber('+14155552671'), isTrue);
    });

    test('trims surrounding whitespace before checking', () {
      expect(AppConstants.isValidWhatsAppNumber('  237692996791  '), isTrue);
      // A --dart-define sourced from a shell variable or a .env file often
      // carries a trailing newline; that is a formatting accident, not an
      // attempt to rewrite the URL, so it is tolerated.
      expect(AppConstants.isValidWhatsAppNumber('237692996791\n'), isTrue);
    });

    // The number is interpolated into a wa.me URL, so a value carrying URL
    // structure would rewrite the link's host or path instead of its segment.
    test('rejects characters that would rewrite the URL', () {
      for (final bad in [
        '237692996791/../../admin',
        '237692996791?text=spoofed',
        '237692996791#fragment',
        'evil.com/237692996791',
        '237 692 996 791',
        '237-692-996-791',
        "237692996791'",
      ]) {
        expect(
          AppConstants.isValidWhatsAppNumber(bad),
          isFalse,
          reason: 'expected "$bad" to be rejected',
        );
      }
    });

    test('rejects empty and too-short or too-long values', () {
      expect(AppConstants.isValidWhatsAppNumber(''), isFalse);
      expect(AppConstants.isValidWhatsAppNumber('1234567'), isFalse); // 7
      expect(AppConstants.isValidWhatsAppNumber('1' * 16), isFalse); // 16
      expect(AppConstants.isValidWhatsAppNumber('1' * 15), isTrue);
    });
  });
}