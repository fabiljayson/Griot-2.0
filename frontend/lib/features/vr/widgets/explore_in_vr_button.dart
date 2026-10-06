import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_components.dart';
import '../../../core/widgets/griot_loader.dart';
import '../providers/vr_provider.dart';

/// "Virtual Reality" section for an artifact page.
///
/// Takes the artifact's slug rather than an `ArtifactModel` on purpose: this
/// feature's only contract with the rest of the app is an identifier the API
/// understands, so it does not have to be edited when the artifact model
/// changes, and it can be dropped onto a story or gallery screen unchanged.
///
/// Failure is a first-class outcome. Every path ends in either a launched
/// headset or a message the reader can read: no silent no-ops, no exceptions
/// escaping into the widget tree, and no crash when the VR app is not there.
class ExploreInVrButton extends ConsumerWidget {
  const ExploreInVrButton({super.key, required this.artifactSlug});

  /// Slug of the artifact to open in VR.
  final String artifactSlug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final state = ref.watch(vrLaunchControllerProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          title: 'Virtual Reality',
          icon: AppIcons.view_in_ar,
        ),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm + 2),
                    decoration: BoxDecoration(
                      color: AppColors.bronze.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.control),
                    ),
                    child: const Icon(
                      AppIcons.view_in_ar,
                      color: AppColors.bronzeDark,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'See this artifact in VR',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          state.status == VrLaunchStatus.requesting
                              ? 'Preparing your visit…'
                              : 'Stand beside this artifact in the virtual '
                                    'museum, on a headset.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  // Disabled while a launch is in flight: a second token would
                  // open a second copy of the scene.
                  onPressed: state.isBusy ? null : () => _launch(context, ref),
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.secondary,
                    foregroundColor: scheme.onSecondary,
                    minimumSize: const Size.fromHeight(AppSizes.buttonHeight),
                  ),
                  icon: state.isBusy
                      ? const GriotLoader(size: 18)
                      : const Icon(AppIcons.view_in_ar, size: 18),
                  label: Text(state.isBusy ? 'Opening…' : 'Explore in VR'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _launch(BuildContext context, WidgetRef ref) async {
    final result = await ref
        .read(vrLaunchControllerProvider.notifier)
        .launchForArtifact(artifactSlug);

    if (!context.mounted || !result.hasMessage) return;

    final message = result.message ?? '';

    // A missing app is a different conversation from a failed launch: it is
    // not an error the reader can retry away, so it gets a dialog that says so
    // instead of a snackbar that will be missed.
    if (result.status == VrLaunchStatus.notInstalled) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('VR app not found'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }
}
