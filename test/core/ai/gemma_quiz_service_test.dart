import 'dart:async';

import 'package:flutter_gemma/flutter_gemma.dart' as gemma;
import 'package:flutter_test/flutter_test.dart';

import 'package:quex/core/ai/gemma_inference_service.dart';
import 'package:quex/core/ai/gemma_quiz_service.dart';
import 'package:quex/core/models/models.dart';

class _StuckGemmaInferenceService extends GemmaInferenceService {
  int addTextQueryCalls = 0;
  int createSessionCalls = 0;
  gemma.ToolChoice? lastToolChoice;

  @override
  bool get isInitialized => true;

  @override
  Future<void> createSession({
    String? systemInstruction,
    double temperature = 0.8,
    int randomSeed = 1,
    int topK = 1,
    gemma.ModelType modelType = gemma.ModelType.gemmaIt,
    gemma.PromptDialect promptDialect = gemma.PromptDialect.gemma4,
    bool supportImage = false,
    bool isThinking = false,
    List<gemma.Tool> tools = const [],
    bool supportsFunctionCalls = false,
    gemma.ToolChoice toolChoice = gemma.ToolChoice.auto,
  }) async {
    createSessionCalls++;
    lastToolChoice = toolChoice;
    expect(promptDialect, gemma.PromptDialect.gemma4);
  }

  @override
  Future<void> addTextQuery(String message, {bool noTool = false}) async {
    addTextQueryCalls++;
  }

  @override
  Stream<gemma.ModelResponse> generateResponses() async* {
    yield* const Stream<gemma.ModelResponse>.empty();
  }
}

void main() {
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
}
