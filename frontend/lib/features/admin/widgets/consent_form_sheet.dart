import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../stories/models/story_model.dart';
import '../models/moderation_models.dart';
import '../providers/admin_provider.dart';

/// What a moderator decided, and on what basis.
///
/// A value the moderator has to fill in rather than a status the form infers:
/// the basis is the part that makes the record defensible, so it is never
/// derived, defaulted, or left empty.
class ConsentDecision {
  const ConsentDecision({
    required this.status,
    required this.basis,
    this.rightsHolder,
    this.licence,
  });

  /// One of `StoryConsent` — the wire value, e.g. `granted_restricted`.
  final String status;

  /// Required. Who the moderator spoke to and what they said.
  final String basis;

  /// Optional override; null leaves the story's existing value alone.
  final String? rightsHolder;

  /// Optional override; null leaves the story's existing value alone.
  final String? licence;
}

/// Modal form for recording a community's answer on a story.
///
/// The sheet owns the write rather than handing a decision back to its caller,
/// because the moderator's words are the record: if the request fails, they
/// have to still be on screen to be retried. A caller that received a decision
/// and then posted it would have to either discard the text on failure or
/// rebuild the form to keep it, and the first of those loses the one thing
/// this screen exists to capture.
///
/// Three rules, all of which the server also enforces and none of which a plain
/// "pick a status" control would:
///
///   * **A basis is mandatory.** `consent_status` answers "did they agree";
///     only the basis answers "says who, on what grounds".
///   * **Withholding is not a light edit.** Choosing "withheld" on a published
///     story archives it, so the sheet says so before the moderator commits
///     rather than after.
///   * **An emptied rights holder changes nothing.** Sending an empty string
///     would blank a real rights holder; the override is omitted instead.
class ConsentFormSheet extends ConsumerStatefulWidget {
  const ConsentFormSheet({super.key, required this.story});

  final ConsentReviewStory story;

  /// Records the decision. Returns true when the server accepted it.
  static Future<bool> show(BuildContext context, ConsentReviewStory story) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ConsentFormSheet(story: story),
    ).then((recorded) => recorded ?? false);
  }

  @override
  ConsumerState<ConsentFormSheet> createState() => _ConsentFormSheetState();
}

class _ConsentFormSheetState extends ConsumerState<ConsentFormSheet> {
  late final TextEditingController _basis = TextEditingController(
    text: widget.story.consentBasis,
  );
  late final TextEditingController _rightsHolder = TextEditingController(
    text: widget.story.rightsHolder,
  );

  /// Prefilled with the story's current licence so that recording a decision
  /// without touching rights does not silently blank them out.
  late StoryLicence _licence = StoryLicence.fromString(widget.story.licence);
  late StoryConsent _decision = StoryConsent.fromString(
    widget.story.consentStatus,
  );

  bool _showBasisError = false;
  bool _busy = false;
  String? _errorMessage;

  /// Recording "withheld" here archives a live story. Stated before the tap,
  /// not discovered after it.
  bool get _willArchive =>
      _decision == StoryConsent.withheld &&
      widget.story.status == 'published';

  @override
  void dispose() {
    _basis.dispose();
    _rightsHolder.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final basis = _basis.text.trim();
    if (basis.isEmpty) {
      setState(() => _showBasisError = true);
      return;
    }

    final rightsHolder = _rightsHolder.text.trim();
    setState(() {
      _busy = true;
      _errorMessage = null;
    });

    final ok = await ref.read(consentActionProvider.notifier).record(
      slug: widget.story.slug,
      status: _decision.value,
      basis: basis,
      // Empty means "leave it as it is" — the server only overwrites when a
      // value is sent, so an untouched field must send nothing.
      rightsHolder: rightsHolder.isEmpty ? null : rightsHolder,
      licence: _licence.value,
    );
    if (!mounted) return;

    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }

    // The sheet stays open with everything the moderator wrote still in it.
    setState(() {
      _busy = false;
      _errorMessage =
          ref.read(consentActionProvider).errorMessage ??
          'Could not record the decision. Please try again.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      // Lifts the sheet above the keyboard so the basis field stays reachable.
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(AppIcons.khanda, size: 22, color: AppColors.ochre),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Record the community’s answer',
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

              DropdownButtonFormField<StoryConsent>(
                initialValue: _decision,
                decoration: const InputDecoration(
                  labelText: 'Decision',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final choice in StoryConsent.values)
                    DropdownMenuItem(
                      value: choice,
                      child: Text(choice.label),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (value) {
                        if (value != null) setState(() => _decision = value);
                      },
              ),
              const SizedBox(height: 14),

              TextField(
                controller: _basis,
                maxLines: 3,
                // A consent status with nothing behind it cannot be defended.
                // The server refuses an empty basis too; catching it here just
                // saves the round trip and says why.
                decoration: InputDecoration(
                  labelText: 'Basis (required)',
                  hintText: 'Who you spoke to, and what they said.',
                  border: const OutlineInputBorder(),
                  errorText: _showBasisError
                      ? 'Record the basis for this decision.'
                      : null,
                ),
              ),
              const SizedBox(height: 14),

              TextField(
                controller: _rightsHolder,
                decoration: const InputDecoration(
                  labelText: 'Rights holder',
                  hintText: 'Leave empty to keep the current value',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),

              DropdownButtonFormField<StoryLicence>(
                initialValue: _licence,
                decoration: const InputDecoration(
                  labelText: 'Licence',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final choice in StoryLicence.values)
                    DropdownMenuItem(
                      value: choice,
                      child: Text(choice.label),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (value) {
                        if (value != null) setState(() => _licence = value);
                      },
              ),

              if (_willArchive) ...[
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
                        'This story is published. Recording “withheld” '
                        'archives it immediately. The record is kept, never '
                        'deleted.',
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
                      onPressed: _busy ? null : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: _decision == StoryConsent.withheld
                            ? AppColors.error
                            : AppColors.bronze,
                        foregroundColor: _decision == StoryConsent.withheld
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
                          : const Text('Record'),
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