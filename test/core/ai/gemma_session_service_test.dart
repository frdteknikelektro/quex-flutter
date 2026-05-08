import 'package:flutter_gemma/flutter_gemma.dart' as gemma;
import 'package:flutter_test/flutter_test.dart';

import 'package:quex/core/ai/gemma_inference_service.dart';
import 'package:quex/core/ai/gemma_session_service.dart';
import 'package:quex/core/ai/tutor_event.dart';
import 'package:quex/core/models/models.dart';

class _RepeatedTextInferenceService extends GemmaInferenceService {
  int addTextQueryCalls = 0;

  @override
  bool get isInitialized => true;

  @override
  bool get hasActiveSession => true;

  @override
  Future<void> addTextQuery(String message, {bool noTool = false, bool prefix = false}) async {
    addTextQueryCalls++;
  }

  @override
  Stream<gemma.ModelResponse> generateResponses() async* {
    for (var i = 0; i < 40; i++) {
      yield const gemma.TextResponse('loop');
    }
  }
}

class _ToolCallTextInferenceService extends GemmaInferenceService {
  int addTextQueryCalls = 0;

  @override
  bool get isInitialized => true;

  @override
  bool get hasActiveSession => true;

  @override
  Future<void> addTextQuery(String message, {bool noTool = false, bool prefix = false}) async {
    addTextQueryCalls++;
  }

  @override
  Stream<gemma.ModelResponse> generateResponses() async* {
    yield const gemma.TextResponse(
      '{"name":"evaluate_understanding","arguments":{"score":',
    );
    yield const gemma.TextResponse('1}}');
  }
}

class _PreloadRecordingInferenceService extends GemmaInferenceService {
  final operations = <String>[];
  String? systemInstruction;
  List<gemma.Message> replayedMessages = [];

  @override
  bool get isInitialized => true;

  @override
  bool get hasActiveSession => true;

  @override
  Future<void> closeSession() async {
    operations.add('closeSession');
  }

  @override
  Future<void> createSession({
    String? systemInstruction,
    double temperature = 1.0,
    int randomSeed = 1,
    int topK = 64,
    double topP = 0.95,
    gemma.ModelType modelType = gemma.ModelType.gemmaIt,
    bool supportImage = false,
    bool supportAudio = false,
    bool isThinking = false,
    List<gemma.Tool> tools = const [],
    bool supportsFunctionCalls = false,
    gemma.ToolChoice toolChoice = gemma.ToolChoice.auto,
  }) async {
    operations.add('createSession');
    this.systemInstruction = systemInstruction;
  }

  @override
  Future<void> replayMessages(List<gemma.Message> messages) async {
    operations.add('replayMessages');
    replayedMessages = List<gemma.Message>.of(messages);
  }
}

void main() {
  test('coach stream stops on repeated text token loop', () async {
    final service = _RepeatedTextInferenceService();
    final sessionService = GemmaSessionService(service);

    await expectLater(
      sessionService.sendCoachMessage('hello').toList(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('repeated text token'),
        ),
      ),
    );

    expect(service.addTextQueryCalls, 1);
  });

  test('tutor stream keeps tool-like text as plain text', () async {
    final service = _ToolCallTextInferenceService();
    final sessionService = GemmaSessionService(service);

    final events =
        await sessionService.sendQuestionTutorMessage('hello').toList();

    expect(
      events.whereType<TutorReply>().map((e) => e.token).join(),
      '{"name":"evaluate_understanding","arguments":{"score":1}}',
    );
    expect(events.whereType<TutorEvaluation>(), isEmpty);
    expect(service.addTextQueryCalls, 1);
  });

  test('preload replays only completed turns in order', () async {
    final service = _PreloadRecordingInferenceService();
    final sessionService = GemmaSessionService(service);
    const question = Question(
      quizId: 1,
      source: QuestionSource.generated,
      type: QuestionType.multipleChoice,
      questionText: 'What is 2 + 2?',
      options: ['3', '4', '5'],
      orderIndex: 0,
    );
    final materials = [
      StudyMaterial(
        sessionId: 1,
        kind: MaterialKind.text,
        title: 'Addition',
        content: 'Use counting to add numbers.',
        pageIndex: 0,
        createdAt: DateTime(2024),
      ),
    ];
    final history = [
      QuestionMessage(
        questionId: 1,
        role: QuestionMessageRole.user,
        content: 'I think it is 3.',
        createdAt: DateTime(2024, 1, 1),
      ),
      QuestionMessage(
        questionId: 1,
        role: QuestionMessageRole.assistant,
        content: 'Try again.',
        createdAt: DateTime(2024, 1, 1, 0, 0, 1),
      ),
      QuestionMessage(
        questionId: 1,
        role: QuestionMessageRole.user,
        content: 'Maybe 4.',
        createdAt: DateTime(2024, 1, 1, 0, 0, 2),
      ),
      QuestionMessage(
        questionId: 1,
        role: QuestionMessageRole.assistant,
        content: 'Correct.',
        createdAt: DateTime(2024, 1, 1, 0, 0, 3),
      ),
      QuestionMessage(
        questionId: 1,
        role: QuestionMessageRole.user,
        content: 'Unpaired draft',
        createdAt: DateTime(2024, 1, 1, 0, 0, 4),
      ),
    ];

    await sessionService.preloadQuestionTutorSession(
      question: question,
      materials: materials,
      history: history,
    );

    expect(service.operations, ['closeSession', 'createSession', 'replayMessages']);
    expect(service.replayedMessages, hasLength(5));
    expect(
      service.replayedMessages.map((message) => message.text).toList(),
      [
        '--- QUIZ QUESTION ---\nQuestion: What is 2 + 2?',
        'I think it is 3.',
        'Try again.',
        'Maybe 4.',
        'Correct.',
      ],
    );
    expect(
      service.replayedMessages.map((message) => message.isUser).toList(),
      [false, true, false, true, false],
    );
    expect(service.systemInstruction, isNot(contains(question.questionText)));
    expect(service.systemInstruction, contains('Options:'));
    expect(service.systemInstruction, contains('Addition:'));
  });
}
