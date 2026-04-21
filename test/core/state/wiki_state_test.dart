import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:quex/core/ai/gemma_inference_service.dart';
import 'package:quex/core/ai/gemma_wiki_service.dart';
import 'package:quex/core/ai/wiki_storage_service.dart';
import 'package:quex/core/models/models.dart';
import 'package:quex/core/state/app_state.dart';
import 'package:quex/core/state/wiki_state.dart';

import '../../support/fake_gemma_inference_service.dart';

class FakeWikiAgentService extends GemmaWikiService {
  FakeWikiAgentService(super.storage);

  int lintCalls = 0;

  @override
  Future<WikiAgentResult> runLint({
    required GemmaInferenceService service,
    required Session session,
    required List<StudyMaterial> materials,
    required int sessionId,
    WikiAgentLineCallback? onLine,
    void Function(List<String> steps)? onPlan,
    void Function(int index)? onStepComplete,
  }) async {
    lintCalls++;
    expect(materials, isEmpty);
    return const WikiAgentResult(
      touchedPaths: [],
      deletedPaths: [],
      summary: 'Lint complete',
    );
  }
}

void main() {
  test('lint runs without study materials', () async {
    final tempDir = await Directory.systemTemp.createTemp('quex-wiki-state-');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final storage = WikiStorageService(
      documentsDirectoryProvider: () async => tempDir,
    );
    final fakeAgent = FakeWikiAgentService(storage);
    final bundle = SessionBundle(
      session: Session(
        id: 1,
        profileId: 1,
        title: 'Cell Biology',
        emoji: '🧬',
        gradeOverride: 3,
        createdAt: DateTime.utc(2026, 1, 1),
      ),
      materials: const [],
      quizzes: const [],
      messages: const [],
    );

    final container = ProviderContainer(
      overrides: [
        sessionBundleProvider(1).overrideWith((ref) async => bundle),
        wikiAgentServiceProvider.overrideWith((ref) => fakeAgent),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(
      wikiActionControllerProvider(1).notifier,
    );

    await controller.lint(FakeGemmaInferenceService());

    final state = container.read(wikiActionControllerProvider(1));
    expect(fakeAgent.lintCalls, 1);
    expect(state.status, WikiActionStatus.success);
    expect(state.error, isNull);
    expect(state.lines.last, 'Lint complete');
  });
}
