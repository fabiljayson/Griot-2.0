import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../models/vr_launch_ticket.dart';

/// API service for the VR launch handoff. Mirrors `QrApiService` /
/// `VideoApiService`: a thin HTTP layer with no UI or navigation logic, built
/// on the authenticated Dio so the reader's JWT is attached.
///
/// `/api/vr/launch/` is minting a credential, so it is authenticated and
/// throttled server-side; the endpoint *is* the availability check (it answers
/// 404 with `code: no_vr_experience` when nothing places the artifact), which is
/// why the button does not make a second round trip to ask first.
class VrApiService {
  VrApiService({Dio? dio}) : _dio = dio ?? ApiClient.instance.dio;

  final Dio _dio;

  static const String _basePath = '/api/vr';

  /// Request a single-use launch token.
  ///
  /// Pass [artifact] (its slug or id) when the reader tapped an artifact, or
  /// [experience] to open a specific gallery directly. The server resolves the
  /// experience and rejects ambiguity rather than guessing.
  Future<VrLaunchTicket> requestLaunch({
    String? artifact,
    String? experience,
  }) async {
    final response = await _dio.post(
      '$_basePath/launch/',
      data: {
        if (artifact != null && artifact.isNotEmpty) 'artifact': artifact,
        if (experience != null && experience.isNotEmpty) 'experience': experience,
      },
    );

    return VrLaunchTicket.fromJson(response.data as Map<String, dynamic>);
  }
}
