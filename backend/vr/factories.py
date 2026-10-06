"""Factories shared by the VR test modules.

Deliberately not a `test*.py` module: its name keeps unittest discovery from
importing it as a suite, while the tests import it explicitly. Nothing here has
side effects beyond the rows it creates.
"""

from django.contrib.auth import get_user_model

from media_app.models import AudioNarrationJob
from qr_codes.models import Artifact
from stories.models import Story

from .models import VRExperience, VRExperienceArtifact

User = get_user_model()


def make_user(username='visitor1', *, role='visitor', password='hunter2secure'):
    return User.objects.create_user(
        username,
        email=f'{username}@example.com',
        password=password,
        role=role,
    )


def make_artifact(title='Royal Bamoun Throne', *, published=True, **kwargs):
    defaults = {
        'description': 'A ceremonial throne used by Bamoun kings.',
        'category': 'sculpture',
        'culture': 'Bamoun',
        'region': 'West Region',
        'museum_name': 'Foumban Royal Museum',
        'is_published': published,
    }
    defaults.update(kwargs)
    return Artifact.objects.create(title=title, **defaults)


def make_story(title='The Throne Speaks', *, status=Story.Status.PUBLISHED, author=None, **kwargs):
    # `Story.author` is NOT NULL, and every published story in this project has
    # a named teller behind it — the factory says so rather than inventing one
    # per test.
    if author is None:
        author, _ = User.objects.get_or_create(
            username='storyteller',
            defaults={
                'email': 'storyteller@example.com',
                'role': 'contributor',
            },
        )

    defaults = {
        'content': 'Once, the throne was carried through the courtyard.',
        'summary': 'A royal procession.',
        'language': Story.Language.ENGLISH,
        'region': 'West Region',
    }
    defaults.update(kwargs)
    return Story.objects.create(
        title=title, status=status, author=author, **defaults,
    )


def make_experience(title='Bamoun Heritage Gallery', *, active=True, **kwargs):
    defaults = {
        'description': 'The royal courtyard, reconstructed.',
        'scene_identifier': 'bamoun_gallery',
        'environment': 'royal_palace_courtyard',
        'museum_name': 'Foumban Royal Museum',
        'region': 'West Region',
        'culture': 'Bamoun',
        'is_active': active,
    }
    defaults.update(kwargs)
    return VRExperience.objects.create(title=title, **defaults)


def place(experience, artifact, **kwargs):
    defaults = {
        'order': 0,
        'model_url': '',
        'model_scale': 1.0,
        'is_interactive': True,
    }
    defaults.update(kwargs)
    return VRExperienceArtifact.objects.create(
        experience=experience, artifact=artifact, **defaults
    )


def make_narration(
    user,
    *,
    artifact=None,
    story=None,
    status=AudioNarrationJob.Status.COMPLETED,
    audio_url='https://cdn.example.org/audio/narration.mp3',
    **kwargs,
):
    """A narration job. `target_key` is recomputed by the model on save."""
    return AudioNarrationJob.objects.create(
        user=user,
        artifact=artifact,
        story=story,
        narration_text='Synthetic narration of the artifact.',
        language='en',
        status=status,
        duration=84,
        audio_url=audio_url,
        **kwargs,
    )
