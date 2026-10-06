import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:griot_ai/features/vr/models/vr_launch_ticket.dart';
import 'package:griot_ai/features/vr/providers/vr_provider.dart';
import 'package:griot_ai/features/vr/services/vr_api_service.dart';
import 'package:griot_ai/features/vr/services/vr_launcher.dart';

class _MockVrApiService extends Mock implements VrApiService {}

const _token = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

VrLaunchTicket _ticket({String? deepLink}) => VrLaunchTicket.fromJson({
  'token': _token,
  'deep_link': deepLink ?? 'griotvr://launch?token=$_token&experience=42&artifact=108',
  'expires_at': '2099-01-01T00:00:00Z',
  'expires_in': 120,
  'experience': {'id': 42, 'slug': 'bamoun-heritage-gallery', 'title': 'Bamoun'},
  'artifact': {'id': 108, 'slug': 'traditional-mask'},
});

DioException _dioError({
  required int statusCode,
  String? code,
  String? message,
  DioExceptionType type = DioExceptionType.badResponse,
}) {
  final options = RequestOptions(path: '/api/vr/launch/');
  return DioException(
    requestOptions: options,
    type: type,
    response: Response<Map<String, dynamic>>(
      requestOptions: options,
      statusCode: statusCode,
      data: {'error': ?message, 'code': ?code},
    ),
  );
}

void main() {
  late _MockVrApiService api;
  late List<Uri> opened;

  VrLaunchController build({VrLaunchOutcome outcome = VrLaunchOutcome.launched}) {
    return VrLaunchController(
      api: api,
      launcher: VrLauncher(
        canLaunch: (_) async => outcome != VrLaunchOutcome.notInstalled,
        open: (uri) async {
          opened.add(uri);
          return outcome == VrLaunchOutcome.launched;
        },
      ),
    );
  }

  setUp(() {
    api = _MockVrApiService();
    opened = [];
  });

  test('mints a token then opens the rebuilt, validated link', () async {
    when(() => api.requestLaunch(artifact: any(named: 'artifact')))
        .thenAnswer((_) async => _ticket());
    final controller = build();

    final state = await controller.launchForArtifact('traditional-mask');

    expect(state.status, VrLaunchStatus.idle);
    expect(state.experienceId, 42);
    expect(opened, hasLength(1));
    final uri = opened.single;
    expect(uri.scheme, 'griotvr');
    expect(uri.host, 'launch');
    expect(uri.queryParameters['token'], _token);
    expect(uri.queryParameters['experience'], '42');
    expect(uri.queryParameters['artifact'], '108');
  });

  test('asks the API for the artifact the reader tapped', () async {
    when(() => api.requestLaunch(artifact: any(named: 'artifact')))
        .thenAnswer((_) async => _ticket());
    final controller = build();

    await controller.launchForArtifact('traditional-mask');

    verify(() => api.requestLaunch(artifact: 'traditional-mask')).called(1);
  });

  test('reports a missing VR application and never opens anything', () async {
    when(() => api.requestLaunch(artifact: any(named: 'artifact')))
        .thenAnswer((_) async => _ticket());
    final controller = build(outcome: VrLaunchOutcome.notInstalled);

    final state = await controller.launchForArtifact('traditional-mask');

    expect(state.status, VrLaunchStatus.notInstalled);
    expect(state.message, VrLaunchController.notInstalledMessage);
    expect(opened, isEmpty);
  });

  test('explains an artifact that is not in any scene', () async {
    when(() => api.requestLaunch(artifact: any(named: 'artifact'))).thenThrow(
      _dioError(statusCode: 404, code: 'no_vr_experience'),
    );
    final controller = build();

    final state = await controller.launchForArtifact('lonely-stool');

    expect(state.status, VrLaunchStatus.error);
    expect(state.message, "This artifact isn't available in VR yet.");
    expect(opened, isEmpty);
  });

  test('explains an ambiguous artifact instead of picking a scene', () async {
    when(() => api.requestLaunch(artifact: any(named: 'artifact'))).thenThrow(
      _dioError(statusCode: 409, code: 'experience_ambiguous'),
    );
    final controller = build();

    final state = await controller.launchForArtifact('traditional-mask');

    expect(state.status, VrLaunchStatus.error);
    expect(state.message, contains('more than one VR experience'));
  });

  test('asks the reader to sign in when the session has lapsed', () async {
    when(() => api.requestLaunch(artifact: any(named: 'artifact')))
        .thenThrow(_dioError(statusCode: 401));
    final controller = build();

    final state = await controller.launchForArtifact('traditional-mask');

    expect(state.message, 'Sign in to explore this artifact in VR.');
  });

  test('tells the reader VR needs a connection when offline', () async {
    when(() => api.requestLaunch(artifact: any(named: 'artifact'))).thenThrow(
      _dioError(statusCode: 0, type: DioExceptionType.connectionError),
    );
    final controller = build();

    final state = await controller.launchForArtifact('traditional-mask');

    expect(state.message, contains('needs a connection'));
    expect(opened, isEmpty);
  });

  test('refuses a ticket whose link is not a launch link', () async {
    when(() => api.requestLaunch(artifact: any(named: 'artifact')))
        .thenAnswer((_) async => _ticket(deepLink: 'https://evil.example.org/x'));
    final controller = build();

    final state = await controller.launchForArtifact('traditional-mask');

    expect(state.status, VrLaunchStatus.error);
    expect(opened, isEmpty);
  });

  test('refuses an expired ticket rather than opening a dead link', () async {
    when(() => api.requestLaunch(artifact: any(named: 'artifact'))).thenAnswer(
      (_) async => VrLaunchTicket.fromJson({
        'token': _token,
        'deep_link': 'griotvr://launch?token=$_token&experience=42',
        'expires_at': '2020-01-01T00:00:00Z',
        'expires_in': 0,
        'experience': {'id': 42},
      }),
    );
    final controller = build();

    final state = await controller.launchForArtifact('traditional-mask');

    expect(state.status, VrLaunchStatus.error);
    expect(opened, isEmpty);
  });

  test('a second tap while launching does not mint a second token', () async {
    when(() => api.requestLaunch(artifact: any(named: 'artifact')))
        .thenAnswer((_) async => _ticket());
    final controller = build();

    final first = controller.launchForArtifact('traditional-mask');
    final second = controller.launchForArtifact('traditional-mask');
    await Future.wait([first, second]);

    verify(() => api.requestLaunch(artifact: 'traditional-mask')).called(1);
    expect(opened, hasLength(1));
  });

  test('clears a previous message so a retry can fail the same way again', () async {
    when(() => api.requestLaunch(artifact: any(named: 'artifact'))).thenThrow(
      _dioError(statusCode: 404, code: 'no_vr_experience'),
    );
    final controller = build();
    await controller.launchForArtifact('lonely-stool');
    expect(controller.state.hasMessage, isTrue);

    controller.clearMessage();

    expect(controller.state.hasMessage, isFalse);
    expect(controller.state.status, VrLaunchStatus.error);
  });

  test('launches an experience directly when one is named', () async {
    when(() => api.requestLaunch(experience: any(named: 'experience')))
        .thenAnswer((_) async => _ticket());
    final controller = build();

    await controller.launchExperience('bamoun-heritage-gallery');

    verify(() => api.requestLaunch(experience: 'bamoun-heritage-gallery')).called(1);
  });
}
