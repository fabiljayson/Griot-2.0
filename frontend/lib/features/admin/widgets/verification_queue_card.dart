import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../stories/models/story_model.dart';
import '../models/verification_models.dart';
import 'consent_review_card.dart' show ConsentStatePill;
import 'flagged_story_card.dart' show StatusPill;

/// One story in the verification queue, with everything a reviewer needs to
/// decide on it.
///
/// The evidence checklist and the sources are shown *on the card*, not behind
/// a detail page: a reviewer pressing "Approve" on a title and a score is
/// being asked to vouch for documentation they have not seen, and the whole
/// point of the Cultural Trust Score is that the levers behind the number are
/// visible where the number is.
class VerificationQueueCard extends StatelessWidget {
  const VerificationQueueCard({
    super.key,
    required this.story,
    required this.onDecide,
    required this.onToggleSource,
    this.busy = false,
  });

  final VerificationQueueEntry story;

  /// Opens the decision sheet for this story.
  final VoidCallback onDecide;

  /// Confirms or withdraws the check on one of the story's sources.
  final void Function(StorySourceModel source, bool isVerified) onToggleSource;

  /// True while a request for this story is in flight.
  final bool busy;

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
              TrustScoreBadge(
                score: story.trustScore,
                level: story.trustLevel,
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'by ${story.authorUsername}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              StatusPill(status: story.status),
              ConsentStatePill(consentStatus: story.consentStatus),
            ],
          ),
          const SizedBox(height: 10),
          _Row(
            label: 'Origin',
            value: StoryOrigin.fromString(story.origin).label,
          ),
          if (story.region.isNotEmpty)
            _Row(label: 'Region', value: story.region),
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
          if (story.reviewer != null && story.reviewer!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'In review by ${story.reviewer}',
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],

          if (story.breakdown.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Evidence',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            for (final row in story.breakdown)
              _EvidenceRow(
                label: row.label,
                weight: row.weight,
                confirmed: row.confirmed,
              ),
          ],

          if (story.sources.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Sources',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            for (final source in story.sources)
              _SourceRow(
                source: source,
                busy: busy,
                onToggle: () =>
                    onToggleSource(source, !source.isVerified),
              ),
          ],

          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            // The button is the whole workflow entry: every decision — start,
            // approve, request changes, reject — plus its evidence is
            // recorded through the same sheet, so a reviewer never has to
            // guess which door a given action lives behind.
            child: FilledButton.icon(
              onPressed: busy ? null : onDecide,
              icon: const Icon(AppIcons.shield_outlined, size: 16),
              label: const Text('Record decision'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.ochre,
                foregroundColor: AppColors.charcoal,
                minimumSize: const Size(0, 40),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The score and its band, side by side — the band is what a reader sees, the
/// score is what the reviewer tuned the evidence to.
class TrustScoreBadge extends StatelessWidget {
  const TrustScoreBadge({super.key, required this.score, required this.level});

  final int score;
  final String level;

  static Color colorFor(String level) => switch (level) {
    'verified' => AppColors.savannahGreen,
    'partial' => AppColors.ochre,
    _ => AppColors.charcoalMuted,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = colorFor(level);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$score%',
            style: theme.textTheme.titleSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            TrustLevel.fromString(level).label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// One evidence criterion: the label, its weight, and whether it counts.
class _EvidenceRow extends StatelessWidget {
  const _EvidenceRow({
    required this.label,
    required this.weight,
    required this.confirmed,
  });

  final String label;
  final int weight;
  final bool confirmed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = confirmed
        ? AppColors.savannahGreen
        : theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            confirmed ? AppIcons.check_circle : AppIcons.radio_button_unchecked,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: confirmed ? null : theme.colorScheme.onSurfaceVariant,
                fontWeight: confirmed ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          Text(
            '+$weight',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// One source, with the confirm/undo control a reviewer uses to move the
/// first trust criterion.
class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.source,
    required this.onToggle,
    required this.busy,
  });

  final StorySourceModel source;
  final VoidCallback onToggle;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            source.isVerified ? AppIcons.check_circle : AppIcons.link,
            size: 16,
            color: source.isVerified
                ? AppColors.savannahGreen
                : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(source.name, style: theme.textTheme.bodySmall),
                if (source.citation.isNotEmpty)
                  Text(
                    '${source.typeLabel} · ${source.citation}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                else
                  Text(
                    source.typeLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: busy ? null : onToggle,
            child: Text(source.isVerified ? 'Undo' : 'Confirm'),
          ),
        ],
      ),
    );
  }
}

/// A label/value row inside the card.
class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

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
