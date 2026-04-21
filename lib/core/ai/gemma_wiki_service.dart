import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart' as gemma;
import 'package:intl/intl.dart';

import '../models/models.dart';
import 'gemma_inference_service.dart';
import 'material_preprocessor.dart';
import 'response_loop_guard.dart';
import 'wiki_storage_service.dart';

typedef WikiAgentLineCallback = void Function(String line);

class WikiAgentResult {
  final List<String> touchedPaths;
  final List<String> deletedPaths;
  final List<String> unresolvedIssues;
  final String summary;

  const WikiAgentResult({
    required this.touchedPaths,
    required this.deletedPaths,
    required this.summary,
    this.unresolvedIssues = const [],
  });
}

class _AgentSessionResult {
  final List<String> touchedPaths;
  final List<String> deletedPaths;
  final List<String> unresolvedIssues;
  final String summary;

  const _AgentSessionResult({
    required this.touchedPaths,
    required this.deletedPaths,
    required this.unresolvedIssues,
    required this.summary,
  });
}

class GemmaWikiService {
  GemmaWikiService(
    this._storage, {
    GemmaInferenceService Function()? workerServiceFactory,
  }) : _workerServiceFactory = workerServiceFactory ?? GemmaInferenceService.new;

  final WikiStorageService _storage;
  final GemmaInferenceService Function() _workerServiceFactory;

  static const _planTool = gemma.Tool(
    name: 'plan',
    description:
        'Declare your complete plan before starting any work. Call ONCE at the very beginning. '
        'List every step you intend to take in order, with one sentence per step.',
    parameters: {
      'type': 'object',
      'properties': {
        'steps': {
          'type': 'array',
          'items': {'type': 'string'},
          'description':
              'Ordered list of single-sentence steps, one step per line, e.g. ["List existing pages", "Write concepts/photosynthesis.md", "Update index.md", "Finish"]',
        },
      },
      'required': ['steps'],
    },
  );

  static const _completeStepTool = gemma.Tool(
    name: 'complete_step',
    description:
        'Mark a planned worker step as done. Call after finishing each step from your plan.',
    parameters: {
      'type': 'object',
      'properties': {
        'index': {
          'type': 'integer',
          'description': '0-based index of the completed step from your plan',
        },
      },
      'required': ['index'],
    },
  );

  static const _spawnWorkerTool = gemma.Tool(
    name: 'spawn_worker',
    description:
        'Spawn one sequential worker agent for a single markdown task. '
        'Use this after planning. Provide one concrete task bundle at a time and do not overlap workers.',
    parameters: {
      'type': 'object',
      'properties': {
        'task': {
          'type': 'string',
          'description':
              'Concrete worker task, such as writing specific pages or linting a small slice of the wiki.',
        },
        'stepIndex': {
          'type': 'integer',
          'description':
              'Optional 0-based index of the planned step that this worker completes.',
        },
        'focusPaths': {
          'type': 'array',
          'items': {'type': 'string'},
          'description':
              'Optional existing wiki paths the worker should inspect first.',
        },
      },
      'required': ['task'],
    },
  );

  static const _listPagesTool = gemma.Tool(
    name: 'list_existing_pages',
    description:
        'List all existing markdown pages in the current session wiki. Call this first to understand what already exists before writing or updating.',
    parameters: {
      'type': 'object',
      'properties': {},
    },
  );

  static const _readPageTool = gemma.Tool(
    name: 'read_existing_page',
    description:
        'Read the full content of one existing wiki page. Use this before updating a page to avoid overwriting useful content.',
    parameters: {
      'type': 'object',
      'properties': {
        'path': {
          'type': 'string',
          'description':
              'Relative path to the wiki page, e.g. sources/chapter1.md or concepts/photosynthesis.md',
        },
      },
      'required': ['path'],
    },
  );

  static const _writePageTool = gemma.Tool(
    name: 'write_markdown_file',
    description:
        'Write a wiki page. Include YAML frontmatter and markdown. Allowed: index.md, log.md, sources/*.md, concepts/*.md, entities/*.md, syntheses/*.md, reviews/*.md.',
    parameters: {
      'type': 'object',
      'properties': {
        'path': {
          'type': 'string',
          'description': 'Relative wiki path, e.g. sources/intro.md',
        },
        'content': {
          'type': 'string',
          'description': 'Markdown content including YAML frontmatter.',
        },
      },
      'required': ['path', 'content'],
    },
  );

  static const _deletePageTool = gemma.Tool(
    name: 'delete_markdown_file',
    description:
        'Delete one obsolete or duplicate wiki page. Only use when a page is truly redundant or superseded.',
    parameters: {
      'type': 'object',
      'properties': {
        'path': {
          'type': 'string',
          'description':
              'Relative path of the wiki file to delete, e.g. sources/old_draft.md',
        },
      },
      'required': ['path'],
    },
  );

  static const _finishTool = gemma.Tool(
    name: 'finish_run',
    description:
        'Call when all wiki changes or delegated worker tasks are done. Provide a one-line summary and any unresolved issues.',
    parameters: {
      'type': 'object',
      'properties': {
        'summary': {
          'type': 'string',
          'description': 'One-line summary of changes made.',
        },
        'unresolvedIssues': {
          'type': 'array',
          'items': {'type': 'string'},
          'description':
              'Optional issues that remain unresolved after the run.',
        },
      },
      'required': ['summary'],
    },
  );

  Future<WikiAgentResult> runIngest({
    required GemmaInferenceService service,
    required Session session,
    required List<StudyMaterial> materials,
    required int sessionId,
    WikiAgentLineCallback? onLine,
    void Function(List<String> steps)? onPlan,
    void Function(int index)? onStepComplete,
  }) async {
    return _runDelegatedManager(
      service: service,
      session: session,
      materials: materials,
      sessionId: sessionId,
      prompt: _buildManagerPrompt(session, materials, mode: 'ingest'),
      systemInstruction:
          _buildManagerSystemInstruction(session, mode: 'ingest'),
      onLine: onLine,
      onPlan: onPlan,
      onStepComplete: onStepComplete,
    );
  }

