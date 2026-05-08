import 'dart:async';
import 'dart:collection';

import 'package:flutter_gemma/flutter_gemma.dart' as gemma;
import 'package:flutter_test/flutter_test.dart';

import 'package:quex/core/ai/gemma_inference_service.dart';
import 'package:quex/core/ai/gemma_quiz_service.dart';
import 'package:quex/core/ai/quiz_generation_event.dart';
import 'package:quex/core/models/models.dart';

class _StuckGemmaInferenceService extends GemmaInferenceService {
  int addTextQueryCalls = 0;
  int createSessionCalls = 0;
  gemma.ToolChoice? lastToolChoice;
  String? lastSystemInstruction;

  @override
  bool get isInitialized => true;

  @override
  Future<void> createSession({
    String? systemInstruction,
    double temperature = 1.0,
    int randomSeed = 1,
    int topK = 64,
    double topP = 0.95,
    gemma.ModelType modelType = gemma.ModelType.gemma4,
    bool supportImage = false,
    bool supportAudio = false,
    bool isThinking = false,
    List<gemma.Tool> tools = const [],
    bool supportsFunctionCalls = false,
    gemma.ToolChoice toolChoice = gemma.ToolChoice.auto,
  }) async {
    createSessionCalls++;
    lastToolChoice = toolChoice;
    lastSystemInstruction = systemInstruction;
  }

  @override
  Future<void> addTextQuery(String message, {bool noTool = false, bool prefix = false}) async {
    addTextQueryCalls++;
  }

  @override
  Stream<gemma.ModelResponse> generateResponses() async* {
    yield* const Stream<gemma.ModelResponse>.empty();
  }
}

class _QueuedGemmaInferenceService extends GemmaInferenceService {
  _QueuedGemmaInferenceService(this.turns);

  final Queue<List<gemma.ModelResponse>> turns;
  final List<String> textQueries = [];
  final List<String> toolResponses = [];
  int createSessionCalls = 0;
  String? lastSystemInstruction;

  @override
  bool get isInitialized => true;

  @override
  Future<void> createSession({
    String? systemInstruction,
    double temperature = 1.0,
    int randomSeed = 1,
    int topK = 64,
    double topP = 0.95,
    gemma.ModelType modelType = gemma.ModelType.gemma4,
    bool supportImage = false,
    bool supportAudio = false,
    bool isThinking = false,
    List<gemma.Tool> tools = const [],
    bool supportsFunctionCalls = false,
    gemma.ToolChoice toolChoice = gemma.ToolChoice.auto,
  }) async {
    createSessionCalls++;
    lastSystemInstruction = systemInstruction;
  }

  @override
  Future<void> addTextQuery(String message, {bool noTool = false, bool prefix = false}) async {
    textQueries.add(message);
  }

  @override
  Future<void> addToolResponse({
    required String toolName,
    required Map<String, Object?> response,
  }) async {
    toolResponses.add(toolName);
  }

  @override
  Stream<gemma.ModelResponse> generateResponses() async* {
    if (turns.isEmpty) return;
    yield* Stream.fromIterable(turns.removeFirst());
  }
}

