"""
Test script: exercises the full quiz flow via Django's test client.
Run with:  python test_quiz_api.py

This is a standalone smoke script, NOT a unit-test module. The whole flow
lives inside main() guarded by __main__, so `manage.py test` (which
discovers test*.py files) imports it without running anything against the
empty test database.
"""
import os
import sys


def main():
    os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings.dev')

    import django
    django.setup()

    from django.contrib.auth import get_user_model
    from rest_framework.test import APIRequestFactory, force_authenticate
    from gamification.models import (
        Quiz,
        QuizAttempt,
        UserProfile,
        UserBadge,
        QuizQuestion,
    )
    from gamification.views import QuizViewSet

    User = get_user_model()

    # Ensure UTF-8 output on Windows
    if sys.platform == 'win32':
        sys.stdout.reconfigure(encoding='utf-8')

    # Setup
    user, _ = User.objects.get_or_create(
        username='quiz_tester',
        defaults={'email': 'quiz_tester@test.com', 'role': 'visitor'},
    )
    user.set_password('testpass123')
    user.save()

    factory = APIRequestFactory()

    print("\n" + "=" * 60)
    print("  QUIZ API TEST - FULL FLOW")
    print("=" * 60)

    # 1. List quizzes
    request = factory.get('/api/gamification/quizzes/')
    force_authenticate(request, user=user)
    view = QuizViewSet.as_view({'get': 'list'})
    response = view(request)
    quizzes_raw = response.data

    if isinstance(quizzes_raw, dict) and 'results' in quizzes_raw:
        quizzes = quizzes_raw['results']
    else:
        quizzes = quizzes_raw

    print(f"\n[Step 1] List quizzes --- Status: {response.status_code}")
    print(f"   Found {len(quizzes)} quizzes")
    for q in quizzes:
        print(f"   [{q['id']}] {q['title']} ({q['question_count']} questions)")

    # 2. Pick first quiz, retrieve detail
    quiz_id = quizzes[0]['id']
    request = factory.get(f'/api/gamification/quizzes/{quiz_id}/')
    force_authenticate(request, user=user)
    view = QuizViewSet.as_view({'get': 'retrieve'})
    response = view(request, pk=quiz_id)
    detail = response.data
    print(f"\n[Step 2] Retrieve quiz {quiz_id} --- Status: {response.status_code}")
    print(f"   Title: {detail['title']}")
    print(f"   Questions: {detail['question_count']}")
    questions_api = detail.get('questions', [])
    for i, q in enumerate(questions_api):
        print(f"   Q{i+1}: {q['question_text'][:70]}...")
        print(f"        A={q['option_a'][:40]}  B={q['option_b'][:40]}")

    # Fetch correct answers from DB (not exposed in API)
    db_questions = QuizQuestion.objects.filter(quiz_id=quiz_id).order_by('order')
    correct_answers = {q.id: q.correct_answer for q in db_questions}
    print(f"   (Fetched {len(correct_answers)} correct answers from DB)")

    # 3. Start quiz attempt
    request = factory.post(f'/api/gamification/quizzes/{quiz_id}/start/', {}, format='json')
    force_authenticate(request, user=user)
    view = QuizViewSet.as_view({'post': 'start'})
    response = view(request, pk=quiz_id)
    attempt_data = response.data
    print(f"\n[Step 3] Start quiz attempt --- Status: {response.status_code}")
    print(f"   Attempt ID: {attempt_data['id']}")
    print(f"   Status: {attempt_data['status']}")
    print(f"   Total questions: {attempt_data['total_questions']}")

    # 4. Submit all answers (all correct)
    for i, q in enumerate(questions_api):
        qid = q['id']
        correct = correct_answers[qid]
        request = factory.post(
            f'/api/gamification/quizzes/{quiz_id}/submit_answer/',
            {'question_id': qid, 'selected_answer': correct},
            format='json',
        )
        force_authenticate(request, user=user)
        view = QuizViewSet.as_view({'post': 'submit_answer'})
        response = view(request, pk=quiz_id)
        result = response.data
        status_mark = "PASS" if result['is_correct'] else "FAIL"
        print(f"\n[Step 4.{i+1}] Submit Q{i+1} --- {status_mark}")
        print(f"   Correct: {result['is_correct']}")
        print(f"   Progress: {result['answered_count']}/{result['total_questions']}")
        print(f"   Explanation: {result['explanation'][:80]}...")

    # 5. Finish quiz
    request = factory.post(f'/api/gamification/quizzes/{quiz_id}/finish/', {}, format='json')
    force_authenticate(request, user=user)
    view = QuizViewSet.as_view({'post': 'finish'})
    response = view(request, pk=quiz_id)
    final = response.data
    print(f"\n[Step 5] Finish quiz --- Status: {response.status_code}")
    print(f"   Score: {final['score']}%")
    print(f"   Passed: {final['passed']}")
    print(f"   Correct: {final['correct_count']}/{final['total_questions']}")
    print(f"   XP earned: {final['xp_earned']}")
    print(f"   Time taken: {final['time_taken_seconds']}s")

    # 6. Check user profile
    profile, _ = UserProfile.objects.get_or_create(user=user)
    print(f"\n[Step 6] User profile")
    print(f"   Level: {profile.level}")
    print(f"   Total XP: {profile.total_xp}")
    print(f"   Quizzes passed: {profile.quizzes_passed}")
    print(f"   XP progress: {profile.xp_progress:.1%}")

    # 7. Check badges earned
    badges_earned = UserBadge.objects.filter(user=user).select_related('badge')
    print(f"\n[Step 7] Badges earned: {badges_earned.count()}")
    for ub in badges_earned:
        print(f"   {ub.badge.emoji} {ub.badge.name}")

    # 8. Try to start same quiz again
    request = factory.post(f'/api/gamification/quizzes/{quiz_id}/start/', {}, format='json')
    force_authenticate(request, user=user)
    view = QuizViewSet.as_view({'post': 'start'})
    response = view(request, pk=quiz_id)
    print(f"\n[Step 8] Start same quiz again --- Status: {response.status_code}")
    print(f"   Returned status: {response.data['status']}")

    # 9. Verify attempts count
    attempts = QuizAttempt.objects.filter(user=user, quiz__id=quiz_id)
    print(f"\n[Step 9] Total attempts for quiz {quiz_id}: {attempts.count()}")
    for a in attempts:
        print(f"   Attempt {a.id}: {a.status} | Score: {a.score}% | Passed: {a.passed}")

    # 10. Try submitting wrong answer to a NEW quiz
    quiz2 = Quiz.objects.exclude(id=quiz_id).first()
    if quiz2:
        print(f"\n[Step 10] Test wrong answer on quiz: {quiz2.title}")
        # Start
        request = factory.post(f'/api/gamification/quizzes/{quiz2.id}/start/', {}, format='json')
        force_authenticate(request, user=user)
        view = QuizViewSet.as_view({'post': 'start'})
        response = view(request, pk=quiz2.id)
        print(f"   Started: {response.status_code}")

        # Get correct answer from DB, then submit WRONG one
        q2 = QuizQuestion.objects.filter(quiz=quiz2).first()
        wrong = 'a' if q2.correct_answer != 'a' else 'b'
        request = factory.post(
            f'/api/gamification/quizzes/{quiz2.id}/submit_answer/',
            {'question_id': q2.id, 'selected_answer': wrong},
            format='json',
        )
        force_authenticate(request, user=user)
        view = QuizViewSet.as_view({'post': 'submit_answer'})
        response = view(request, pk=quiz2.id)
        result = response.data
        # On repeated runs a leftover in-progress attempt may already hold an
        # answer for this question — handle that gracefully instead of crashing.
        if 'is_correct' in result:
            print(f"   Submitted wrong answer: is_correct={result['is_correct']}")
            print(f"   Correct answer was: {result['correct_answer']}")
            print(f"   Explanation: {result['explanation'][:80]}...")
        else:
            print(f"   Could not submit answer: {result}")

    print(f"\n{'='*60}")
    print(f"  QUIZ API TEST COMPLETE")
    print("=" * 60)


if __name__ == '__main__':
    main()