  Future<WikiAgentResult> runLint({
    required GemmaInferenceService service,
    required Session session,
    required List<StudyMaterial> materials,
    required int sessionId,
    WikiAgentLineCallback? onLine,
    void Function(List<String> steps)? onPlan,
    void Function(int index)? onStepComplete,
  }) async {
    return _runDelegatedManager(
      service: service,
      session: session,
      materials: materials,
      sessionId: sessionId,
      prompt: _buildManagerPrompt(session, materials, mode: 'lint'),
      systemInstruction: _buildManagerSystemInstruction(session, mode: 'lint'),
      onLine: onLine,
      onPlan: onPlan,
      onStepComplete: onStepComplete,
    );
  }

  Future<WikiAgentResult> _runDelegatedManager({
    required GemmaInferenceService service,
    required Session session,
    required List<StudyMaterial> materials,
    required int sessionId,
    required String prompt,
    required String systemInstruction,
    WikiAgentLineCallback? onLine,
    void Function(List<String> steps)? onPlan,
    void Function(int index)? onStepComplete,
  }) async {
    final prepared = await MaterialPreprocessor.prepare(materials);
    final managerResult = await _runAgentSession(
      service: service,
      session: session,
      materials: materials,
      prepared: prepared,
      sessionId: sessionId,
      mode: 'manager',
      role: 'manager',
      prompt: prompt,
      systemInstruction: systemInstruction,
      supportImage: false,
      tools: const [
        _planTool,
        _completeStepTool,
        _listPagesTool,
        _readPageTool,
        _spawnWorkerTool,
        _finishTool,
      ],
      onLine: onLine,
      onPlan: onPlan,
      onStepComplete: onStepComplete,
      executeToolCall: (response) => _executeManagerToolCall(
        service: service,
        session: session,
        materials: materials,
        prepared: prepared,
        sessionId: sessionId,
        response: response,
        onLine: onLine,
      ),
    );

    return WikiAgentResult(
      touchedPaths: managerResult.touchedPaths,
      deletedPaths: managerResult.deletedPaths,
      unresolvedIssues: managerResult.unresolvedIssues,
      summary: managerResult.summary,
    );
  }

  Future<WikiAgentResult> _run({
    required GemmaInferenceService service,
    required Session session,
    required List<StudyMaterial> materials,
    required int sessionId,
    required String prompt,
    required String systemInstruction,
    WikiAgentLineCallback? onLine,
    void Function(List<String> steps)? onPlan,
    void Function(int index)? onStepComplete,
  }) async {
    final prepared = await MaterialPreprocessor.prepare(materials);
    final hasImages = prepared.any((item) => item.images.isNotEmpty);
    final totalImages = prepared.fold(0, (sum, p) => sum + p.images.length);
    final guard = ResponseLoopGuard();
    debugPrint(
        '[WikiAgent] start: materials=${materials.length} images=$totalImages hasImages=$hasImages');

    await service.createSession(
      systemInstruction: systemInstruction,
      temperature: 1,
      topK: 1,
      supportImage: hasImages,
      promptDialect: gemma.PromptDialect.gemma4,
      toolChoice: gemma.ToolChoice.required,
      tools: const [
        _planTool,
        _completeStepTool,
        _listPagesTool,
        _readPageTool,
        _writePageTool,
        _deletePageTool,
        _finishTool,
      ],
      supportsFunctionCalls: true,
      isThinking: false,
    );

    // Queue all images to be included with first user message
    final allImages = <Uint8List>[];
    for (final item in prepared) {
      allImages.addAll(item.images);
    }
    if (allImages.isNotEmpty) {
      debugPrint('[WikiAgent] Queuing ${allImages.length} images');
      await service.addImagesToQueue(allImages);
    }
    await service.addTextQuery(prompt);
    debugPrint('[WikiAgent] session ready, generating (turn 0)');

    final touchedPaths = <String>{};
    final deletedPaths = <String>{};
    var summary = '';
    var plainTextRetry = 0;
    var lastPlainText = '';

    for (var turn = 0; turn < 48; turn++) {
      lastPlainText = ''; // reset per turn
      var sawToolCall = false;
      final toolResults = <Map<String, Object?>>[];

      await for (final response in service.generateResponses()) {
        if (response is gemma.ThinkingResponse) {
          // per-token thinking — skip
        } else if (response is gemma.TextResponse) {
          final error = guard.recordTextToken(response.token);
          if (error != null) {
            throw StateError(error);
          }
          lastPlainText += response.token;
        } else if (response is gemma.FunctionCallResponse) {
          final error = guard.recordToolCall(response.name, response.args);
          if (error != null) {
            throw StateError(error);
          }
          debugPrint(
              '[WikiAgent] tool call: name=${response.name} args=${response.args}');
          sawToolCall = true;
          final result = await _executeToolCall(
            sessionId: sessionId,
            response: response,
            touchedPaths: touchedPaths,
            deletedPaths: deletedPaths,
          );
          toolResults.add(result);
          _emitLine(onLine, result['message'] as String? ?? response.name);
          if (response.name == 'finish_run') {
            summary = (response.args['summary'] as String?)?.trim() ?? '';
            debugPrint('[WikiAgent] finish_run called. summary=$summary');
            return WikiAgentResult(
              touchedPaths: touchedPaths.toList()..sort(),
              deletedPaths: deletedPaths.toList()..sort(),
              summary: summary,
            );
          }
        } else if (response is gemma.ParallelFunctionCallResponse) {
          sawToolCall = true;
          for (final call in response.calls) {
            final error = guard.recordToolCall(call.name, call.args);
            if (error != null) {
              throw StateError(error);
            }
            final result = await _executeToolCall(
              sessionId: sessionId,
              response: call,
              touchedPaths: touchedPaths,
              deletedPaths: deletedPaths,
            );
            toolResults.add(result);
            _emitLine(onLine, result['message'] as String? ?? call.name);
            if (call.name == 'finish_run') {
              summary = (call.args['summary'] as String?)?.trim() ?? '';
              debugPrint('[WikiAgent] finish_run called. summary=$summary');
              return WikiAgentResult(
                touchedPaths: touchedPaths.toList()..sort(),
                deletedPaths: deletedPaths.toList()..sort(),
                summary: summary,
              );
            }
          }
        }
      }

      if (!sawToolCall) {
        plainTextRetry++;
        if (plainTextRetry >= 5) {
          final preview = lastPlainText.isEmpty
              ? '<empty stream or no text emitted>'
              : '"${lastPlainText.substring(0, lastPlainText.length.clamp(0, 100))}"';
          debugPrint(
              '[WikiAgent] FAILURE after $plainTextRetry text-only turns. '
              'Last text: $preview. Touched: ${touchedPaths.length}, deleted: ${deletedPaths.length}. '
              'Touched paths: ${touchedPaths.toList()}. Deleted paths: ${deletedPaths.toList()}.');
          throw StateError(
            'Wiki agent stopped without calling finish_run after $plainTextRetry text-only turns. '
            'Last text: $preview. '
            'Touched: ${touchedPaths.length}, deleted: ${deletedPaths.length}.',
          );
        }
        debugPrint(
            '[WikiAgent] text-only turn $plainTextRetry, nudging with noTool query. '
            'lastTextPreview: "${lastPlainText.substring(0, lastPlainText.length.clamp(0, 80))}"');
        await service.addTextQuery(
          'You must call a tool now. Call list_existing_pages or write_markdown_file with valid arguments.',
          noTool: true,
        );
        continue;
      }

      plainTextRetry = 0;
      for (final result in toolResults) {
        final toolName = result['tool'] as String? ?? 'unknown';
        debugPrint(
            '[WikiAgent] tool result: $toolName -> ${result['message']}');
        if (result['plan'] != null) {
          onPlan?.call((result['plan'] as List).cast<String>());
        }
        if (result['completedIndex'] != null) {
          onStepComplete?.call(result['completedIndex'] as int);
        }
        await service.addToolResponse(toolName: toolName, response: result);
      }
    }

    debugPrint('[WikiAgent] FAILURE: exceeded 48 steps. '
        'Touched: ${touchedPaths.toList()}. Deleted: ${deletedPaths.toList()}.');
    throw StateError(
      'Wiki agent exceeded step limit (48) before finish_run. '
      'Touched: ${touchedPaths.length}, deleted: ${deletedPaths.length}.',
    );
  }

