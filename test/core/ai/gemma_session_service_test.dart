import 'package:flutter_gemma/flutter_gemma.dart' as gemma;
import 'package:flutter_test/flutter_test.dart';

import 'package:quex/core/ai/gemma_inference_service.dart';
import 'package:quex/core/ai/gemma_session_service.dart';
import 'package:quex/core/ai/tutor_event.dart';

class _RepeatedTextInferenceService extends GemmaInferenceService {
  int addTextQueryCalls = 0;

  @override
  bool get isInitialized => true;

  @override
  bool get hasActiveSession => true;

  @override
  Future<void> addTextQuery(String message, {bool noTool = false}) async {
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
  Future<void> addTextQuery(String message, {bool noTool = false}) async {
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
}
