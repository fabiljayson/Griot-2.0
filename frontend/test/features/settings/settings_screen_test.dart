import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:griot_ai/core/constants/app_constants.dart';
import 'package:griot_ai/features/settings/screens/settings_screen.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/method_channel_url_launcher.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// Records launched URLs instead of touching a real platform channel.
class _FakeUrlLauncher
    with MockPlatformInterfaceMixin
    implements UrlLauncherPlatform {
  final List<String> opened = [];
  bool succeed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
        '${invocation.memberName} is not stubbed',
      );

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    opened.add(url);
    return succeed;
  }
}

void main() {
  late _FakeUrlLauncher fakeLauncher;

  setUp(() {
    fakeLauncher = _FakeUrlLauncher();
    UrlLauncherPlatform.instance = fakeLauncher;
  });

  tearDown(() {
    UrlLauncherPlatform.instance = MethodChannelUrlLauncher();
  });

  Widget buildScreen() =>
      const MaterialApp(home: SettingsScreen());

  testWidgets('renders title and feedback tile', (tester) async {
    await tester.pumpWidget(buildScreen());

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Send Feedback via WhatsApp'), findsOneWidget);
  });

  testWidgets('feedback tile opens WhatsApp with the prefilled draft',
      (tester) async {
    await tester.pumpWidget(buildScreen());

    await tester.tap(find.text('Send Feedback via WhatsApp'));
    await tester.pumpAndSettle();

    expect(fakeLauncher.opened, hasLength(1));
    final url = Uri.parse(fakeLauncher.opened.single);
    expect(url.scheme, 'https');
    expect(url.host, 'wa.me');
    expect(url.path, '/${AppConstants.feedbackWhatsAppNumber}');
    expect(
      url.queryParameters['text'],
      AppConstants.feedbackWhatsAppDraft,
    );
    expect(url.queryParameters['text'], contains(AppConstants.developerName));
  });

  testWidgets('shows a snackbar when WhatsApp cannot be opened',
      (tester) async {
    fakeLauncher.succeed = false;
    await tester.pumpWidget(buildScreen());

    await tester.tap(find.text('Send Feedback via WhatsApp'));
    await tester.pump();

    expect(
      find.text('Could not open WhatsApp. Please try again.'),
      findsOneWidget,
    );
  });
}