void main() {
  test('quiz system instruction requires tool-only plain question output',
      () async {
    final service = _StuckGemmaInferenceService();
    final quizService = GemmaQuizService(service);
    final session = Session(
      id: 1,
      profileId: 1,
      title: 'Plant Cells',
      emoji: '🧫',
      gradeOverride: 3,
      createdAt: DateTime.utc(2026, 1, 1),
    );

    await expectLater(
      quizService.runQuizAgent(session: session, materials: const []),
      emitsError(isA<StateError>()),
    );

    expect(service.createSessionCalls, 1);
    expect(service.lastSystemInstruction, isNotNull);
    expect(
      service.lastSystemInstruction,
      allOf(
        contains(
            'Generate quiz content only through the generate_question tool'),
        contains(
            'Write plain question text only, with no numbering such as "1." or "Question 1"'),
        contains(
            'Use multipleChoice for factual recall with 3-4 plain options and no option letters'),
      ),
    );
  });

  test('quiz agent stops after repeated analyze retries', () async {
    final service = _StuckGemmaInferenceService();
    final quizService = GemmaQuizService(service);
    final session = Session(
      id: 1,
      profileId: 1,
      title: 'Plant Cells',
      emoji: '🧫',
      gradeOverride: 3,
      createdAt: DateTime.utc(2026, 1, 1),
    );

    await expectLater(
      quizService.runQuizAgent(session: session, materials: const []),
      emitsError(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('analyze_materials'),
        ),
      ),
    );

    expect(service.createSessionCalls, 1);
    expect(service.lastToolChoice, gemma.ToolChoice.required);
    expect(service.addTextQueryCalls, greaterThanOrEqualTo(5));
  });

  test('runs the agentic quiz generation flow', () async {
    final service = _QueuedGemmaInferenceService(
      Queue.of([
        [
          const gemma.FunctionCallResponse(
            name: 'plan',
            args: {
              'steps': [
                'Plan',
                'Analyze',
                'Generate',
                'Review',
                'Finish',
              ],
            },
          ),
          const gemma.FunctionCallResponse(
            name: 'complete_step',
            args: {'index': 0},
          ),
          const gemma.FunctionCallResponse(
            name: 'analyze_materials',
            args: {
              'question_count': 2,
              'topics': ['Plants', 'Sunlight'],
            },
          ),
        ],
        [
          const gemma.FunctionCallResponse(
            name: 'generate_question',
            args: {
              'type': 'multipleChoice',
              'questionText': 'What is photosynthesis?',
              'options': [
                'The process plants use to make food',
                'A kind of leaf',
                'A type of soil',
              ],
            },
          ),
        ],
        [
          const gemma.FunctionCallResponse(
            name: 'generate_question',
            args: {
              'type': 'multipleChoice',
              'questionText': 'Why do plants need sunlight?',
              'options': [
                'To make food',
                'To become rocks',
                'To stop growing',
              ],
            },
          ),
        ],
        [
          const gemma.FunctionCallResponse(
            name: 'review_quiz',
            args: {
              'issues_found': [],
              'regenerate_indices': [],
              'ready_to_submit': true,
            },
          ),
        ],
        [
          const gemma.FunctionCallResponse(
            name: 'finish_run',
            args: {
              'summary': 'Created two distinct plant questions',
              'total_questions': 2,
            },
          ),
        ],
      ]),
    );

    final quizService = GemmaQuizService(service);
    final session = Session(
      id: 1,
      profileId: 1,
      title: 'Plant Cells',
      emoji: '🧫',
      gradeOverride: 3,
      createdAt: DateTime.utc(2026, 1, 1),
    );
    final material = StudyMaterial(
      id: 1,
      sessionId: 1,
      kind: MaterialKind.text,
      title: 'Plant basics',
      content: 'Plants use sunlight to make food through photosynthesis.',
      pageIndex: 0,
      createdAt: DateTime.utc(2026, 1, 1),
    );

    final events = await quizService
        .runQuizAgent(session: session, materials: [material], maxQuestions: 2)
        .toList();

    final questions = events
        .whereType<QuizQuestionGenerated>()
        .map((e) => e.question)
        .toList();

    expect(questions, hasLength(2));
    expect(questions.map((q) => q.questionText), [
      'What is photosynthesis?',
      'Why do plants need sunlight?',
    ]);
    expect(
        service.toolResponses,
        containsAllInOrder([
          'plan',
          'complete_step',
          'analyze_materials',
          'generate_question',
          'generate_question',
          'review_quiz',
          'finish_run',
        ]));
    expect(events.whereType<QuizGenerationComplete>(), isNotEmpty);
  });

  test('normalizes numbered question and option labels from tool output',
      () async {
    final service = _QueuedGemmaInferenceService(
      Queue.of([
        [
          const gemma.FunctionCallResponse(
            name: 'plan',
            args: {
              'steps': [
                'Plan',
                'Analyze',
                'Generate',
                'Review',
                'Finish',
              ],
            },
          ),
          const gemma.FunctionCallResponse(
            name: 'complete_step',
            args: {'index': 0},
          ),
          const gemma.FunctionCallResponse(
            name: 'analyze_materials',
            args: {
              'question_count': 1,
              'topics': ['Plants'],
            },
          ),
        ],
        [
          const gemma.FunctionCallResponse(
            name: 'generate_question',
            args: {
              'type': 'multipleChoice',
              'questionText': '1. What is photosynthesis?',
              'options': [
                'A. The process plants use to make food',
                'B. A kind of leaf',
                'C. A type of soil',
              ],
            },
          ),
        ],
        [
          const gemma.FunctionCallResponse(
            name: 'review_quiz',
            args: {
              'issues_found': [],
              'regenerate_indices': [],
              'ready_to_submit': true,
            },
          ),
        ],
        [
          const gemma.FunctionCallResponse(
            name: 'finish_run',
            args: {
              'summary': 'Created one plant question',
              'total_questions': 1,
            },
          ),
        ],
      ]),
    );

    final quizService = GemmaQuizService(service);
    final session = Session(
      id: 1,
      profileId: 1,
      title: 'Plant Cells',
      emoji: '🧫',
      gradeOverride: 3,
      createdAt: DateTime.utc(2026, 1, 1),
    );
    final material = StudyMaterial(
      id: 1,
      sessionId: 1,
      kind: MaterialKind.text,
      title: 'Plant basics',
      content: 'Plants use sunlight to make food through photosynthesis.',
      pageIndex: 0,
      createdAt: DateTime.utc(2026, 1, 1),
    );

    final events = await quizService
        .runQuizAgent(session: session, materials: [material], maxQuestions: 1)
        .toList();

    final questions = events
        .whereType<QuizQuestionGenerated>()
        .map((e) => e.question)
        .toList();

    expect(questions, hasLength(1));
    expect(questions.single.questionText, 'What is photosynthesis?');
    expect(questions.single.options, [
      'The process plants use to make food',
      'A kind of leaf',
      'A type of soil',
    ]);
  });
}