  Future<Map<String, Object?>> _executeToolCall({
    required int sessionId,
    required gemma.FunctionCallResponse response,
    required Set<String> touchedPaths,
    required Set<String> deletedPaths,
  }) async {
    switch (response.name) {
      case 'plan':
        final steps =
            (response.args['steps'] as List<dynamic>?)?.cast<String>() ?? [];
        return {
          'tool': response.name,
          'plan': steps,
          'message':
              'Plan: ${steps.length} step${steps.length == 1 ? '' : 's'}',
        };
      case 'complete_step':
        final index = (response.args['index'] as num?)?.toInt() ?? 0;
        return {
          'tool': response.name,
          'completedIndex': index,
          'message': 'Step ${index + 1} done',
        };
      case 'list_existing_pages':
        final entries = await _storage.readAllEntries(sessionId);
        return {
          'tool': response.name,
          'paths': entries
              .map((entry) => {
                    'path': entry.relativePath,
                    'title': entry.title,
                    'category': entry.category,
                    'materialIds': entry.materialIds,
                  })
              .toList(growable: false),
          'message': 'Listed ${entries.length} wiki pages.',
        };
      case 'read_existing_page':
        final rawPath = response.args['path'] as String? ?? '';
        try {
          final entry = await _storage.readEntry(sessionId, rawPath);
          final normalizedPath = _storage.normalizeRelativePath(rawPath);
          return {
            'tool': response.name,
            'path': normalizedPath,
            'found': entry != null,
            'content': entry?.rawContent ?? '',
            'message': entry == null
                ? 'Page not found: $normalizedPath'
                : 'Read page ${entry.relativePath}.',
          };
        } on FormatException catch (error) {
          return {
            'tool': response.name,
            'message': 'Invalid wiki path. Got: "$rawPath". ${error.message}',
          };
        }
      case 'write_markdown_file':
        final path = response.args['path'] as String? ?? '';
        final content = response.args['content'] as String? ?? '';
        try {
          final entry = await _storage.writeMarkdownFile(
            sessionId: sessionId,
            relativePath: path,
            content: content,
          );
          touchedPaths.add(entry.relativePath);
          deletedPaths.remove(entry.relativePath);
          return {
            'tool': response.name,
            'path': entry.relativePath,
            'message': 'Wrote ${entry.relativePath}.',
          };
        } on FormatException catch (error) {
          return {
            'tool': response.name,
            'message': 'Invalid wiki path. Got: "$path". ${error.message}',
          };
        }
      case 'delete_markdown_file':
        final path = response.args['path'] as String? ?? '';
        try {
          final normalized = _storage.normalizeRelativePath(path);
          await _storage.deleteMarkdownFile(
            sessionId: sessionId,
            relativePath: normalized,
          );
          deletedPaths.add(normalized);
          touchedPaths.remove(normalized);
          return {
            'tool': response.name,
            'path': normalized,
            'message': 'Deleted $normalized.',
          };
        } on FormatException catch (error) {
          return {
            'tool': response.name,
            'message': 'Invalid wiki path. Got: "$path". ${error.message}',
          };
        }
      case 'finish_run':
        return {
          'tool': response.name,
          'summary': response.args['summary'] ?? '',
          'message': 'Finish requested.',
        };
      default:
        return {
          'tool': response.name,
          'message': 'Ignored unsupported tool ${response.name}.',
        };
    }
  }

