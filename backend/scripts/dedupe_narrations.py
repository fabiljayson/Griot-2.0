"""Remove duplicate narration jobs left by concurrent `seed_narrations` runs.

Keeps the OLDEST completed job per (story, artifact, language) target and
deletes the rest, along with their audio files, so no orphans remain on disk.

Rows with id <= KEEP_BELOW are pre-existing duplicates from earlier manual
runs and are deliberately left alone — this cleans up only what the raced
seed runs created.

Run with: python scripts/dedupe_narrations.py --apply
"""

import argparse
import os
import sys

import django

sys.path.insert(
    0, os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
)
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings.dev')
django.setup()

from media_app.models import AudioNarrationJob  # noqa: E402

# Ids at or below this existed before the concurrent seed runs.
KEEP_BELOW = 0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        '--apply',
        action='store_true',
        help='Actually delete. Without this flag nothing is written.',
    )
    args = parser.parse_args()

    seen = set()
    duplicates = []
    jobs = AudioNarrationJob.objects.order_by('id')
    for job in jobs:
        key = (job.story_id, job.artifact_id, job.language)
        if key in seen:
            duplicates.append(job)
        else:
            seen.add(key)

    pre_existing = [j for j in duplicates if j.id <= KEEP_BELOW]
    from_race = [j for j in duplicates if j.id > KEEP_BELOW]

    print(f'total jobs            : {jobs.count()}')
    print(f'distinct targets      : {len(seen)}')
    print(f'duplicates from race  : {len(from_race)}')
    print(f'pre-existing dupes    : {len(pre_existing)} (left alone)')
    print(f'pre-existing detail   : {sorted(j.id for j in pre_existing)}')

    if not args.apply:
        print('\nDry run. Re-run with --apply to delete.')
        return

    freed = 0
    for job in from_race:
        freed += job.file_size or 0
        # delete(save=False) leaves the file alone; we want it gone.
        if job.audio_file:
            job.audio_file.delete(save=False)
        job.delete()

    print(f'\ndeleted {len(from_race)} duplicate job(s), '
          f'~{freed / 1024 / 1024:.1f} MB of audio')

    remaining = AudioNarrationJob.objects.count()
    print(f'jobs remaining: {remaining}')
    uncredited = AudioNarrationJob.objects.filter(engine='').count()
    print(f'jobs with no engine recorded: {uncredited}')


if __name__ == '__main__':
    main()