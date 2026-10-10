import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/griot_skeleton.dart';
import '../models/verification_models.dart';
import '../providers/admin_provider.dart';
import '../widgets/dashboard_error.dart';
import '../widgets/value_formatters.dart';
import '../widgets/verification_form_sheet.dart';
import '../widgets/verification_queue_card.dart';

/// Stories awaiting a verification decision (admins and institution managers).
///
/// The queue is defined once, server-side, in
/// `stories.services.verification_queue`: what counts as "awaiting review" is
/// a rule about the record, not a filter this screen invents. Everything a
/// reviewer needs to decide — the provenance, the sources, the evidence
/// checklist and the score it produces — travels with each row.
class VerificationQueueScreen extends ConsumerWidget {
  const VerificationQueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queueAsync = ref.watch(verificationQueueProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verification review'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(verificationQueueProvider),
            icon: const Icon(AppIcons.refresh),
          ),
        ],
      ),
      body: queueAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(24),
          child: GriotSkeletonList(itemCount: 4),
        ),
        error: (error, _) => DashboardError(
          message: friendlyError(error),
          onRetry: () => ref.invalidate(verificationQueueProvider),
        ),
        data: (queue) => queue.isEmpty
            ? const _NothingAwaiting()
            : RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(verificationQueueProvider);
                  await ref.read(verificationQueueProvider.future);
                },
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    _QueueIntro(count: queue.length),
                    const SizedBox(height: 14),
                    for (final story in queue)
                      VerificationQueueCard(
                        story: story,
                        busy: ref.watch(
                          verificationActionProvider
                              .select((s) => s.isBusy(story.slug)),
                        ),
                        onDecide: () => _decide(context, ref, story),
                        onToggleSource: (source, isVerified) =>
                            _toggleSource(context, ref, story, source.id, isVerified),
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  /// Open the sheet, record the decision, and take the story out of the queue.
  ///
  /// The sheet owns the write (it has to, so a failed save keeps the
  /// reviewer's notes); this only reacts to the outcome.
  Future<void> _decide(
    BuildContext context,
    WidgetRef ref,
    VerificationQueueEntry story,
  ) async {
    final recorded = await VerificationFormSheet.show(context, story);
    if (!recorded || !context.mounted) return;

    // The decided story leaves the queue, so the list is refetched rather
    // than patched — the queue's membership is a server-side rule and this
    // screen has no business reimplementing it.
    ref.invalidate(verificationQueueProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Decision recorded for “${story.title}”.')),
    );
  }

  /// Confirm or withdraw one source check, then re-read the queue: the score
  /// follows the evidence, and the new score must come from the server that
  /// recomputed it rather than from arithmetic done here.
  Future<void> _toggleSource(
    BuildContext context,
    WidgetRef ref,
    VerificationQueueEntry story,
    int sourceId,
    bool isVerified,
  ) async {
    final ok = await ref.read(verificationActionProvider.notifier).confirmSource(
      slug: story.slug,
      sourceId: sourceId,
      isVerified: isVerified,
    );
    if (!ok || !context.mounted) return;

    ref.invalidate(verificationQueueProvider);
  }
}

/// What this queue is for, in the reviewer's own terms — including what the
/// score does *not* claim.
class _QueueIntro extends StatelessWidget {
  const _QueueIntro({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.ochre.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.ochre.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$count ${count == 1 ? 'story awaits' : 'stories await'} verification',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'The trust score measures how well a story is documented — its '
            'sources, community validation, expert review — never how likely '
            'it is to be true. Check the evidence boxes before you approve.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// The honest empty state: no story is sitting in a reviewable status right
/// now, which is not the same as every story being documented.
class _NothingAwaiting extends StatelessWidget {
  const _NothingAwaiting();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              AppIcons.check_circle,
              size: 44,
              color: AppColors.savannahGreen,
            ),
            const SizedBox(height: 14),
            Text(
              'Nothing awaiting verification',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'No story is waiting on a verification decision here. Stories '
              'that were rejected or never submitted for review are not in '
              'this queue.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
