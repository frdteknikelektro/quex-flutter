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
  gemma.ToolChoice? lastToolChoice;
  String? lastSystemInstruction;

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
    lastSystemInstruction = systemInstruction;
    expect(promptDialect, gemma.PromptDialect.gemma4);
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

class _PromptCaptureInferenceService extends GemmaInferenceService {
  _PromptCaptureInferenceService(this.responses);

  final List<gemma.ModelResponse> responses;
  int createSessionCalls = 0;
  int addTextQueryCalls = 0;
  int addToolResponseCalls = 0;
  String? lastSystemInstruction;
  String? lastTextQuery;
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
    lastSystemInstruction = systemInstruction;
    expect(promptDialect, gemma.PromptDialect.gemma4);
  }

  @override
  Future<void> addTextQuery(String message, {bool noTool = false}) async {
    addTextQueryCalls++;
    lastTextQuery = message;
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
    for (final response in responses) {
      yield response;
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
    expect(service.lastToolChoice, gemma.ToolChoice.required);
    expect(
      service.lastSystemInstruction,
      contains('spawn_worker'),
    );
    expect(service.addTextQueryCalls, 1);
    expect(service.addToolResponseCalls, 0);
  });

  test('wiki manager spawns a worker and aggregates the report', () async {
    final tempDir = await Directory.systemTemp.createTemp('quex-wiki-flow-');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final storage = WikiStorageService(
      documentsDirectoryProvider: () async => tempDir,
    );
    final workerService = _PromptCaptureInferenceService([
      const gemma.FunctionCallResponse(
        name: 'list_existing_pages',
        args: {},
      ),
      const gemma.FunctionCallResponse(
        name: 'write_markdown_file',
        args: {
          'path': 'sources/alpha.md',
          'content': '# Alpha',
        },
      ),
      const gemma.FunctionCallResponse(
        name: 'finish_run',
        args: {
          'summary': 'Worker complete',
          'unresolvedIssues': ['Needs review'],
        },
      ),
    ]);
    final managerService = _PromptCaptureInferenceService([
      const gemma.FunctionCallResponse(
        name: 'list_existing_pages',
        args: {},
      ),
      const gemma.FunctionCallResponse(
        name: 'plan',
        args: {
          'steps': ['Write sources/alpha.md'],
        },
      ),
      const gemma.FunctionCallResponse(
        name: 'spawn_worker',
        args: {
          'task': 'Write sources/alpha.md',
          'stepIndex': 0,
        },
      ),
      const gemma.FunctionCallResponse(
        name: 'finish_run',
        args: {'summary': 'Manager complete'},
      ),
    ]);
    final wiki = GemmaWikiService(
      storage,
      workerServiceFactory: () => workerService,
    );
    final session = Session(
      id: 8,
      profileId: 1,
      title: 'Flow Test',
      emoji: '🧠',
      gradeOverride: 3,
      createdAt: DateTime.utc(2026, 1, 1),
    );

    final result = await wiki.runIngest(
      service: managerService,
      session: session,
      materials: const [],
      sessionId: 8,
    );

    expect(managerService.createSessionCalls, 1);
    expect(workerService.createSessionCalls, 1);
    expect(managerService.lastSystemInstruction, isNotNull);
    expect(managerService.lastSystemInstruction, contains('MODE: ingest'));
    expect(
      managerService.lastSystemInstruction,
      contains('spawn_worker'),
    );
    expect(workerService.lastSystemInstruction, isNotNull);
    expect(workerService.lastSystemInstruction, contains('ASSIGNED TASK'));
    expect(workerService.lastTextQuery, contains('Write sources/alpha.md'));
    expect(result.touchedPaths, contains('sources/alpha.md'));
    expect(result.unresolvedIssues, contains('Needs review'));
  });

  test('wiki manager system instruction differs for ingest and lint', () async {
    final tempDir = await Directory.systemTemp.createTemp('quex-wiki-prompt-');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final storage = WikiStorageService(
      documentsDirectoryProvider: () async => tempDir,
    );
    final wiki = GemmaWikiService(storage);
    final session = Session(
      id: 9,
      profileId: 1,
      title: 'Prompt Test',
      emoji: '🧠',
      gradeOverride: 3,
      createdAt: DateTime.utc(2026, 1, 1),
    );

    final ingestService = _PromptCaptureInferenceService([
      const gemma.FunctionCallResponse(
        name: 'list_existing_pages',
        args: {},
      ),
      const gemma.FunctionCallResponse(
        name: 'finish_run',
        args: {'summary': 'done'},
      ),
    ]);
    await wiki.runIngest(
      service: ingestService,
      session: session,
      materials: const [],
      sessionId: 9,
    );

    expect(ingestService.createSessionCalls, 1);
    expect(ingestService.lastSystemInstruction, isNotNull);
    expect(ingestService.lastSystemInstruction, contains('MODE: ingest'));
    expect(
      ingestService.lastSystemInstruction,
      contains('spawn_worker'),
    );

    final lintService = _PromptCaptureInferenceService([
      const gemma.FunctionCallResponse(
        name: 'list_existing_pages',
        args: {},
      ),
      const gemma.FunctionCallResponse(
        name: 'finish_run',
        args: {'summary': 'lint done'},
      ),
    ]);
    await wiki.runLint(
      service: lintService,
      session: session,
      materials: const [],
      sessionId: 9,
    );

    expect(lintService.createSessionCalls, 1);
    expect(lintService.lastSystemInstruction, isNotNull);
    expect(lintService.lastSystemInstruction, contains('MODE: lint'));
    expect(
      lintService.lastSystemInstruction,
      contains('spawn_worker'),
    );
    expect(ingestService.lastSystemInstruction,
        isNot(equals(lintService.lastSystemInstruction)));
  });
}
