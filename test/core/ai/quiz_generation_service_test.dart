import 'dart:typed_data';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quex/core/ai/chat_prompts.dart';
import 'package:flutter_gemma/flutter_gemma.dart' as gemma;
import 'package:quex/core/ai/gemma_chat_service.dart';
import 'package:quex/core/ai/quiz_generation_event.dart';
import 'package:quex/core/ai/quiz_agent_skill.dart';
import 'package:quex/core/ai/quiz_generation_service.dart';
import 'package:quex/core/models/models.dart';

class FakeQuizChatService implements QuizChatService {
  FakeQuizChatService(this.responses);

  final List<List<({String? text, String? thinking})>> responses;
  final List<String?> systemInstructions = [];
  final List<String> prompts = [];
  int createSessionCount = 0;
  int _responseIndex = 0;

  @override
  bool get isInitialized => true;

  @override
  Future<void> initialize({
    int maxTokens = 8192,
    gemma.PreferredBackend? preferredBackend,
    int? maxNumImages,
    bool? enableSpeculativeDecoding,
  }) async {}

  @override
  Future<void> createSession({
    String? systemInstruction,
    double temperature = 1.0,
    double topP = 0.95,
    int topK = 64,
    bool isThinking = false,
    List<gemma.Tool> tools = const [],
    ToolExecutor? toolExecutor,
  }) async {
    createSessionCount++;
    systemInstructions.add(systemInstruction);
  }

  @override
  Stream<({String? text, String? thinking})> sendMessage(String message) {
    prompts.add(message);
    return Stream.fromIterable(responses[_responseIndex++]);
  }

  @override
  Stream<({String? text, String? thinking})> sendMessageWithImages(
    String message,
    List<Uint8List> images,
  ) {
    prompts.add(message);
    return Stream.fromIterable(responses[_responseIndex++]);
  }
}

