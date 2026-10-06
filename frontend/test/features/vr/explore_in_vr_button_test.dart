import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:griot_ai/core/theme/app_theme.dart';
import 'package:griot_ai/features/vr/models/vr_launch_ticket.dart';
import 'package:griot_ai/features/vr/providers/vr_provider.dart';
import 'package:griot_ai/features/vr/services/vr_api_service.dart';
import 'package:griot_ai/features/vr/services/vr_launcher.dart';
import 'package:griot_ai/features/vr/widgets/explore_in_vr_button.dart';

class _MockVrApiService extends Mock implements VrApiService {}

const _token = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const _slug = 'royal-bamoun-throne';

VrLaunchTicket _ticket() => VrLaunchTicket.fromJson({
  'token': _token,
  'deep_link': 'griotvr://launch?token=$_token&experience=42&artifact=108',
  'expires_at': '2099-01-01T00:00:00Z',
  'expires_in': 120,
  'experience': {'id': 42, 'title': 'Bamoun Heritage Gallery'},
});

DioException _refusal(String code) {
  final options = RequestOptions(path: '/api/vr/launch/');
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response<Map<String, dynamic>>(
      requestOptions: options,
      statusCode: 404,
      data: {'error': 'Not available', 'code': code},
    ),
  );
}

void main() {
  late _MockVrApiService api;

  setUp(() {
    api = _MockVrApiService();
  });

  /// A launcher that reports [outcome] and records every URI it is handed.
  VrLauncher recordingLauncher(
    VrLaunchOutcome outcome, {
    List<Uri>? opened,
  }) {
    return VrLauncher(
      canLaunch: (_) async => outcome != VrLaunchOutcome.notInstalled,
      open: (uri) async {
        opened?.add(uri);
        return outcome == VrLaunchOutcome.launched;
      },
    );
  }

  Future<void> pumpSection(WidgetTester tester, VrLauncher launcher) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vrApiServiceProvider.overrideWithValue(api),
          vrLauncherProvider.overrideWithValue(launcher),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: SingleChildScrollView(
              child: ExploreInVrButton(artifactSlug: _slug),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('offers the button under the design-system section header', (
    tester,
  ) async {
    await pumpSection(tester, recordingLauncher(VrLaunchOutcome.launched));

    expect(find.text('Virtual Reality'), findsOneWidget);
    expect(find.text('Explore in VR'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('requests the artifact it was given and opens the rebuilt link', (
    tester,
  ) async {
    final opened = <Uri>[];
    when(() => api.requestLaunch(artifact: any(named: 'artifact')))
        .thenAnswer((_) async => _ticket());
    await pumpSection(
      tester,
      recordingLauncher(VrLaunchOutcome.launched, opened: opened),
    );

    await tester.tap(find.text('Explore in VR'));
    await tester.pumpAndSettle();

    verify(() => api.requestLaunch(artifact: _slug)).called(1);
    expect(opened, hasLength(1));
    expect(opened.single.scheme, 'griotvr');
    expect(opened.single.queryParameters['artifact'], '108');
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tells the reader when the VR application is not installed', (
    tester,
  ) async {
    when(() => api.requestLaunch(artifact: any(named: 'artifact')))
        .thenAnswer((_) async => _ticket());
    await pumpSection(tester, recordingLauncher(VrLaunchOutcome.notInstalled));

    await tester.tap(find.text('Explore in VR'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.text("VR experience isn't installed on this device."),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('surfaces a server refusal as copy the reader can act on', (
    tester,
  ) async {
    when(() => api.requestLaunch(artifact: any(named: 'artifact')))
        .thenThrow(_refusal('no_vr_experience'));
    await pumpSection(tester, recordingLauncher(VrLaunchOutcome.launched));

    await tester.tap(find.text('Explore in VR'));
    await tester.pumpAndSettle();

    expect(
      find.text("This artifact isn't available in VR yet."),
      findsOneWidget,
    );
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('does not crash when the API throws something unexpected', (
    tester,
  ) async {
    when(() => api.requestLaunch(artifact: any(named: 'artifact')))
        .thenThrow(StateError('boom'));
    await pumpSection(tester, recordingLauncher(VrLaunchOutcome.launched));

    await tester.tap(find.text('Explore in VR'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Could not prepare the VR experience'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
