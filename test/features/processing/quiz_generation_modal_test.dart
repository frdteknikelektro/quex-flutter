import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart' as gemma;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:quex/core/ai/quiz_generation_event.dart';
import 'package:quex/core/ai/quiz_generation_service.dart';
import 'package:quex/core/db/daos.dart';
import 'package:quex/core/db/database.dart';
import 'package:quex/core/models/models.dart';
import 'package:quex/core/state/app_state.dart';
import 'package:quex/features/processing/quiz_generation_modal.dart';
import 'package:quex/generated/l10n/app_localizations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class ControlledQuizGenerationService extends QuizGenerationService {
  @override
  Future<void> initialize({
    int maxTokens = 8192,
    gemma.PreferredBackend? preferredBackend,
    int? maxNumImages,
    bool? enableSpeculativeDecoding,
  }) async {}

  @override
  Stream<QuizGenerationEvent> runExtractionSession({
    required Session session,
    required List<StudyMaterial> materials,
    String locale = 'en',
  }) {
    return Stream.fromIterable([
      QuizExtractionStarted(),
      QuizTextToken('What is photosynthesis?\nA. Food\nB. Process\n'),
      QuizExtractionComplete(
        'What is photosynthesis?\nA. Food\nB. Process\n',
      ),
      QuizStepCompleted(0),
    ]);
  }

  @override
  Stream<QuizGenerationEvent> runGenerationSession({
    required Session session,
    required List<StudyMaterial> materials,
    required String reviewText,
    int targetCount = 10,
    String locale = 'en',
  }) {
    return Stream.fromIterable([
      QuizGenerationStarted(1),
      QuizPhaseStarted(QuizGenerationPhase.generation),
      QuizPhaseTextToken(
        QuizGenerationPhase.generation,
        '[QUESTION]\nWhat is photosynthesis?\n[OPTIONS]\nA. Food\nB. Process\n',
      ),
      QuizPhaseCompleted(QuizGenerationPhase.generation),
      QuizStepCompleted(2),
    ]);
  }

  @override
  Stream<QuizGenerationEvent> runReviewSession({
    required Session session,
    required List<StudyMaterial> materials,
    required String extractedQuestions,
    String locale = 'en',
  }) {
    return Stream.fromIterable([
      QuizPhaseStarted(QuizGenerationPhase.review),
      QuizPhaseTextToken(
        QuizGenerationPhase.review,
        '[QUESTION_REVIEW]\n- USABLE: What is photosynthesis?\n',
      ),
      QuizPhaseCompleted(QuizGenerationPhase.review),
      QuizStepCompleted(1),
      QuizReviewComplete(
        '[QUESTION_REVIEW]\n- USABLE: What is photosynthesis?\n',
      ),
    ]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() async {
    await QuexDatabase.close();
    final db = await QuexDatabase.instance;
    await db.delete('sessions');
    await SessionDAO().insert(
      Session(
        id: 1,
        profileId: 1,
        title: 'Science',
        emoji: '🧪',
        gradeOverride: 3,
        createdAt: DateTime(2025, 1, 1),
      ),
    );
  });

  tearDown(() async {
    await QuexDatabase.close();
  });

  testWidgets('opens the quiz generation modal and shows selected state',
      (tester) async {
    final service = ControlledQuizGenerationService();
    final session = Session(
      id: 1,
      profileId: 1,
      title: 'Science',
      emoji: '🧪',
      gradeOverride: 3,
      createdAt: DateTime(2025, 1, 1),
    );
    final materials = [
      StudyMaterial(
        id: 1,
        sessionId: 1,
        kind: MaterialKind.text,
        title: 'Photosynthesis',
        content: 'Plants use sunlight to make food.',
        pageIndex: 0,
        createdAt: DateTime(2025, 1, 1),
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionBundleProvider(1).overrideWith(
            (ref) async => SessionBundle(
              session: session,
              materials: materials,
              quizzes: const [],
              messages: const [],
            ),
          ),
        ],
        child: MaterialApp.router(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: GoRouter(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) {
                  return Scaffold(
                    body: Center(
                      child: Builder(
                        builder: (context) => FilledButton(
                          onPressed: () => showDialog<void>(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) => QuizGenerationModal(
                              sessionId: 1,
                              quizService: service,
                            ),
                          ),
                          child: const Text('Open'),
                        ),
                      ),
                    ),
                  );
                },
              ),
              GoRoute(
                path: '/session/:sessionId/quiz/:quizId/detail',
                builder: (context, state) {
                  return const Scaffold(
                    body: Center(child: Text('quiz detail')),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();

    expect(find.text('Generate quiz (1)'), findsOneWidget);
  });

  test('censors answer metadata in the visible transcript', () {
    final sanitized = sanitizeQuizTranscript('''
[QUESTION]
What is photosynthesis?
[OPTIONS]
A. Food
B. Process
[CORRECT]
B
[END]

[QUESTION]
What is the expected answer?
[EXPECTED_ANSWER]
Sunlight
[END]
''');

    expect(sanitized, contains('[QUESTION]'));
    expect(sanitized, contains('[OPTIONS]'));
    expect(sanitized, isNot(contains('[CORRECT]')));
    expect(sanitized, isNot(contains('[EXPECTED_ANSWER]')));
    expect(sanitized, isNot(contains('Sunlight')));
    expect(sanitized, isNot(contains('B\n')));
  });
}