void main() {
  group('QuizGenerationService draft parsing', () {
    late QuizGenerationService service;

    setUp(() {
      service = QuizGenerationService();
    });

    test('parses structured multiple-choice draft with answer metadata', () {
      final drafts = service.parseStructuredDrafts('''
[QUESTION]
What is the capital of France?
[OPTIONS]
A. London
B. Paris
C. Berlin
D. Madrid
[CORRECT]
B
[EXPLANATION]
Paris is the capital of France.
[EVIDENCE]
The material states that the capital of France is Paris.
[END]
''');

      expect(drafts, hasLength(1));
      expect(drafts.single.questionText, 'What is the capital of France?');
      expect(drafts.single.options, ['London', 'Paris', 'Berlin', 'Madrid']);
      expect(drafts.single.correctOptionIndex, 1);
      expect(service.validateDraft(drafts.single).isValid, isTrue);
    });

    test('removes answer-key lines from legacy extracted markdown fallback',
        () {
      final drafts = service.parseStructuredDrafts('''
What is 2 + 2?
A. 3
B. 4
C. 5
Answer: B
---
''');

      expect(drafts, hasLength(1));
      expect(drafts.single.questionText, 'What is 2 + 2?');
      expect(drafts.single.options, ['3', '4', '5']);
      expect(
        drafts.single.options.any((option) => option.contains('Answer')),
        isFalse,
      );
    });

    test('rejects multiple-choice draft without correct option metadata', () {
      const draft = QuizItemDraft(
        questionText: 'Which planet is known as the Red Planet?',
        options: ['Earth', 'Mars', 'Venus'],
        explanation: 'Mars is commonly called the Red Planet.',
        evidence: 'The material says Mars is the Red Planet.',
      );

      final validation = service.validateDraft(draft);

      expect(validation.isValid, isFalse);
      expect(
        validation.issues,
        contains('Multiple-choice question is missing a correct option.'),
      );
    });

    test('rejects duplicate options', () {
      const draft = QuizItemDraft(
        questionText: 'Which process do plants use to make food?',
        options: ['Photosynthesis', 'Respiration', 'photosynthesis'],
        correctOptionIndex: 0,
        explanation: 'Plants make food through photosynthesis.',
        evidence: 'The material explains that plants use photosynthesis.',
      );

      final validation = service.validateDraft(draft);

      expect(validation.isValid, isFalse);
      expect(validation.issues, contains('Options contain duplicates.'));
    });
  });

  group('QuizGenerationService phase streaming', () {
    Session buildSession() {
      return Session(
        id: 7,
        profileId: 1,
        title: 'Science',
        emoji: '🧪',
        gradeOverride: 3,
        createdAt: DateTime(2025, 1, 1),
      );
    }

    List<StudyMaterial> buildMaterials() {
      return [
        StudyMaterial(
          id: 1,
          sessionId: 7,
          kind: MaterialKind.text,
          title: 'Photosynthesis',
          content: 'Plants use sunlight to make food.',
          pageIndex: 0,
          createdAt: DateTime(2025, 1, 1),
        ),
      ];
    }

    test('emits generation, review, and completion phases in order', () async {
      final chat = FakeQuizChatService([
        [
          (text: '[QUESTION]\nWhat is photosynthesis?\n', thinking: null),
          (text: '[OPTIONS]\nA. A type of food\nB. A way plants make food\n', thinking: null),
          (text: '[CORRECT]\nB\n', thinking: null),
          (text: '[EXPLANATION]\nPlants make food using sunlight.\n', thinking: null),
          (text: '[EVIDENCE]\nThe material says plants use sunlight to make food.\n[END]\n', thinking: null),
        ],
        [
          (text: '[QUESTION]\nWhat is photosynthesis?\n', thinking: null),
          (text: '[OPTIONS]\nA. A type of food\nB. A way plants make food\n', thinking: null),
          (text: '[CORRECT]\nB\n', thinking: null),
          (text: '[EXPLANATION]\nPlants make food using sunlight.\n', thinking: null),
          (text: '[EVIDENCE]\nThe material says plants use sunlight to make food.\n[END]\n', thinking: null),
        ],
      ]);

      final service = QuizGenerationService(chatService: chat);
      final events = await service
          .runGenerationSession(
            session: buildSession(),
            materials: buildMaterials(),
            extractedQuestions: 'What is photosynthesis?',
            targetCount: 1,
            locale: 'en',
          )
          .toList();

      expect(
        events.whereType<QuizPhaseStarted>().map((e) => e.phase).toList(),
        [
          QuizGenerationPhase.generation,
          QuizGenerationPhase.review,
        ],
      );
      expect(
        events.whereType<QuizPhaseCompleted>().map((e) => e.phase).toList(),
        [
          QuizGenerationPhase.generation,
          QuizGenerationPhase.review,
        ],
      );
      expect(
        events.whereType<QuizPhaseTextToken>().map((e) => e.phase).toList(),
        [
          QuizGenerationPhase.generation,
          QuizGenerationPhase.generation,
          QuizGenerationPhase.generation,
          QuizGenerationPhase.generation,
          QuizGenerationPhase.generation,
          QuizGenerationPhase.review,
          QuizGenerationPhase.review,
          QuizGenerationPhase.review,
          QuizGenerationPhase.review,
          QuizGenerationPhase.review,
        ],
      );
      expect(events.whereType<QuizGenerationComplete>(), hasLength(1));
      expect(events.whereType<QuizPhaseStarted>().map((e) => e.phase), isNot(contains(QuizGenerationPhase.regeneration)));
      expect(chat.createSessionCount, 2);
    });

    test('emits regeneration phase when review output is rejected', () async {
      final chat = FakeQuizChatService([
        [
          (text: '[QUESTION]\nWhat is photosynthesis?\n', thinking: null),
          (text: '[OPTIONS]\nA. A type of food\nB. Plants make food with sunlight\n', thinking: null),
          (text: '[EXPLANATION]\nToo short.\n', thinking: null),
          (text: '[EVIDENCE]\nPlants use sunlight.\n[END]\n', thinking: null),
        ],
        [
          (text: '[QUESTION]\nWhat is photosynthesis?\n', thinking: null),
          (text: '[OPTIONS]\nA. A type of food\nB. Plants make food with sunlight\n', thinking: null),
          (text: '[EXPLANATION]\nToo short.\n', thinking: null),
          (text: '[EVIDENCE]\nPlants use sunlight.\n[END]\n', thinking: null),
        ],
        [
          (text: '[QUESTION]\nWhat is photosynthesis?\n', thinking: null),
          (text: '[OPTIONS]\nA. A process plants use to make food\nB. A type of animal behavior\n', thinking: null),
          (text: '[CORRECT]\nA\n', thinking: null),
          (text: '[EXPLANATION]\nPlants use photosynthesis to make food from sunlight.\n', thinking: null),
          (text: '[EVIDENCE]\nThe material says plants make food using sunlight.\n[END]\n', thinking: null),
        ],
      ]);

      final service = QuizGenerationService(chatService: chat);
      final events = await service
          .runGenerationSession(
            session: buildSession(),
            materials: buildMaterials(),
            extractedQuestions: 'What is photosynthesis?',
            targetCount: 1,
            locale: 'en',
          )
          .toList();

      expect(
        events.whereType<QuizPhaseStarted>().map((e) => e.phase).toList(),
        [
          QuizGenerationPhase.generation,
          QuizGenerationPhase.review,
          QuizGenerationPhase.regeneration,
        ],
      );
      expect(chat.createSessionCount, 3);
      expect(events.whereType<QuizGenerationComplete>(), hasLength(1));
    });
  });

  group('ChatPrompts quiz extraction wording', () {
    test('keeps choices but removes answer keys', () {
      final prompt = ChatPrompts.getQuizExtractionInstruction('en');

      expect(prompt, contains('Include all answer choices/options'));
      expect(prompt, contains('Do NOT include answer keys'));
      expect(prompt, isNot(contains('DO NOT include all answer options')));
    });
  });

  group('QuizAgentSkill', () {
    test('defines the in-app agent workflow', () {
      expect(
        QuizAgentSkill.workflowSteps('en'),
        [
          'Extract questions from materials',
          'Generate question drafts with answer metadata',
          'Review quiz quality',
          'Generate or repair replacement questions',
        ],
      );
    });

    test('review prompt requires fixed valid draft blocks only', () {
      final instruction = QuizAgentSkill.reviewInstruction('en');

      expect(instruction, contains('Quiz quality reviewer'));
      expect(instruction, contains('Return only valid items'));
      expect(instruction, contains('safely fixed items'));
    });
  });
}
