import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../models/verification_models.dart';
import '../providers/admin_provider.dart';

/// Modal form for recording a verification decision with its evidence.
///
/// The sheet owns the write rather than handing the decision back to its
/// caller, for the same reason `ConsentFormSheet` does: the reviewer's notes
/// are the record, and a failed request must not discard them.
///
/// Three rules, all of which the server also enforces and none of which a
/// plain "pick a status" control would:
///
///   * **Evidence travels with the decision.** The score is recomputed from
///     the checklist before the decision lands, so the number shown beside
///     "Approved" is the score the approval was based on. Only criteria the
///     reviewer actually changed are sent — re-sending every box would bump
///     `verified_at` on rows the reviewer never touched.
///   * **Approving withheld consent fails on the server.** The sheet says so
///     before the tap rather than after the 400.
///   * **Notes are append-only.** They end up in `reviewer_notes` beside the
///     reviewer's name; the sheet never rewrites what is already there.
class VerificationFormSheet extends ConsumerStatefulWidget {
  const VerificationFormSheet({
    super.key,
    required this.story,
    this.initialAction = VerifyAction.startReview,
  });

  final VerificationQueueEntry story;

  /// The action the sheet opens preselected.
  final VerifyAction initialAction;

  /// Record the decision. Returns true when the server accepted it.
  static Future<bool> show(
    BuildContext context,
    VerificationQueueEntry story, {
    VerifyAction action = VerifyAction.startReview,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => VerificationFormSheet(story: story, initialAction: action),
    ).then((recorded) => recorded ?? false);
  }

  @override
  ConsumerState<VerificationFormSheet> createState() =>
      _VerificationFormSheetState();
}

class _VerificationFormSheetState extends ConsumerState<VerificationFormSheet> {
  late final TextEditingController _notes = TextEditingController();

  late VerifyAction _action = widget.initialAction;

  /// The checklist as the reviewer sees it, seeded from the story's current
  /// evidence so an untouched box is never re-sent as a "change".
  late final Map<String, bool> _evidence = {
    for (final row in widget.story.breakdown) row.criterion: row.confirmed,
  };

  bool _showEvidenceError = false;
  bool _busy = false;
  String? _errorMessage;

  /// Approving a story whose community withheld consent is refused by
  /// `Story.save` — stated here so the reviewer is not left with a raw 400.
  bool get _approvalBlocked =>
      _action == VerifyAction.approve &&
      widget.story.consentStatus == 'withheld';

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_action == VerifyAction.approve && _evidence.values.every((v) => !v)) {
      // Approving with nothing confirmed claims a review that never checked
      // anything. The server allows it (the score would simply read 0), but a
      // zero-evidence approval is exactly the kind of record this workflow
      // exists to prevent.
      setState(() => _showEvidenceError = true);
      return;
    }

    setState(() {
      _busy = true;
      _errorMessage = null;
    });

    // Only criteria that actually changed travel with the decision.
    final changed = <String, dynamic>{};
    for (final row in widget.story.breakdown) {
      if (_evidence[row.criterion] != row.confirmed) {
        changed[row.criterion] = _evidence[row.criterion] ?? false;
      }
    }

    final ok = await ref.read(verificationActionProvider.notifier).decide(
      slug: widget.story.slug,
      action: _action,
      notes: _notes.text.trim(),
      evidence: changed.isEmpty ? null : changed,
    );
    if (!mounted) return;

    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }

    // The sheet stays open with everything the reviewer wrote still in it.
    setState(() {
      _busy = false;
      _errorMessage =
          ref.read(verificationActionProvider).errorMessage ??
          'Could not record the decision. Please try again.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final breakdown = widget.story.breakdown;
    final confirmedWeight = breakdown
        .where((row) => _evidence[row.criterion] ?? false)
        .fold<int>(0, (sum, row) => sum + row.weight);

    return Padding(
      // Lifts the sheet above the keyboard so the notes field stays reachable.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    AppIcons.shield_outlined,
                    size: 22,
                    color: AppColors.ochre,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Record verification decision',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                widget.story.title,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final choice in VerifyAction.values)
                    ChoiceChip(
                      label: Text(choice.label),
                      selected: _action == choice,
                      onSelected: _busy
                          ? null
                          : (selected) {
                              if (selected) setState(() => _action = choice);
                            },
                    ),
                ],
              ),
              const SizedBox(height: 16),

              if (breakdown.isNotEmpty) ...[
                Text(
                  'Evidence checklist',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Checked boxes are what the score is built from — '
                  '$confirmedWeight of ${breakdown.fold<int>(0, (s, r) => s + r.weight)} '
                  'points currently confirmed.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                for (final row in breakdown)
                  CheckboxListTile(
                    value: _evidence[row.criterion] ?? false,
                    onChanged: _busy
                        ? null
                        : (value) {
                            setState(
                              () => _evidence[row.criterion] = value ?? false,
                            );
                          },
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(row.label),
                    secondary: Text(
                      '+${row.weight}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                if (_showEvidenceError) ...[
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        AppIcons.error_outline,
                        size: 18,
                        color: AppColors.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Approving needs at least one confirmed criterion — '
                          'an approval with no evidence behind it is not a '
                          'review.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
              ],

              TextField(
                controller: _notes,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Reviewer notes',
                  hintText: 'What you checked, and what remains open.',
                  border: OutlineInputBorder(),
                ),
              ),

              if (_approvalBlocked) ...[
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      AppIcons.warning_amber_rounded,
                      size: 18,
                      color: AppColors.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'The community withheld consent on this story. The '
                        'server will refuse an approval until that changes.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              if (_errorMessage != null) ...[
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      AppIcons.error_outline,
                      size: 18,
                      color: AppColors.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: switch (_action) {
                          VerifyAction.approve => AppColors.savannahGreen,
                          VerifyAction.reject => AppColors.error,
                          _ => AppColors.ochre,
                        },
                        foregroundColor:
                            (_action == VerifyAction.approve ||
                                _action == VerifyAction.reject)
                            ? Colors.white
                            : AppColors.charcoal,
                      ),
                      child: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(_action.label),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
