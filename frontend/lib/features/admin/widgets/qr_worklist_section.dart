import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/griot_loader.dart';
import '../../../core/widgets/griot_skeleton.dart';
import '../../../core/theme/app_icons.dart';
import '../models/qr_worklist_models.dart';
import '../providers/admin_provider.dart';
import 'dashboard_section.dart';

/// The admin dashboard's QR code worklist.
///
/// The mobile mirror of the same section on the web dashboard: the same list,
/// the same ordering and the same bound, all owned by
/// `qr_codes.services.qr_worklist` on the server. This widget renders what it
/// is given and never re-derives the order — two clients disagreeing about
/// which objects still need a label is the failure the shared endpoint exists
/// to prevent.
class QrWorklistSection extends ConsumerWidget {
  const QrWorklistSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final worklistAsync = ref.watch(qrWorklistProvider);

    return worklistAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: GriotSkeletonList(itemCount: 3),
      ),
      error: (error, _) => DashboardSection(
        title: 'QR code worklist',
        subtitle: 'Printable codes for the museum floor',
        child: _ErrorBody(
          onRetry: () => ref.invalidate(qrWorklistProvider),
        ),
      ),
      data: (worklist) => _buildSection(context, theme, ref, worklist),
    );
  }

  Widget _buildSection(
    BuildContext context,
    ThemeData theme,
    WidgetRef ref,
    QrWorklist worklist,
  ) {
    final generation = ref.watch(qrGenerationProvider);
    final pending = worklist.unlabelled.length;

    return DashboardSection(
      title: 'QR code worklist',
      subtitle: 'Printable codes for the museum floor',
      trailing: Text(
        '$pending of ${worklist.total} still unlabelled',
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A truncated list that reads as complete is how an object goes
          // unlabelled and nobody notices, so it is stated rather than implied.
          if (worklist.truncated)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Showing ${worklist.entries.length} of ${worklist.total} '
                'artifacts — the catalog is larger than this worklist.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.accentTextStrong,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: generation.isSubmitting
                  ? null
                  : () => _generateAllMissing(context, ref),
              icon: generation.generatingAll
                  ? const GriotLoader.inline()
                  : const Icon(AppIcons.qr_code_scanner, size: 18),
              label: Text(
                generation.generatingAll
                    ? 'Generating…'
                    : 'Generate all missing',
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (worklist.entries.isEmpty)
            _EmptyBody(hasArtifacts: worklist.total > 0)
          else
            for (final entry in worklist.entries)
              _WorklistRow(
                entry: entry,
                busy: generation.isBusy(entry.slug),
                onGenerate: () => _generateOne(context, ref, entry),
              ),
        ],
      ),
    );
  }

  Future<void> _generateOne(
    BuildContext context,
    WidgetRef ref,
    QrWorklistEntry entry,
  ) async {
    final result = await ref.read(qrGenerationProvider.notifier).generateOne(
      entry.slug,
    );
    if (!context.mounted) return;

    if (result == null) {
      final message =
          ref.read(qrGenerationProvider).errorMessage ??
          'Could not generate the QR code.';
      _toast(context, message, AppColors.error);
      return;
    }
    // The server owns the ordering, so re-read it rather than guessing which
    // rows moved.
    ref.invalidate(qrWorklistProvider);
    _toast(context, 'QR code generated for “${entry.title}”.', AppColors.savannahGreen);
  }

  Future<void> _generateAllMissing(BuildContext context, WidgetRef ref) async {
    final result = await ref
        .read(qrGenerationProvider.notifier)
        .generateAllMissing();
    if (!context.mounted) return;

    if (result == null) {
      final message =
          ref.read(qrGenerationProvider).errorMessage ??
          'Could not generate the QR codes.';
      _toast(context, message, AppColors.error);
      return;
    }
    ref.invalidate(qrWorklistProvider);

    if (result.skipped) {
      _toast(
        context,
        'Nothing to generate — every artifact already has a code.',
        AppColors.savannahGreen,
      );
      return;
    }

    final count = result.generated.length;
    var message = '$count QR code${count == 1 ? '' : 's'} generated.';
    // A stale row is reported, not swallowed: a curator who ticked a row that
    // has since been deleted should be told, not left wondering.
    if (result.missing.isNotEmpty) {
      message +=
          ' ${result.missing.length} could not be found and '
          '${result.missing.length == 1 ? 'was' : 'were'} skipped.';
    }
    _toast(context, message, AppColors.savannahGreen);
  }

  void _toast(BuildContext context, String message, Color background) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: background,
      ),
    );
  }
}

class _WorklistRow extends StatelessWidget {
  const _WorklistRow({
    required this.entry,
    required this.busy,
    required this.onGenerate,
  });

  final QrWorklistEntry entry;
  final bool busy;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: entry.hasQrCode
              ? AppColors.savannahGreen.withValues(alpha: 0.3)
              : AppColors.ochre.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  entry.museumName.isEmpty ? entry.category : entry.museumName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  entry.deepLink,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      entry.hasQrCode
                          ? AppIcons.check_circle
                          : AppIcons.warning_amber_rounded,
                      size: 14,
                      color: entry.hasQrCode
                          ? AppColors.savannahGreen
                          : AppColors.ochre,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      entry.hasQrCode ? 'Ready to print' : 'No code yet',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: entry.hasQrCode
                            ? AppColors.savannahGreen
                            : AppColors.ochre,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${entry.scanTotal} scan${entry.scanTotal == 1 ? '' : 's'}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          IconButton.filledTonal(
            onPressed: busy ? null : onGenerate,
            tooltip: entry.hasQrCode ? 'Regenerate' : 'Generate',
            icon: busy
                ? const GriotLoader.inline()
                : Icon(
                    entry.hasQrCode
                        ? AppIcons.refresh
                        : AppIcons.qr_code_scanner,
                    size: 18,
                  ),
          ),
        ],
      ),
    );
  }
}

class _EmptyBody extends StatelessWidget {
  const _EmptyBody({required this.hasArtifacts});

  final bool hasArtifacts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = hasArtifacts
        ? 'No artifacts on this worklist.'
        : 'No artifacts to label yet.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.savannahGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.savannahGreen.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          const Icon(AppIcons.check_circle, size: 22, color: AppColors.savannahGreen),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.savannahGreen,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            'Could not load the QR worklist.',
            style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.error),
          ),
        ),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    );
  }
}