  void _emitLine(WikiAgentLineCallback? onLine, String rawLine) {
    final line = rawLine.trim();
    if (line.isEmpty) return;
    onLine?.call(line);
  }

  String _buildSystemInstruction(Session session, {required String mode}) {
    final categories = [
      'sources',
      'concepts',
      'entities',
      'syntheses',
      'reviews',
    ].join(', ');
    final currentDate = DateFormat('yyyy/MM/dd HH:mm z').format(DateTime.now());
    final modeRules = switch (mode) {
      'ingest' => '''
MODE: ingest
- Build and refine the wiki from the provided materials.
- Prefer updating existing pages over creating duplicates.
- Use concepts/entities/syntheses to generalize across sources.
- End with finish_run after index.md and log.md are updated.''',
      'lint' => '''
MODE: lint
- Audit the wiki for contradictions, stale claims, weak links, orphan pages, and bad category placement.
- Fix safe issues directly.
- Write one review page under reviews/ with findings, fixes, unresolved issues, and next targets.
- End with finish_run after index.md and log.md are updated.''',
      _ => '''
MODE: $mode
- Follow the same wiki rules, but prefer the smallest safe set of edits.''',
    };

    return '''
You are the wiki builder and maintainer for "${session.title}" (Grade ${session.gradeOverride}).
Output ONLY tool calls. Never emit free text, reasoning, or explanations.
Every response must be a tool call using one of the provided tools.

GOAL
Maintain a persistent, interconnected knowledge base that is accurate, readable for Grade ${session.gradeOverride}, and easy to navigate.

HARD RULES
- list_existing_pages must be the first tool call in every run.
- plan() must come after list_existing_pages and before any writes.
- Call read_existing_page before editing an existing file.
- Use finish_run only when all wiki changes are complete.
- Do not invent paths, categories, or tools.
- Use only these categories: $categories.
- Keep filenames lowercase kebab-case when possible.

$modeRules

PAGE ROLES
- sources: one page per study material, focused on what the material says.
- concepts: abstractions, definitions, repeated ideas, and principles.
- entities: concrete named things such as people, places, events, objects, or species.
- syntheses: cross-source comparisons, timelines, patterns, and conclusions.
- reviews: lint findings, gaps, contradictions, and follow-up questions.

QUALITY BAR
- Write for Grade ${session.gradeOverride} comprehension.
- Prefer short sentences, clear headers, and concrete examples.
- Define jargon on first use.
- Cross-link both directions when a relationship matters.
- Never silently overwrite a contradiction; preserve it in syntheses or log.md.
- Avoid repeating the same description across pages. Link instead.

PLAN AND OUTPUT STYLE
- In plan(), include only the concrete steps you will actually do now.
- Keep each step to one sentence.
- After each step, call complete_step(index).
- Prefer updating index.md and log.md near the end of the run.
- The final tool call must be finish_run with a one-line summary.

FRONTMATTER
Use YAML frontmatter on wiki pages with:
---
title: [Page Title]
category: [sources|concepts|entities|syntheses|reviews]
slug: [kebab-case-url-slug]
materialIds: [comma-separated source IDs that informed this page]
lastUpdated: YYYY-MM-DD
status: [draft|active|deprecated]
---

CURRENT DATE
$currentDate
''';
  }

  String _buildIngestPrompt(Session session, List<StudyMaterial> materials) {
    final hasPhotos = materials.any((m) => m.kind == MaterialKind.photo);
    final buffer = StringBuffer()
      ..writeln(
          'Ingest all session materials into the wiki. Update existing pages when appropriate instead of duplicating them.')
      ..writeln()
      ..writeln('Session: ${session.title}')
      ..writeln('Grade: ${session.gradeOverride}')
      ..writeln('Material count: ${materials.length}')
      ..writeln()
      ..writeln('Materials:')
      ..writeln(_materialsContext(materials))
      ..writeln();
    if (hasPhotos) {
      buffer.writeln(
          'Note: Image attachments for photo materials are included above. Use them to extract content for wiki pages.');
      buffer.writeln();
    }
    buffer.writeln(
        'Start by listing existing pages if needed. Then read any page you need, write/update wiki pages, update index.md and log.md, and finish.');
    return buffer.toString();
  }

  String _buildLintPrompt(Session session) {
    return '''
Run a wiki lint pass for "${session.title}".

Look for:
- contradictions
- stale claims
- missing cross-links
- orphan pages
- weak category placement
- missing reviews/index coverage

When safe, fix wiki pages directly. Also write one lint report under reviews/ with findings, fixes applied, unresolved issues, and suggested next targets. Update index.md and log.md. Finish when done.
''';
  }

  String _materialsContext(List<StudyMaterial> materials) {
    final buffer = StringBuffer();
    for (final material in materials) {
      buffer
        ..writeln(
            '- [${material.id}] ${material.title} (${material.kind.name})')
        ..writeln('  Preview: ${material.preview}');
      if (material.kind == MaterialKind.text) {
        final trimmed = material.content.trim();
        final snippet = trimmed.length > 1400
            ? '${trimmed.substring(0, 1400)}...'
            : trimmed;
        buffer.writeln('  Content: $snippet');
      } else if (material.kind == MaterialKind.photo) {
        final imageCount =
            material.content.split('\n').where((p) => p.isNotEmpty).length;
        buffer.writeln('  Images: $imageCount image(s) attached');
      }
    }
    return buffer.toString().trim();
  }

