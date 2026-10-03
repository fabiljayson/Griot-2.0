import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../stories/models/story_model.dart';
import '../models/moderation_models.dart';
import 'flagged_story_card.dart' show StatusPill;

/// One story in the consent queue, with everything a moderator needs to
/// decide on it.
///
/// The point of showing [ConsentReviewStory.provenanceNotes] and
/// [ConsentReviewStory.origin] here is that the decision is *about the text*.
/// A moderator asked to press "granted" on a title and an author name is being
/// asked to sign for a tradition they have not read the provenance of, so the
/// provenance is not decoration here — it is the thing being judged.
class ConsentReviewCard extends StatelessWidget {
  const ConsentReviewCard({
    super.key,
    required this.story,
    required this.onDecide,
  });

  final ConsentReviewStory story;
  final VoidCallback onDecide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.ochre.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  story.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ConsentStatePill(consentStatus: story.consentStatus),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'by ${story.authorUsername}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (story.region.isNotEmpty) ...[
            const SizedBox(height: 10),
            _ConsentRow(label: 'Region', value: story.region),
          ],
          const SizedBox(height: 10),
          _ConsentRow(
            label: 'Origin',
            value: StoryOrigin.fromString(story.origin).label,
          ),
          _ConsentRow(
            label: 'Licence',
            value: StoryLicence.fromString(story.licence).label,
          ),
          if (story.rightsHolder.isNotEmpty)
            _ConsentRow(label: 'Rights holder', value: story.rightsHolder),
          if (story.provenanceNotes.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              story.provenanceNotes,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
          if (story.consentBasis.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Previous basis: ${story.consentBasis}',
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              StatusPill(status: story.status),
              const Spacer(),
              FilledButton.icon(
                onPressed: onDecide,
                icon: const Icon(AppIcons.khanda, size: 16),
                label: const Text('Record decision'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.ochre,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 40),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A consent state as a pill, coloured by whether the story can be relied on.
///
/// Mirrors `StoryModel.hasEstablishedConsent`: only `granted` and
/// `granted_restricted` mean the community agreed. Everything else is not
/// permission, which is why `withheld` and the unasked states read as warning
/// colours rather than as neutral ones.
class ConsentStatePill extends StatelessWidget {
  const ConsentStatePill({super.key, required this.consentStatus});

  final String consentStatus;

  static const _labels = {
    'not_requested': 'Not requested',
    'pending': 'Awaiting answer',
    'granted': 'Granted',
    'granted_restricted': 'Granted (restricted)',
    'withheld': 'Withheld',
  };

  static const _colors = {
    'granted': AppColors.savannahGreen,
    'granted_restricted': AppColors.ochre,
    'withheld': AppColors.error,
    'pending': AppColors.ochre,
    'not_requested': AppColors.charcoalMuted,
  };

  static String labelFor(String status) => _labels[status] ?? status;

  static Color colorFor(String status) =>
      _colors[status] ?? AppColors.charcoalMuted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = colorFor(consentStatus);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        labelFor(consentStatus),
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// A label/value row inside the consent card.
class _ConsentRow extends StatelessWidget {
  const _ConsentRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}