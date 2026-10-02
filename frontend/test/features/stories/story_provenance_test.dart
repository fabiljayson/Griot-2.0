import 'package:flutter_test/flutter_test.dart';
import 'package:griot_ai/features/stories/models/story_model.dart';

/// The app renders oral traditions it did not record.
///
/// These pin what a reader is told, and — just as importantly — what the app
/// refuses to claim. A field that defaults to "verified" would be worse than
/// no field at all.
void main() {
  StoryModel storyWith(Map<String, dynamic> overrides) {
    return StoryModel.fromJson({
      'id': 1,
      'title': 'The Calabash of Truth',
      'author': {'id': 1, 'username': 'teller'},
      ...overrides,
    });
  }

  group('StoryModel provenance parsing', () {
    test('reads every provenance field the API sends', () {
      final story = storyWith({
        'origin': 'community_recorded',
        'provenance_notes': 'Recorded in Bafoussam in 2019.',
        'consent_status': 'granted',
        'rights_holder': 'The Mambila community',
        'licence': 'cc_by_nc',
        'recorded_at': '2019-06-01',
        'attribution': 'Told by The Mambila',
        'is_synthetic_origin': false,
      });

      expect(story.origin, 'community_recorded');
      expect(story.provenanceNotes, 'Recorded in Bafoussam in 2019.');
      expect(story.consentStatus, 'granted');
      expect(story.rightsHolder, 'The Mambila community');
      expect(story.licence, 'cc_by_nc');
      expect(story.recordedAt, '2019-06-01');
      expect(story.attribution, 'Told by The Mambila');
      expect(story.isSyntheticOrigin, isFalse);
    });

    test('a story from an older payload defaults to unknown, not verified', () {
      final story = storyWith({});

      expect(story.origin, 'unknown');
      expect(story.originLabel, 'Unknown');
      expect(story.licence, 'undetermined');
      expect(story.licenceLabel, 'Undetermined');
      expect(story.consentStatus, 'not_requested');
      expect(story.isSyntheticOrigin, isFalse);
      expect(story.hasEstablishedConsent, isFalse);
    });

    test('an unrecognised wire value degrades to the honest label', () {
      final story = storyWith({
        'origin': 'invented_by_a_future_migration',
        'licence': 'also-invented',
      });

      expect(story.originLabel, 'Unknown');
      expect(story.licenceLabel, 'Undetermined');
    });

    test('round-trips through toJson without losing provenance', () {
      final original = storyWith({
        'origin': 'seeded',
        'licence': 'undetermined',
        'attribution': 'Oral tradition, Grassfields',
        'is_synthetic_origin': true,
      });

      final restored = StoryModel.fromJson(original.toJson());

      expect(restored.origin, original.origin);
      expect(restored.licence, original.licence);
      expect(restored.attribution, original.attribution);
      expect(restored.isSyntheticOrigin, isTrue);
    });
  });

  group('StoryModel consent', () {
    test('only granted statuses count as established consent', () {
      expect(
        storyWith({'consent_status': 'granted'}).hasEstablishedConsent,
        isTrue,
      );
      expect(
        storyWith({'consent_status': 'granted_restricted'})
            .hasEstablishedConsent,
        isTrue,
        reason: 'restricted consent still means the community agreed',
      );
    });

    test('"we have not asked" is not permission', () {
      for (final status in ['not_requested', 'pending', 'withheld', '']) {
        final story = storyWith({'consent_status': status});
        expect(
          story.hasEstablishedConsent,
          isFalse,
          reason: '"$status" must not read as consent',
        );
        expect(
          story.needsConsentDisclosure,
          isTrue,
          reason: '"$status" must be disclosed to the reader',
        );
      }
    });

    test('an established consent needs no disclosure', () {
      expect(
        storyWith({'consent_status': 'granted'}).needsConsentDisclosure,
        isFalse,
      );
    });

    test('withheld consent still needs disclosure even though it is a decision',
        () {
      final story = storyWith({'consent_status': 'withheld'});
      expect(story.hasEstablishedConsent, isFalse);
      expect(story.needsConsentDisclosure, isTrue);
    });
  });

  group('StoryOrigin', () {
    test('wire values match the backend choices', () {
      // These strings are a contract with `Story.Origin` on the Django side.
      expect(StoryOrigin.communityRecorded.value, 'community_recorded');
      expect(StoryOrigin.oralTranscription.value, 'oral_transcription');
      expect(StoryOrigin.publishedCollection.value, 'published_collection');
      expect(StoryOrigin.contributorOriginal.value, 'contributor_original');
      expect(StoryOrigin.seeded.value, 'seeded');
      expect(StoryOrigin.unknown.value, 'unknown');
    });

    test('seeded is labelled as demonstration content', () {
      expect(
        StoryOrigin.seeded.label,
        contains('demonstration'),
        reason: 'the label is what a reader sees on the card',
      );
    });
  });

  group('StoryLicence', () {
    test('wire values match the backend choices', () {
      expect(StoryLicence.allRightsReserved.value, 'all_rights_reserved');
      expect(StoryLicence.ccBy.value, 'cc_by');
      expect(StoryLicence.ccBySa.value, 'cc_by_sa');
      expect(StoryLicence.ccByNc.value, 'cc_by_nc');
      expect(StoryLicence.ccByNcSa.value, 'cc_by_nc_sa');
      expect(StoryLicence.publicDomain.value, 'public_domain');
      expect(StoryLicence.undetermined.value, 'undetermined');
    });
  });

  group('StoryModel copyWith', () {
    test('relabelling a story as seeded flips the synthetic flag', () {
      final original = storyWith({
        'origin': 'community_recorded',
        'is_synthetic_origin': false,
      });

      final relabelled = original.copyWith(
        origin: StoryOrigin.seeded.value,
        isSyntheticOrigin: true,
      );

      expect(relabelled.isSyntheticOrigin, isTrue);
      expect(relabelled.originLabel, 'Seeded demonstration content');
      // The original is untouched — models are immutable.
      expect(original.isSyntheticOrigin, isFalse);
    });
  });
}
