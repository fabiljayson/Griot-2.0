import 'package:flutter_test/flutter_test.dart';
import 'package:griot_ai/features/stories/models/story_model.dart';

/// The Cultural Trust Score is evidence documentation, never a truth claim.
///
/// These pin the wire contract with `stories.trust` on the Django side, and —
/// just as importantly — the app's refusal to default anything to "verified".
/// A cached story that silently claimed review it never had would be worse
/// than no score at all.
void main() {
  StoryModel storyWith(Map<String, dynamic> overrides) {
    return StoryModel.fromJson({
      'id': 1,
      'title': 'The Calabash of Truth',
      'author': {'id': 1, 'username': 'teller'},
      ...overrides,
    });
  }

  group('StoryModel trust parsing', () {
    test('reads the score, band, sources and verification the API sends', () {
      final story = storyWith({
        'trust_score': 65,
        'trust_level': 'partial',
        'sources': [
          {
            'id': 3,
            'source_type': 'ORAL_TRADITION',
            'name': 'Foumban elders',
            'author': 'Njoya',
            'institution': 'Palace archive',
            'is_verified': true,
            'verified_by': 'manager1',
          },
        ],
        'verification': {
          'source_verified': true,
          'community_validated': true,
          'references_confirmed': true,
          'trust_score': 65,
          'trust_level': 'partial',
          'breakdown': [
            {
              'criterion': 'source_verified',
              'label': 'Reliable/documented source',
              'weight': 25,
              'confirmed': true,
            },
          ],
          'disclaimer': 'Measures documentation strength, not truth.',
          'reviewer': 'manager1',
        },
      });

      expect(story.trustScore, 65);
      expect(story.trustLevel, 'partial');
      expect(story.sources, hasLength(1));
      expect(story.sources.first.name, 'Foumban elders');
      expect(story.sources.first.isVerified, isTrue);
      expect(story.sources.first.verifiedBy, 'manager1');
      expect(story.verification, isNotNull);
      expect(story.verification!.trustScore, 65);
      expect(story.verification!.sourceVerified, isTrue);
      expect(story.verification!.disclaimer, contains('not truth'));
      expect(story.verification!.breakdown, hasLength(1));
    });

    test('an older payload is unverified, not verified', () {
      final story = storyWith({});

      expect(story.trustScore, 0);
      expect(story.trustLevel, 'unverified');
      expect(story.sources, isEmpty);
      expect(story.verification, isNull);
    });

    test('an unrecognised band degrades to unverified', () {
      final story = storyWith({'trust_level': 'definitely_true'});

      expect(TrustLevel.fromString(story.trustLevel), TrustLevel.unverified);
    });

    test('round-trips through toJson without losing trust evidence', () {
      final original = storyWith({
        'trust_score': 100,
        'trust_level': 'verified',
        'sources': [
          {'id': 1, 'source_type': 'ARCHIVE', 'name': 'Record 44'},
        ],
        'verification': {
          'source_verified': true,
          'trust_score': 100,
          'trust_level': 'verified',
        },
      });

      final restored = StoryModel.fromJson(original.toJson());

      expect(restored.trustScore, 100);
      expect(restored.trustLevel, 'verified');
      expect(restored.sources, hasLength(1));
      expect(restored.sources.first.sourceType, 'ARCHIVE');
      expect(restored.verification, isNotNull);
      expect(restored.verification!.sourceVerified, isTrue);
    });
  });

  group('TrustLevel', () {
    test('wire values match the backend bands', () {
      // These strings are a contract with `stories.trust.trust_level`.
      expect(TrustLevel.unverified.value, 'unverified');
      expect(TrustLevel.partial.value, 'partial');
      expect(TrustLevel.verified.value, 'verified');
    });

    test('the band names documentation strength, not truth', () {
      expect(TrustLevel.unverified.label, 'Unverified');
      expect(TrustLevel.partial.label, 'Partially verified');
      expect(
        TrustLevel.verified.label,
        'Verified',
        reason: 'verified qualifies the record, never the claim itself',
      );
    });
  });

  group('StoryStatus review states', () {
    test('wire values match the backend choices', () {
      // These strings are a contract with `Story.Status` on the Django side.
      expect(StoryStatus.underReview.value, 'under_review');
      expect(StoryStatus.needsRevision.value, 'needs_revision');
      expect(StoryStatus.underReview.label, 'Under Review');
      expect(StoryStatus.needsRevision.label, 'Changes Requested');
    });

    test('an unknown status falls back to draft', () {
      expect(
        StoryStatus.fromString('submitted_somewhere_new'),
        StoryStatus.draft,
      );
    });
  });

  group('StorySourceModel', () {
    test('source type values match the backend choices', () {
      // Contract with `StorySource.SourceType` — the API emits uppercase.
      expect(StorySourceType.oralTradition.value, 'ORAL_TRADITION');
      expect(StorySourceType.communityTestimony.value, 'COMMUNITY_TESTIMONY');
      expect(StorySourceType.book.value, 'BOOK');
      expect(StorySourceType.academicReference.value, 'ACADEMIC_REFERENCE');
      expect(StorySourceType.museum.value, 'MUSEUM');
      expect(
        StorySourceType.culturalInstitution.value,
        'CULTURAL_INSTITUTION',
      );
      expect(StorySourceType.archive.value, 'ARCHIVE');
      expect(StorySourceType.officialSource.value, 'OFFICIAL_SOURCE');
      expect(StorySourceType.other.value, 'OTHER');
    });

    test('a lowercase legacy value still resolves its label', () {
      final source = StorySourceModel.fromJson(
        const {'id': 9, 'source_type': 'oral_tradition', 'name': 'Elder'},
      );

      expect(source.typeLabel, 'Oral tradition');
    });

    test('an unrecognised source type degrades to Other', () {
      final source = StorySourceModel.fromJson(
        const {'id': 1, 'source_type': 'crystal_ball', 'name': 'A feeling'},
      );

      expect(source.typeLabel, 'Other');
    });

    test('citation joins author and institution, skipping what is absent', () {
      final both = StorySourceModel.fromJson(const {
        'id': 1,
        'source_type': 'book',
        'name': 'Tales of the Grassfields',
        'author': 'Rev. S. Cole',
        'institution': 'Society Press',
      });
      final nameOnly = StorySourceModel.fromJson(
        const {'id': 2, 'source_type': 'book', 'name': 'Anonymous pamphlet'},
      );

      expect(both.citation, 'Rev. S. Cole, Society Press');
      expect(nameOnly.citation, isEmpty);
    });
  });
}