  Future<_AgentSessionResult> _runAgentSession({
    required GemmaInferenceService service,
    required Session session,
    required List<StudyMaterial> materials,
    required List<PreparedMaterial> prepared,
    required int sessionId,
    required String mode,
    required String role,
    required String prompt,
    required String systemInstruction,
    required bool supportImage,
    required List<gemma.Tool> tools,
    required Future<Map<String, Object?>> Function(
      gemma.FunctionCallResponse response,
    ) executeToolCall,
    WikiAgentLineCallback? onLine,
    void Function(List<String> steps)? onPlan,
    void Function(int index)? onStepComplete,
    int maxTurns = 48,
  }) async {
    final hasImages = supportImage && prepared.any((item) => item.images.isNotEmpty);
    final totalImages = prepared.fold<int>(0, (sum, p) => sum + p.images.length);
    final guard = ResponseLoopGuard();
    debugPrint(
      '[WikiAgent][$role][$sessionId] start: materials=${materials.length} images=$totalImages hasImages=$hasImages',
    );

    await service.createSession(
      systemInstruction: systemInstruction,
      temperature: 0.2,
      topK: 1,
      supportImage: hasImages,
      promptDialect: gemma.PromptDialect.gemma4,
      toolChoice: gemma.ToolChoice.required,
      tools: tools,
      supportsFunctionCalls: true,
      isThinking: false,
    );

    final allImages = <Uint8List>[];
    for (final item in prepared) {
      allImages.addAll(item.images);
    }
    if (hasImages && allImages.isNotEmpty) {
      debugPrint('[WikiAgent][$role][$sessionId] Queuing ${allImages.length} images');
      await service.addImagesToQueue(allImages);
    }
    await service.addTextQuery(prompt);
    debugPrint('[WikiAgent][$role][$sessionId] session ready, generating (turn 0)');

    final touchedPaths = <String>{};
    final deletedPaths = <String>{};
    final unresolvedIssues = <String>{};
    var summary = '';
    var plainTextRetry = 0;
    var lastPlainText = '';

    for (var turn = 0; turn < maxTurns; turn++) {
      lastPlainText = '';
      var sawToolCall = false;
      final toolResults = <Map<String, Object?>>[];

      await for (final response in service.generateResponses()) {
        if (response is gemma.ThinkingResponse) {
          continue;
        } else if (response is gemma.TextResponse) {
          final error = guard.recordTextToken(response.token);
          if (error != null) {
            throw StateError(error);
          }
          lastPlainText += response.token;
        } else if (response is gemma.FunctionCallResponse) {
          final error = guard.recordToolCall(response.name, response.args);
          if (error != null) {
            throw StateError(error);
          }
          debugPrint(
            '[WikiAgent][$role][$sessionId] tool call: name=${response.name} args=${response.args}',
          );
          sawToolCall = true;
          final result = await executeToolCall(response);
          toolResults.add(result);
          _collectToolResult(
            result,
            touchedPaths: touchedPaths,
            deletedPaths: deletedPaths,
            unresolvedIssues: unresolvedIssues,
          );
          _emitLine(onLine, result['message'] as String? ?? response.name);
          if (response.name == 'finish_run') {
            summary = (result['summary'] as String?)?.trim() ??
                (response.args['summary'] as String?)?.trim() ??
                '';
            final finishIssues = _stringList(
              result['unresolvedIssues'] ?? response.args['unresolvedIssues'],
            );
            unresolvedIssues.addAll(finishIssues);
            debugPrint(
              '[WikiAgent][$role][$sessionId] finish_run called. summary=$summary unresolved=${unresolvedIssues.length}',
            );
            return _AgentSessionResult(
              touchedPaths: touchedPaths.toList()..sort(),
              deletedPaths: deletedPaths.toList()..sort(),
              unresolvedIssues: unresolvedIssues.toList()..sort(),
              summary: summary,
            );
          }
        } else if (response is gemma.ParallelFunctionCallResponse) {
          sawToolCall = true;
          for (final call in response.calls) {
            final error = guard.recordToolCall(call.name, call.args);
            if (error != null) {
              throw StateError(error);
            }
            final result = await executeToolCall(call);
            toolResults.add(result);
            _collectToolResult(
              result,
              touchedPaths: touchedPaths,
              deletedPaths: deletedPaths,
              unresolvedIssues: unresolvedIssues,
            );
            _emitLine(onLine, result['message'] as String? ?? call.name);
            if (call.name == 'finish_run') {
              summary = (result['summary'] as String?)?.trim() ??
                  (call.args['summary'] as String?)?.trim() ??
                  '';
              final finishIssues = _stringList(
                result['unresolvedIssues'] ?? call.args['unresolvedIssues'],
              );
              unresolvedIssues.addAll(finishIssues);
              debugPrint(
                '[WikiAgent][$role][$sessionId] finish_run called. summary=$summary unresolved=${unresolvedIssues.length}',
              );
              return _AgentSessionResult(
                touchedPaths: touchedPaths.toList()..sort(),
                deletedPaths: deletedPaths.toList()..sort(),
                unresolvedIssues: unresolvedIssues.toList()..sort(),
                summary: summary,
              );
            }
          }
        }
      }

      if (!sawToolCall) {
        plainTextRetry++;
        if (plainTextRetry >= 5) {
          final preview = lastPlainText.isEmpty
              ? '<empty stream or no text emitted>'
              : '"${lastPlainText.substring(0, lastPlainText.length.clamp(0, 100))}"';
          debugPrint(
            '[WikiAgent][$role][$sessionId] FAILURE after $plainTextRetry text-only turns. '
            'Last text: $preview. Touched: ${touchedPaths.length}, deleted: ${deletedPaths.length}. '
            'Touched paths: ${touchedPaths.toList()}. Deleted paths: ${deletedPaths.toList()}.',
          );
          throw StateError(
            'Wiki agent stopped without calling finish_run after $plainTextRetry text-only turns. '
            'Last text: $preview. '
            'Touched: ${touchedPaths.length}, deleted: ${deletedPaths.length}.',
          );
        }
        debugPrint(
          '[WikiAgent][$role][$sessionId] text-only turn $plainTextRetry, nudging with noTool query. '
          'lastTextPreview: "${lastPlainText.substring(0, lastPlainText.length.clamp(0, 80))}"',
        );
        await service.addTextQuery(
          'You must call a tool now. Use the assigned wiki tools only.',
          noTool: true,
        );
        continue;
      }

      plainTextRetry = 0;
      for (final result in toolResults) {
        final toolName = result['tool'] as String? ?? 'unknown';
        debugPrint(
          '[WikiAgent][$role][$sessionId] tool result: $toolName -> ${result['message']}',
        );
        if (result['plan'] != null) {
          onPlan?.call((result['plan'] as List).cast<String>());
        }
        if (result['completedIndex'] != null) {
          onStepComplete?.call(result['completedIndex'] as int);
        }
        await service.addToolResponse(toolName: toolName, response: result);
      }
    }

    debugPrint(
      '[WikiAgent][$role][$sessionId] FAILURE: exceeded $maxTurns steps. '
      'Touched: ${touchedPaths.toList()}. Deleted: ${deletedPaths.toList()}.',
    );
    throw StateError(
      'Wiki agent exceeded step limit ($maxTurns) before finish_run. '
      'Touched: ${touchedPaths.length}, deleted: ${deletedPaths.length}.',
    );
  }

