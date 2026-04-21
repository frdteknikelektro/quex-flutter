import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/gemma_inference_service.dart';
import '../ai/gemma_wiki_service.dart';
import '../ai/wiki_storage_service.dart';
import '../state/app_state.dart';

final wikiStorageServiceProvider = Provider<WikiStorageService>((ref) {
  return WikiStorageService();
});

final wikiAgentServiceProvider = Provider<GemmaWikiService>((ref) {
  return GemmaWikiService(ref.read(wikiStorageServiceProvider));
});

final wikiAutoLoadModelProvider = Provider<bool>((ref) => true);

final wikiTreeProvider = FutureProvider.family<List<WikiTreeNode>, int>(
  (ref, sessionId) => ref.read(wikiStorageServiceProvider).buildTree(sessionId),
);

final wikiPageProvider = FutureProvider.family<WikiEntry?, WikiPageRequest>(
  (ref, request) => ref
      .read(wikiStorageServiceProvider)
      .readEntry(request.sessionId, request.relativePath),
);

final wikiHasContentProvider = FutureProvider.family<bool, int>(
  (ref, sessionId) => ref.read(wikiStorageServiceProvider).hasWiki(sessionId),
);

class WikiActionController extends StateNotifier<WikiActionState> {
  WikiActionController(this._ref, this._sessionId)
      : super(const WikiActionState.idle());

  final Ref _ref;
  final int _sessionId;

  Future<void> ingest(
    GemmaInferenceService service, {
    bool cleanFirst = false,
  }) async {
    await _run(
      runType: WikiRunType.ingest,
      service: service,
      beforeRun: cleanFirst
          ? (appendLine) async {
              appendLine('Clearing existing wiki pages...');
              await _ref
                  .read(wikiStorageServiceProvider)
                  .clearSessionWiki(_sessionId);
              appendLine('Wiki cleared. Building from scratch...');
            }
          : null,
      runner: (
          {required bundle,
          required onLine,
          required onPlan,
          required onStepComplete}) {
        return _ref.read(wikiAgentServiceProvider).runIngest(
              service: service,
              session: bundle.session,
              materials: bundle.materials,
              sessionId: _sessionId,
              onLine: onLine,
              onPlan: onPlan,
              onStepComplete: onStepComplete,
            );
      },
    );
  }

  Future<void> lint(GemmaInferenceService service) async {
    await _run(
      runType: WikiRunType.lint,
      service: service,
      runner: (
          {required bundle,
          required onLine,
          required onPlan,
          required onStepComplete}) {
        return _ref.read(wikiAgentServiceProvider).runLint(
              service: service,
              session: bundle.session,
              materials: bundle.materials,
              sessionId: _sessionId,
              onLine: onLine,
              onPlan: onPlan,
              onStepComplete: onStepComplete,
            );
      },
    );
  }

  Future<void> _run({
    required WikiRunType runType,
    required GemmaInferenceService service,
    Future<void> Function(void Function(String line) appendLine)? beforeRun,
    required Future<WikiAgentResult> Function({
      required SessionBundle bundle,
      required void Function(String line) onLine,
      required void Function(List<String> steps) onPlan,
      required void Function(int index) onStepComplete,
    }) runner,
  }) async {
    if (state.isBusy) return;

    final bundle = await _ref.read(sessionBundleProvider(_sessionId).future);
    if (bundle == null) {
      state = WikiActionState(
        status: WikiActionStatus.error,
        runType: runType,
        lines: const [],
        error: 'Session not found.',
        startedAt: DateTime.now(),
        completedAt: DateTime.now(),
      );
      return;
    }

    if (runType == WikiRunType.ingest && bundle.materials.isEmpty) {
      state = WikiActionState(
        status: WikiActionStatus.error,
        runType: runType,
        lines: const [],
        error: 'Add study materials first.',
        startedAt: DateTime.now(),
        completedAt: DateTime.now(),
      );
      return;
    }

    state = WikiActionState(
      status: WikiActionStatus.running,
      runType: runType,
      startedAt: DateTime.now(),
      lines: [
        runType == WikiRunType.ingest
            ? 'Starting wiki ingest...'
            : 'Starting wiki lint...',
      ],
    );

    try {
      if (beforeRun != null) {
        await beforeRun((line) {
          state = state.copyWith(lines: [...state.lines, line]);
        });
      }

      final result = await runner(
        bundle: bundle,
        onLine: (line) {
          state = state.copyWith(lines: [...state.lines, line]);
        },
        onPlan: (steps) {
          state = state.copyWith(plan: steps);
        },
        onStepComplete: (index) {
          state =
              state.copyWith(completedSteps: {...state.completedSteps, index});
        },
      );

      _ref.invalidate(wikiTreeProvider(_sessionId));
      _ref.invalidate(wikiHasContentProvider(_sessionId));
      _ref.invalidate(sessionBundleProvider(_sessionId));

      state = state.copyWith(
        status: WikiActionStatus.success,
        touchedPaths: [...result.touchedPaths, ...result.deletedPaths]..sort(),
        completedAt: DateTime.now(),
        lines: [
          ...state.lines,
          result.summary.isEmpty ? 'Wiki action complete.' : result.summary,
          if (result.unresolvedIssues.isNotEmpty) ...result.unresolvedIssues
              .map((issue) => 'Unresolved: $issue'),
        ],
      );
    } catch (error) {
      state = state.copyWith(
        status: WikiActionStatus.error,
        error: error.toString(),
        completedAt: DateTime.now(),
        lines: [...state.lines, 'Action failed.'],
      );
    }
  }
}

final wikiActionControllerProvider =
    StateNotifierProvider.family<WikiActionController, WikiActionState, int>(
  (ref, sessionId) => WikiActionController(ref, sessionId),
);
