import 'dart:io';

import 'package:flutter_gemma/flutter_gemma.dart' as gemma;
import 'package:flutter_test/flutter_test.dart';

import 'package:quex/core/ai/gemma_inference_service.dart';
import 'package:quex/core/ai/gemma_wiki_service.dart';
import 'package:quex/core/ai/wiki_storage_service.dart';
import 'package:quex/core/models/models.dart';

class _RepeatedToolInferenceService extends GemmaInferenceService {
  int createSessionCalls = 0;
  int addTextQueryCalls = 0;
  int addToolResponseCalls = 0;

  @override
  bool get isInitialized => true;

  @override
  Future<void> createSession({
    String? systemInstruction,
    double temperature = 0.8,
    int randomSeed = 1,
    int topK = 1,
    bool supportImage = false,
    bool isThinking = false,
    List<gemma.Tool> tools = const [],
    bool supportsFunctionCalls = false,
  }) async {
    createSessionCalls++;
  }

  @override
  Future<void> addTextQuery(String message, {bool noTool = false}) async {
    addTextQueryCalls++;
  }

  @override
  Future<void> addToolResponse({
    required String toolName,
    required Map<String, Object?> response,
  }) async {
    addToolResponseCalls++;
  }

  @override
  Stream<gemma.ModelResponse> generateResponses() async* {
    for (var i = 0; i < 4; i++) {
      yield const gemma.FunctionCallResponse(
        name: 'list_existing_pages',
        args: {},
      );
    }
  }
}

void main() {
  test('wiki agent stops on repeated identical tool calls', () async {
    final tempDir = await Directory.systemTemp.createTemp('quex-wiki-loop-');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final storage = WikiStorageService(
      documentsDirectoryProvider: () async => tempDir,
    );
    final service = _RepeatedToolInferenceService();
    final wiki = GemmaWikiService(storage);
    final session = Session(
      id: 7,
      profileId: 1,
      title: 'Loop Test',
      emoji: '🧪',
      gradeOverride: 3,
      createdAt: DateTime.utc(2026, 1, 1),
    );

    await expectLater(
      wiki.runIngest(
        service: service,
        session: session,
        materials: const [],
        sessionId: 7,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('repeated tool call'),
        ),
      ),
    );

    expect(service.createSessionCalls, 1);
    expect(service.addTextQueryCalls, 1);
    expect(service.addToolResponseCalls, 0);
  });
}