  Future<Map<String, Object?>> _executeManagerToolCall({
    required GemmaInferenceService service,
    required Session session,
    required List<StudyMaterial> materials,
    required List<PreparedMaterial> prepared,
    required int sessionId,
    required gemma.FunctionCallResponse response,
    WikiAgentLineCallback? onLine,
  }) async {
    switch (response.name) {
      case 'plan':
        final steps =
            (response.args['steps'] as List<dynamic>?)?.cast<String>() ?? [];
        return {
          'tool': response.name,
          'plan': steps,
          'message':
              'Plan: ${steps.length} step${steps.length == 1 ? '' : 's'}',
        };
      case 'complete_step':
        final index = (response.args['index'] as num?)?.toInt() ?? 0;
        return {
          'tool': response.name,
          'completedIndex': index,
          'message': 'Step ${index + 1} done',
        };
      case 'list_existing_pages':
        final entries = await _storage.readAllEntries(sessionId);
        return {
          'tool': response.name,
          'paths': entries
              .map((entry) => {
                    'path': entry.relativePath,
                    'title': entry.title,
                    'category': entry.category,
                    'materialIds': entry.materialIds,
                  })
              .toList(growable: false),
          'message': 'Listed ${entries.length} wiki pages.',
        };
      case 'read_existing_page':
        final rawPath = response.args['path'] as String? ?? '';
        try {
          final entry = await _storage.readEntry(sessionId, rawPath);
          final normalizedPath = _storage.normalizeRelativePath(rawPath);
          return {
            'tool': response.name,
            'path': normalizedPath,
            'found': entry != null,
            'content': entry?.rawContent ?? '',
            'message': entry == null
                ? 'Page not found: $normalizedPath'
                : 'Read page ${entry.relativePath}.',
          };
        } on FormatException catch (error) {
          return {
            'tool': response.name,
            'message': 'Invalid wiki path. Got: "$rawPath". ${error.message}',
          };
        }
      case 'spawn_worker':
        final task = (response.args['task'] as String?)?.trim() ?? '';
        final stepIndex = (response.args['stepIndex'] as num?)?.toInt();
        final focusPaths = _stringList(response.args['focusPaths']);
        if (task.isEmpty) {
          return {
            'tool': response.name,
            'message': 'Worker task is required.',
          };
        }
        final prefixedOnLine = onLine == null
            ? null
            : (String line) => _emitLine(
                  onLine,
                  'Worker${stepIndex == null ? '' : ' ${stepIndex + 1}'}: $line',
                );
        final worker = await _runWorkerTask(
          service: _workerServiceFactory(),
          session: session,
          materials: materials,
          prepared: prepared,
          sessionId: sessionId,
          mode: _modeFromTask(task),
          task: task,
          stepIndex: stepIndex,
          focusPaths: focusPaths,
          onLine: prefixedOnLine,
        );
        return {
          'tool': response.name,
          'summary': worker.summary,
          'touchedPaths': worker.touchedPaths,
          'deletedPaths': worker.deletedPaths,
          'unresolvedIssues': worker.unresolvedIssues,
          if (stepIndex != null) 'completedIndex': stepIndex,
          'message': worker.unresolvedIssues.isEmpty
              ? 'Worker completed${stepIndex == null ? '' : ' step ${stepIndex + 1}'}: ${worker.summary}'
              : 'Worker completed${stepIndex == null ? '' : ' step ${stepIndex + 1}'} with unresolved issues.',
        };
      case 'finish_run':
        return {
          'tool': response.name,
          'summary': response.args['summary'] ?? '',
          'unresolvedIssues':
              _stringList(response.args['unresolvedIssues']),
          'message': 'Finish requested.',
        };
      default:
        return {
          'tool': response.name,
          'message': 'Ignored unsupported tool ${response.name}.',
        };
    }
  }

  Future<_AgentSessionResult> _runWorkerTask({
    required GemmaInferenceService service,
    required Session session,
    required List<StudyMaterial> materials,
    required List<PreparedMaterial> prepared,
    required int sessionId,
    required String mode,
    required String task,
    required List<String> focusPaths,
    required int? stepIndex,
    required WikiAgentLineCallback? onLine,
  }) async {
    var shouldDispose = false;
    try {
      if (!service.isInitialized) {
        await service.initialize();
        shouldDispose = true;
      }

      final workerPrompt = _buildWorkerPrompt(
        session,
        materials: materials,
        mode: mode,
        task: task,
        focusPaths: focusPaths,
        stepIndex: stepIndex,
      );
      final workerSystemInstruction =
          _buildWorkerSystemInstruction(session, mode: mode, task: task);
      return await _runAgentSession(
        service: service,
        session: session,
        materials: materials,
        prepared: prepared,
        sessionId: sessionId,
        mode: mode,
        role: 'worker',
        prompt: workerPrompt,
        systemInstruction: workerSystemInstruction,
        supportImage: true,
        tools: const [
          _listPagesTool,
          _readPageTool,
          _writePageTool,
          _deletePageTool,
          _finishTool,
        ],
        onLine: onLine,
        executeToolCall: (response) => _executeWorkerToolCall(
          sessionId: sessionId,
          response: response,
        ),
        maxTurns: 48,
      );
    } finally {
      if (shouldDispose) {
        await service.dispose();
      }
    }
  }

