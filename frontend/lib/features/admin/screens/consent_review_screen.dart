import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../providers/admin_provider.dart';
import '../widgets/consent_form_sheet.dart';
import '../widgets/consent_review_card.dart';
import '../widgets/dashboard_error.dart';
import '../widgets/value_formatters.dart';

/// Stories awaiting a consent decision (admins and institution managers).
///
/// This screen is why `consent_status` was ever worth having. The field was
/// added, validated, migrated and enforced by the model, and nothing anywhere
/// in the product could display or change it — every seeded story sat at
/// `not_requested` with no worklist, no form, and no way to answer for the
/// communities the stories came from.
///
/// The queue itself is defined once, server-side, in
/// `stories.services.consent_review_queue`: what counts as "awaiting a
/// decision" is a rule about the record, not a filter this screen invents.
class ConsentReviewScreen extends ConsumerWidget {
  const ConsentReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queueAsync = ref.watch(consentQueueProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Consent review'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(consentQueueProvider),
            icon: const Icon(AppIcons.refresh),
          ),
        ],
      ),
      body: queueAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => DashboardError(
          message: friendlyError(error),
          onRetry: () => ref.invalidate(consentQueueProvider),
        ),
        data: (queue) => queue.isEmpty
            ? const _NothingAwaiting()
            : RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(consentQueueProvider);
                  await ref.read(consentQueueProvider.future);
                },
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    _QueueIntro(count: queue.length),
                    const SizedBox(height: 14),
                    for (final story in queue)
                      ConsentReviewCard(
                        story: story,
                        onDecide: () => _decide(context, ref, story.slug),
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  /// Open the form, record the decision, and take the story out of the queue.
  ///
  /// The sheet owns the write (it has to, so a failed save keeps the
  /// moderator's text); this only reacts to the outcome.
  Future<void> _decide(
    BuildContext context,
    WidgetRef ref,
    String slug,
  ) async {
    final queue = ref.read(consentQueueProvider).valueOrNull ?? const [];
    final story = queue.where((s) => s.slug == slug).firstOrNull;
    if (story == null) return;

    final recorded = await ConsentFormSheet.show(context, story);
    if (!recorded || !context.mounted) return;

    // The recorded story leaves the queue, so the list is refetched rather
    // than patched — the queue's membership is a server-side rule
    // (`stories.services.consent_review_queue`) and this screen has no business
    // reimplementing it.
    ref.invalidate(consentQueueProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Consent recorded for “${story.title}”.')),
    );
  }
}

/// What this queue is for, in the moderator's own terms.
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
            '$count ${count == 1 ? 'story needs' : 'stories need'} a decision',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'These are someone else’s traditions. Record what the community '
            'actually said and who told you — a consent status with no basis '
            'behind it cannot be defended.',
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

/// The honest empty state: not "all clear", because a queue that is empty
/// because nobody ever asks is not the same as one that is empty because every
/// story has an answer on record.
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
              'Nothing awaiting a decision',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Every story on record has an answer from its source community, '
              'or none has been asked yet.',
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