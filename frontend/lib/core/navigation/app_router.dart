import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/artifacts/screens/artifacts_screen.dart';
import '../../features/discover/screens/region_stories_screen.dart';
import '../../features/qr_scanner/screens/artifact_detail_screen.dart';
import '../../features/qr_scanner/services/qr_api_service.dart';
import '../../features/stories/screens/story_detail_screen.dart';
import '../widgets/app_components.dart';
import '../widgets/griot_loader.dart';
import 'app_deep_link.dart';

export 'app_deep_link.dart';

/// Root navigation: the app's single navigator key, plus deep-link routing.
///
/// Deep links were previously parsed nowhere — `main.dart` logged the incoming
/// URI and carried a `TODO: Wire to Navigator once a proper router is set up`,
/// so QR codes printed on museum labels and shared story links opened the app
/// on whatever screen the user had left it on. [AppRouter] owns the navigator
/// key so links can be routed from `main()`, and maps a parsed [AppDeepLink] to
/// the screen it names.
abstract final class AppRouter {
  /// The application navigator. Attached to `MaterialApp.navigatorKey`.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>(debugLabel: 'griot-root-navigator');

  /// Route an incoming link.
  ///
  /// Safe to call before the first frame: the push is deferred until a
  /// navigator exists, which is the case when the app is cold-started *by* the
  /// link.
  static void handle(Uri? uri) {
    final link = AppDeepLink.parse(uri);
    if (link == null) return;

    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => handle(uri));
      return;
    }

    navigator.push(
      MaterialPageRoute(builder: (_) => _screenFor(link)),
    );
  }

  static Widget _screenFor(AppDeepLink link) {
    return switch (link.kind) {
      DeepLinkKind.story => StoryDetailScreen(slug: link.value),
      DeepLinkKind.artifact => ArtifactDeepLinkScreen(slug: link.value),
      DeepLinkKind.region => RegionStoriesScreen(regionSlug: link.value),
    };
  }
}

/// Resolves a deep-linked artifact slug and then shows its detail screen.
///
/// The catalogue entry has to be fetched by slug first, so the target is
/// wrapped in a loader with a real error state instead of being pushed with a
/// stub model.
class ArtifactDeepLinkScreen extends ConsumerStatefulWidget {
  const ArtifactDeepLinkScreen({super.key, required this.slug});

  final String slug;

  @override
  ConsumerState<ArtifactDeepLinkScreen> createState() =>
      _ArtifactDeepLinkScreenState();
}

class _ArtifactDeepLinkScreenState extends ConsumerState<ArtifactDeepLinkScreen> {
  late Future<ArtifactModel> _artifact;

  @override
  void initState() {
    super.initState();
    _artifact = QrApiService.instance.getArtifact(widget.slug);
  }

  void _retry() {
    setState(() {
      _artifact = QrApiService.instance.getArtifact(widget.slug);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Artifact')),
      body: FutureBuilder<ArtifactModel>(
        future: _artifact,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const GriotLoadingState(label: 'Opening artifact');
          }

          final artifact = snapshot.data;
          if (artifact == null) {
            return ErrorState(
              message:
                  'We could not open “${widget.slug}”. It may have been '
                  'removed, or you may be offline.',
              title: 'Artifact not found',
              onRetry: _retry,
            );
          }

          return ArtifactDetailScreen(artifact: artifact);
        },
      ),
    );
  }
}

/// Catalogue screen for links that point at the collection rather than a
/// single record (e.g. `griot-ai://artifacts`).
class CollectionDeepLinkScreen extends StatelessWidget {
  const CollectionDeepLinkScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: SafeArea(child: ArtifactsScreen()));
  }
}