  Future<Map<String, Object?>> _executeWorkerToolCall({
    required int sessionId,
    required gemma.FunctionCallResponse response,
  }) async {
    switch (response.name) {
      case 'list_existing_pages':
        final entries = await _storage.readAllEntries(sessionId);
        return {
          'tool': response.name,
          'paths': entries
              .map((entry) => {
                    'path': entry.relativePath,
                    'title': entry.title,
                    'category': entry.category,
                    'materialIds': entry.materialIds,
                  })
              .toList(growable: false),
          'message': 'Listed ${entries.length} wiki pages.',
        };
      case 'read_existing_page':
        final rawPath = response.args['path'] as String? ?? '';
        try {
          final entry = await _storage.readEntry(sessionId, rawPath);
          final normalizedPath = _storage.normalizeRelativePath(rawPath);
          return {
            'tool': response.name,
            'path': normalizedPath,
            'found': entry != null,
            'content': entry?.rawContent ?? '',
            'message': entry == null
                ? 'Page not found: $normalizedPath'
                : 'Read page ${entry.relativePath}.',
          };
        } on FormatException catch (error) {
          return {
            'tool': response.name,
            'message': 'Invalid wiki path. Got: "$rawPath". ${error.message}',
          };
        }
      case 'write_markdown_file':
        final path = response.args['path'] as String? ?? '';
        final content = response.args['content'] as String? ?? '';
        try {
          final entry = await _storage.writeMarkdownFile(
            sessionId: sessionId,
            relativePath: path,
            content: content,
          );
          return {
            'tool': response.name,
            'path': entry.relativePath,
            'touchedPaths': [entry.relativePath],
            'message': 'Wrote ${entry.relativePath}.',
          };
        } on FormatException catch (error) {
          return {
            'tool': response.name,
            'message': 'Invalid wiki path. Got: "$path". ${error.message}',
          };
        }
      case 'delete_markdown_file':
        final path = response.args['path'] as String? ?? '';
        try {
          final normalized = _storage.normalizeRelativePath(path);
          await _storage.deleteMarkdownFile(
            sessionId: sessionId,
            relativePath: normalized,
          );
          return {
            'tool': response.name,
            'path': normalized,
            'deletedPaths': [normalized],
            'message': 'Deleted $normalized.',
          };
        } on FormatException catch (error) {
          return {
            'tool': response.name,
            'message': 'Invalid wiki path. Got: "$path". ${error.message}',
          };
        }
      case 'finish_run':
        return {
          'tool': response.name,
          'summary': (response.args['summary'] as String?)?.trim() ?? '',
          'unresolvedIssues': _stringList(response.args['unresolvedIssues']),
          'message': 'Finish requested.',
        };
      default:
        return {
          'tool': response.name,
          'message': 'Ignored unsupported tool ${response.name}.',
        };
    }
  }

  String _buildManagerSystemInstruction(Session session, {required String mode}) {
    final categories = [
      'sources',
      'concepts',
      'entities',
      'syntheses',
      'reviews',
    ].join(', ');
    final currentDate = DateFormat('yyyy/MM/dd HH:mm z').format(DateTime.now());
    final modeRules = switch (mode) {
      'ingest' => '''
MODE: ingest
- Build a delegation plan from the provided materials and existing wiki state.
- Spawn workers one at a time to create and refine markdown pages.
- Keep the manager's own output small; do not write markdown directly.''',
      'lint' => '''
MODE: lint
- Build a delegation plan from the current wiki state.
- Spawn workers one at a time to audit and fix the wiki.
- Keep the manager's own output small; do not write markdown directly.''',
      _ => '''
MODE: $mode
- Prefer the smallest safe delegation plan.''',
    };

    return '''
You are the wiki manager for "${session.title}" (Grade ${session.gradeOverride}).
Output ONLY tool calls. Never emit free text, reasoning, or explanations.
Your job is to inspect the wiki, create a detailed plan, and delegate each task to a worker one at a time.

HARD RULES
- list_existing_pages must be the first tool call in every run.
- Read existing pages before planning if you need more context.
- Call plan once with worker-sized steps.
- Use spawn_worker for each concrete step. Do not overlap workers.
- Do not use write_markdown_file or delete_markdown_file in manager mode.
- Use complete_step when a delegated step finishes if the worker result has not already marked it.
- Use finish_run only after delegated work is complete.
- Use only these categories: $categories.
- Keep filenames lowercase kebab-case when possible.

$modeRules

PAGE ROLES
- sources: one page per study material, focused on what the material says.
- concepts: abstractions, definitions, repeated ideas, and principles.
- entities: concrete named things such as people, places, events, objects, or species.
- syntheses: cross-source comparisons, timelines, patterns, and conclusions.
- reviews: lint findings, gaps, contradictions, and follow-up questions.

QUALITY BAR
- Write for Grade ${session.gradeOverride} comprehension.
- Prefer short sentences, clear headers, and concrete examples.
- Define jargon on first use.
- Cross-link both directions when a relationship matters.
- Never silently overwrite a contradiction; preserve it in syntheses or log.md.
- Avoid repeating the same description across pages. Link instead.

PLAN AND OUTPUT STYLE
- In plan(), include only concrete worker tasks you will actually delegate now.
- Keep each step to one sentence.
- After each delegated step, call complete_step(index) or let the worker result mark it.
- Prefer updating index.md and log.md near the end of the run.
- The final tool call must be finish_run with a one-line summary.

CURRENT DATE
$currentDate
''';
  }

