import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../stories/models/story_model.dart';

/// Model representing a museum artifact.
class ArtifactModel {
  const ArtifactModel({
    required this.id,
    required this.title,
    this.slug = '',
    this.description = '',
    this.category = 'other',
    this.culture = '',
    this.region = '',
    this.estimatedDate = '',
    this.materials = '',
    this.dimensions = '',
    this.imageUrl = '',
    this.imageBlurhash = '',
    this.additionalImages = const [],
    this.qrCodeSvg = '',
    this.deepLinkPath = '',
    this.qrDeepLink = '',
    this.stories = const [],
    this.museumName = '',
    this.floor = '',
    this.displayCase = '',
    this.isPublished = false,
    this.scanCount = 0,
    this.createdAt = '',
  });

  final int id;
  final String title;
  final String slug;
  final String description;
  final String category;
  final String culture;
  final String region;
  final String estimatedDate;
  final String materials;
  final String dimensions;
  final String imageUrl;
  final String imageBlurhash;
  final List<String> additionalImages;
  final String qrCodeSvg;
  final String deepLinkPath;
  final String qrDeepLink;
  final List<StoryModel> stories;
  final String museumName;
  final String floor;
  final String displayCase;
  final bool isPublished;
  final int scanCount;
  final String createdAt;

  factory ArtifactModel.fromJson(Map<String, dynamic> json) {
    return ArtifactModel(
      id: json['id'] as int? ?? 0,
      title: json['title'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      description: json['description'] as String? ?? '',
      category: json['category'] as String? ?? 'other',
      culture: json['culture'] as String? ?? '',
      region: json['region'] as String? ?? '',
      estimatedDate: json['estimated_date'] as String? ?? '',
      materials: json['materials'] as String? ?? '',
      dimensions: json['dimensions'] as String? ?? '',
      imageUrl: json['image'] as String? ?? '',
      imageBlurhash: json['image_blurhash'] as String? ?? '',
      additionalImages:
          (json['additional_images'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      qrCodeSvg: json['qr_code_svg'] as String? ?? '',
      deepLinkPath: json['deep_link_path'] as String? ?? '',
      qrDeepLink: json['qr_deep_link'] as String? ?? '',
      stories:
          (json['stories'] as List<dynamic>?)
              ?.map((e) => StoryModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      museumName: json['museum_name'] as String? ?? '',
      floor: json['floor'] as String? ?? '',
      displayCase: json['display_case'] as String? ?? '',
      isPublished: json['is_published'] as bool? ?? false,
      scanCount: json['scan_count'] as int? ?? 0,
      createdAt: json['created_at'] as String? ?? '',
    );
  }

  /// Category display label.
  String get categoryLabel {
    return switch (category) {
      'sculpture' => 'Sculpture',
      'textile' => 'Textile',
      'instrument' => 'Musical Instrument',
      'jewelry' => 'Jewelry',
      'pottery' => 'Pottery',
      'mask' => 'Mask',
      'weapon' => 'Weapon',
      'fabric' => 'Woven Fabric',
      'tool' => 'Tool',
      _ => 'Other',
    };
  }

  /// Category icon.
  String get categoryEmoji {
    return switch (category) {
      'sculpture' => '🗿',
      'textile' => '🧵',
      'instrument' => '🥁',
      'jewelry' => '💎',
      'pottery' => '🏺',
      'mask' => '🎭',
      'weapon' => '⚔️',
      'fabric' => '🪢',
      'tool' => '🔧',
      _ => '🏛️',
    };
  }
}

/// API service for QR code and artifact endpoints.
class QrApiService {
  QrApiService._({Dio? dio}) : _dio = dio ?? ApiClient.instance.dio;

  final Dio _dio;

  static final QrApiService instance = QrApiService._();

  static const _basePath = '/api';

  /// Look up an artifact by deep link path.
  Future<ArtifactModel?> lookupArtifact(String path) async {
    try {
      final response = await _dio.get(
        '$_basePath/artifacts/lookup/',
        queryParameters: {'path': path},
      );
      return ArtifactModel.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Get artifact detail by slug.
  Future<ArtifactModel> getArtifact(String slug) async {
    final response = await _dio.get('$_basePath/artifacts/$slug/');
    return ArtifactModel.fromJson(response.data as Map<String, dynamic>);
  }

  /// List published artifacts.
  Future<List<ArtifactModel>> listArtifacts({int page = 1}) async {
    final response = await _dio.get(
      '$_basePath/artifacts/',
      queryParameters: {'page': page},
    );
    final results = response.data['results'] as List<dynamic>;
    return results
        .map((json) => ArtifactModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Record a QR code scan.
  Future<void> recordScan({
    required String artifactSlug,
    String deviceType = '',
    double? latitude,
    double? longitude,
  }) async {
    await _dio.post(
      '$_basePath/artifacts/$artifactSlug/scan/',
      data: {
        'device_type': deviceType,
        'latitude': ?latitude,
        'longitude': ?longitude,
      },
    );
  }

  /// Handle a scanned QR code URL.
  ///
  /// Parses the URL and returns the artifact if found.
  Future<ArtifactModel?> handleScannedUrl(String url) async {
    // Extract path from URL
    final uri = Uri.tryParse(url);
    if (uri == null) return null;

    String path;

    // Handle africanteller.org deep links
    if (uri.host.contains('africanteller.org') ||
        uri.host.contains('africanteller')) {
      path = uri.path;
    }
    // Handle /artifact/<slug> or /qr/<slug> paths
    else if (uri.path.startsWith('/artifact/') || uri.path.startsWith('/qr/')) {
      path = uri.path;
    }
    // Handle raw slugs
    else {
      path = '/artifact/${uri.path}';
    }

    return lookupArtifact(path);
  }
}
