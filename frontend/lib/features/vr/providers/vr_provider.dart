import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/app_error.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/vr_launch_ticket.dart';
import '../services/vr_api_service.dart';
import '../services/vr_launcher.dart';
import '../vr_constants.dart';

/// Stage of a launch attempt.
enum VrLaunchStatus {
  idle,

  /// Asking the API for a launch token.
  requesting,

  /// Handing the link to Android.
  launching,

  /// No VR application on this device accepts the link.
  notInstalled,

  /// Something went wrong. [VrLaunchState.message] says what.
  error,
}

/// Immutable launch state for one screen.
@immutable
class VrLaunchState {
  const VrLaunchState({
    this.status = VrLaunchStatus.idle,
    this.message,
    this.experienceId,
  });

  final VrLaunchStatus status;

  /// User-facing explanation when [status] is [VrLaunchStatus.error] or
  /// [VrLaunchStatus.notInstalled]. Null when there is nothing to say.
  final String? message;

  /// Experience the last successful launch opened, for the caller's logging.
  final int? experienceId;

  bool get isBusy =>
      status == VrLaunchStatus.requesting || status == VrLaunchStatus.launching;

  bool get hasMessage => (message ?? '').isNotEmpty;

  VrLaunchState copyWith({
    VrLaunchStatus? status,
    String? message,
    int? experienceId,
    bool clearMessage = false,
  }) {
    return VrLaunchState(
      status: status ?? this.status,
      message: clearMessage ? null : (message ?? this.message),
      experienceId: experienceId ?? this.experienceId,
    );
  }
}

/// Drives one tap of "Explore in VR": request a token, then open Unity.
///
/// The whole flow is a single call from the widget's point of view and always
/// returns a terminal state, so the caller can show a message without holding a
/// listener open. Every failure path ends in a state with copy — the app must
/// never appear to do nothing, and it must never crash because a headset was
/// not plugged in.
class VrLaunchController extends StateNotifier<VrLaunchState> {
  VrLaunchController({required VrApiService api, required VrLauncher launcher})
    : _api = api,
      _launcher = launcher,
      super(const VrLaunchState());

  final VrApiService _api;
  final VrLauncher _launcher;

  /// Copy shown when no VR application is installed.
  static const String notInstalledMessage =
      "VR experience isn't installed on this device.";

  /// Request a launch token for [artifactSlug] and open the VR application.
  Future<VrLaunchState> launchForArtifact(String artifactSlug) =>
      _launch(() => _api.requestLaunch(artifact: artifactSlug));

  /// Request a launch token for an experience directly, by id or slug.
  Future<VrLaunchState> launchExperience(String experience) =>
      _launch(() => _api.requestLaunch(experience: experience));

  /// Clear the last message so a retry can fail with the same copy again.
  void clearMessage() {
    state = state.copyWith(clearMessage: true);
  }

  Future<VrLaunchState> _launch(
    Future<VrLaunchTicket> Function() request,
  ) async {
    // A second tap while a launch is in flight would mint a second token and
    // open a second copy of the scene. The button is disabled while busy; this
    // is the backstop for a fast double tap that lands before the rebuild.
    if (state.isBusy) return state;

    state = const VrLaunchState(status: VrLaunchStatus.requesting);

    final VrLaunchTicket ticket;
    try {
      ticket = await request();
    } on DioException catch (e) {
      return _fail(_messageForDio(e), status: VrLaunchStatus.error);
    } catch (e) {
      return _fail(
        'Could not prepare the VR experience. Please try again.',
        status: VrLaunchStatus.error,
      );
    }

    if (!ticket.isUsable) {
      return _fail(
        'The VR link could not be prepared. Please try again.',
        status: VrLaunchStatus.error,
      );
    }

    // Validate, then rebuild: the link is a string that becomes an Android
    // Intent, so only a link we constructed from checked parts is fired.
    final uri = VrDeepLink.parseAndValidate(ticket.deepLink);
    if (uri == null) {
      return _fail(
        'The VR link could not be prepared. Please try again.',
        status: VrLaunchStatus.error,
      );
    }

    state = const VrLaunchState(status: VrLaunchStatus.launching);

    final outcome = await _launcher.open(uri);
    switch (outcome) {
      case VrLaunchOutcome.launched:
        return state = VrLaunchState(experienceId: ticket.experience.id);
      case VrLaunchOutcome.notInstalled:
        return _fail(
          notInstalledMessage,
          status: VrLaunchStatus.notInstalled,
        );
      case VrLaunchOutcome.failed:
        return _fail(
          'Could not open the VR application. Please try again.',
          status: VrLaunchStatus.error,
        );
    }
  }

  VrLaunchState _fail(String message, {required VrLaunchStatus status}) {
    return state = VrLaunchState(status: status, message: message);
  }

  /// Turn a launch failure into copy a reader can act on.
  ///
  /// The backend answers each VR failure with a `code`, and those codes map to
  /// genuinely different advice — "not available in VR yet" is permanent while
  /// "the server is busy" is not — so they are read before falling back to the
  /// shared mapper.
  String _messageForDio(DioException e) {
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return 'VR needs a connection to start. Check your network and try again.';
    }

    final status = e.response?.statusCode;
    if (status == 401) {
      return 'Sign in to explore this artifact in VR.';
    }

    final data = e.response?.data;
    final code = data is Map<String, dynamic> ? data['code'] as String? : null;

    return switch (code) {
      'no_vr_experience' => "This artifact isn't available in VR yet.",
      'artifact_not_found' => 'That artifact is no longer available.',
      'experience_ambiguous' =>
        'This artifact is in more than one VR experience, so it cannot be '
            'opened from here yet.',
      'experience_not_found' => 'That VR experience is not available.',
      _ => AppErrorMapper.fromDio(e).message,
    };
  }
}

/// VR API service built on the authenticated client, so the launch request
/// carries the reader's JWT (the endpoint is authenticated server-side).
final vrApiServiceProvider = Provider<VrApiService>((ref) {
  final apiClient = ref.watch(authenticatedApiClientProvider);
  return VrApiService(dio: apiClient.dio);
});

/// The deep-link launcher. Overridden in tests with fakes.
final vrLauncherProvider = Provider<VrLauncher>((ref) => const VrLauncher());

/// Launch controller for the artifact/experience screens.
final vrLaunchControllerProvider =
    StateNotifierProvider<VrLaunchController, VrLaunchState>((ref) {
      return VrLaunchController(
        api: ref.watch(vrApiServiceProvider),
        launcher: ref.watch(vrLauncherProvider),
      );
    });