  String _buildWorkerSystemInstruction(
    Session session, {
    required String mode,
    required String task,
  }) {
    final categories = [
      'sources',
      'concepts',
      'entities',
      'syntheses',
      'reviews',
    ].join(', ');

    final modeRules = switch (mode) {
      'ingest' => '''
MODE: ingest
- Execute only the assigned markdown task.
- Read existing pages before editing them.
- Write or update markdown directly when needed.
- Keep changes local to the task; do not re-plan the whole wiki.''',
      'lint' => '''
MODE: lint
- Execute only the assigned lint/fix task.
- Read existing pages before editing them.
- Fix safe issues directly.
- Write one review page when needed and keep the changes local to the task.''',
      _ => '''
MODE: $mode
- Execute only the assigned task.''',
    };

    return '''
You are a wiki worker for "${session.title}" (Grade ${session.gradeOverride}).
Output ONLY tool calls. Never emit free text, reasoning, or explanations.
The manager already made the plan. Your job is to execute one concrete task bundle and report when it is done.

ASSIGNED TASK
$task

HARD RULES
- If you need context, list_existing_pages first.
- Read existing pages before editing them.
- Write markdown directly when needed.
- Do not plan the whole wiki again.
- Use finish_run when the assigned task is complete.
- Include unresolved issues in finish_run if any remain.
- Use only these categories: $categories.
- Keep filenames lowercase kebab-case when possible.

$modeRules

PAGE ROLES
- sources: one page per study material, focused on what the material says.
- concepts: abstractions, definitions, repeated ideas, and principles.
- entities: concrete named things such as people, places, events, objects, or species.
- syntheses: cross-source comparisons, timelines, patterns, and conclusions.
- reviews: lint findings, gaps, contradictions, and follow-up questions.

QUALITY BAR
- Write for Grade ${session.gradeOverride} comprehension.
- Prefer short sentences, clear headers, and concrete examples.
- Define jargon on first use.
- Cross-link both directions when a relationship matters.
- Never silently overwrite a contradiction; preserve it in syntheses or log.md.
- Avoid repeating the same description across pages. Link instead.
''';
  }

  String _buildManagerPrompt(
    Session session,
    List<StudyMaterial> materials, {
    required String mode,
  }) {
    final hasPhotos = materials.any((m) => m.kind == MaterialKind.photo);
    final buffer = StringBuffer()
      ..writeln(
          'Inspect the current wiki, make a delegation plan, and then spawn one worker at a time for each concrete task.')
      ..writeln()
      ..writeln('Session: ${session.title}')
      ..writeln('Grade: ${session.gradeOverride}')
      ..writeln('Material count: ${materials.length}')
      ..writeln()
      ..writeln('Materials:')
      ..writeln(_materialsContext(materials))
      ..writeln();
    if (hasPhotos) {
      buffer.writeln(
          'Note: photo materials exist, but this manager run should stay text-only and delegate image-heavy work to workers.');
      buffer.writeln();
    }
    buffer.writeln(
      'First list existing pages, then read anything you need, then call plan, then spawn workers step by step, and finish only after the delegated work is complete.',
    );
    return buffer.toString();
  }

  String _buildWorkerPrompt(
    Session session, {
    required List<StudyMaterial> materials,
    required String mode,
    required String task,
    required List<String> focusPaths,
    required int? stepIndex,
  }) {
    final hasPhotos = materials.any((m) => m.kind == MaterialKind.photo);
    final buffer = StringBuffer()
      ..writeln('Execute this worker task only.')
      ..writeln()
      ..writeln('Session: ${session.title}')
      ..writeln('Grade: ${session.gradeOverride}')
      ..writeln('Mode: $mode')
      ..writeln('Task:')
      ..writeln(task)
      ..writeln();
    if (stepIndex != null) {
      buffer
        ..writeln('Plan step index: $stepIndex')
        ..writeln();
    }
    if (focusPaths.isNotEmpty) {
      buffer.writeln('Focus paths:');
      for (final path in focusPaths) {
        buffer.writeln('- $path');
      }
      buffer.writeln();
    }
    buffer
      ..writeln('Materials:')
      ..writeln(_materialsContext(materials));
    if (hasPhotos) {
      buffer
        ..writeln()
        ..writeln('Note: photo materials exist and image attachments are available to this worker session.');
    }
    buffer.writeln(
      'Use the assigned task bundle, inspect existing markdown when needed, and finish with a concise report.',
    );
    return buffer.toString();
  }

  void _collectToolResult(
    Map<String, Object?> result, {
    required Set<String> touchedPaths,
    required Set<String> deletedPaths,
    required Set<String> unresolvedIssues,
  }) {
    final singlePath = result['path'] as String?;
    if (singlePath != null) {
      final tool = result['tool'] as String?;
      if (tool == 'delete_markdown_file') {
        deletedPaths.add(singlePath);
        touchedPaths.remove(singlePath);
      } else {
        touchedPaths.add(singlePath);
      }
    }

    final touchedList = _stringList(result['touchedPaths']);
    touchedPaths.addAll(touchedList);

    final deletedList = _stringList(result['deletedPaths']);
    deletedPaths.addAll(deletedList);
    touchedPaths.removeAll(deletedList);

    final issues = _stringList(result['unresolvedIssues']);
    unresolvedIssues.addAll(issues);
  }

  List<String> _stringList(Object? value) {
    if (value is List) {
      return value.whereType<String>().toList(growable: false);
    }
    if (value is String && value.trim().isNotEmpty) {
      return [value.trim()];
    }
    return const [];
  }

  String _modeFromTask(String task) {
    final lower = task.toLowerCase();
    if (lower.contains('lint') || lower.contains('review') || lower.contains('audit')) {
      return 'lint';
    }
    return 'ingest';
  }
}
