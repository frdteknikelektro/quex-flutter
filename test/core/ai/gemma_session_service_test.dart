import 'package:flutter_gemma/flutter_gemma.dart' as gemma;
import 'package:flutter_test/flutter_test.dart';

import 'package:quex/core/ai/gemma_inference_service.dart';
import 'package:quex/core/ai/gemma_session_service.dart';

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
}
