import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart' as gemma;
import 'package:intl/intl.dart';

import '../models/models.dart';
import 'gemma_inference_service.dart';
import 'material_preprocessor.dart';
import 'wiki_storage_service.dart';

typedef WikiAgentLineCallback = void Function(String line);

class WikiAgentResult {
  final List<String> touchedPaths;
  final List<String> deletedPaths;
  final String summary;

  const WikiAgentResult({
    required this.touchedPaths,
    required this.deletedPaths,
    required this.summary,
  });
}

class GemmaWikiService {
  GemmaWikiService(this._storage);

  final WikiStorageService _storage;

  static const _planTool = gemma.Tool(
    name: 'plan',
    description:
        'Declare your complete plan before starting any work. Call ONCE at the very beginning. '
        'List every step you intend to take in order.',
    parameters: {
      'type': 'object',
      'properties': {
        'steps': {
          'type': 'array',
          'items': {'type': 'string'},
          'description':
              'Ordered list of steps, e.g. ["List existing pages", "Write concepts/photosynthesis.md", "Update index.md", "Finish"]',
        },
      },
      'required': ['steps'],
    },
  );

  static const _completeStepTool = gemma.Tool(
    name: 'complete_step',
    description: 'Mark a planned step as done. Call after finishing each step from your plan.',
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

  static const _listPagesTool = gemma.Tool(
    name: 'list_existing_pages',
    description: 'List all existing markdown pages in the current session wiki. Call this first to understand what already exists before writing or updating.',
    parameters: {
      'type': 'object',
      'properties': {},
    },
  );

  static const _readPageTool = gemma.Tool(
    name: 'read_existing_page',
    description: 'Read the full content of one existing wiki page. Use this before updating a page to avoid overwriting useful content.',
    parameters: {
      'type': 'object',
      'properties': {
        'path': {
          'type': 'string',
          'description': 'Relative path to the wiki page, e.g. sources/chapter1.md or concepts/photosynthesis.md',
        },
      },
      'required': ['path'],
    },
  );

  static const _writePageTool = gemma.Tool(
    name: 'write_markdown_file',
    description: 'Write a wiki page. Include YAML frontmatter and markdown. Allowed: index.md, log.md, sources/*.md, concepts/*.md, entities/*.md, syntheses/*.md, reviews/*.md.',
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
    description: 'Delete one obsolete or duplicate wiki page. Only use when a page is truly redundant or superseded.',
    parameters: {
      'type': 'object',
      'properties': {
        'path': {
          'type': 'string',
          'description': 'Relative path of the wiki file to delete, e.g. sources/old_draft.md',
        },
      },
      'required': ['path'],
    },
  );

  static const _finishTool = gemma.Tool(
    name: 'finish_run',
    description: 'Call when all wiki changes are done. Provide a one-line summary.',
    parameters: {
      'type': 'object',
      'properties': {
        'summary': {
          'type': 'string',
          'description': 'One-line summary of changes made.',
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
    return _run(
      service: service,
      session: session,
      materials: materials,
      sessionId: sessionId,
      prompt: _buildIngestPrompt(session, materials),
      systemInstruction: _buildSystemInstruction(session, mode: 'ingest'),
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
    return _run(
      service: service,
      session: session,
      materials: materials,
      sessionId: sessionId,
      prompt: _buildLintPrompt(session),
      systemInstruction: _buildSystemInstruction(session, mode: 'lint'),
      onLine: onLine,
      onPlan: onPlan,
      onStepComplete: onStepComplete,
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
    debugPrint('[WikiAgent] start: materials=${materials.length} images=$totalImages hasImages=$hasImages');

    await service.createSession(
      systemInstruction: systemInstruction,
      temperature: 1,
      topK: 1,
      supportImage: hasImages,
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
          lastPlainText += response.token;
          // Try to recover flushed tool calls from partial JSON
          final recovered = _tryRecoverToolCall(lastPlainText);
          if (recovered != null) {
            debugPrint('[WikiAgent] recovered flushed tool call: ${recovered.name}');
            sawToolCall = true;
            final result = await _executeToolCall(
              sessionId: sessionId,
              response: recovered,
              touchedPaths: touchedPaths,
              deletedPaths: deletedPaths,
            );
            toolResults.add(result);
            _emitLine(onLine, result['message'] as String? ?? recovered.name);
            lastPlainText = '';
            if (recovered.name == 'finish_run') {
              summary = (recovered.args['summary'] as String?)?.trim() ?? '';
              return WikiAgentResult(
                touchedPaths: touchedPaths.toList()..sort(),
                deletedPaths: deletedPaths.toList()..sort(),
                summary: summary,
              );
            }
          }
        } else if (response is gemma.FunctionCallResponse) {
          debugPrint('[WikiAgent] tool call: name=${response.name} args=${response.args}');
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
            debugPrint('[WikiAgent] finish_run called. summary=$summary');
            summary = (response.args['summary'] as String?)?.trim() ?? '';
            return WikiAgentResult(
              touchedPaths: touchedPaths.toList()..sort(),
              deletedPaths: deletedPaths.toList()..sort(),
              summary: summary,
            );
          }
        } else if (response is gemma.ParallelFunctionCallResponse) {
          sawToolCall = true;
          for (final call in response.calls) {
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
          debugPrint('[WikiAgent] FAILURE after $plainTextRetry text-only turns. '
              'Last text: $preview. Touched: ${touchedPaths.length}, deleted: ${deletedPaths.length}. '
              'Touched paths: ${touchedPaths.toList()}. Deleted paths: ${deletedPaths.toList()}.');
          throw StateError(
            'Wiki agent stopped without calling finish_run after $plainTextRetry text-only turns. '
            'Last text: $preview. '
            'Touched: ${touchedPaths.length}, deleted: ${deletedPaths.length}.',
          );
        }
        debugPrint('[WikiAgent] text-only turn $plainTextRetry, nudging with noTool query. '
            'lastTextPreview: "${lastPlainText.substring(0, lastPlainText.length.clamp(0, 80))}"');
        await service.addTextQuery(
          'You must call a tool now. Call list_existing_pages or write_markdown_file with valid arguments. '
          'Example: {"name": "list_existing_pages", "args": {}}',
          noTool: true,
        );
        continue;
      }

      plainTextRetry = 0;
      for (final result in toolResults) {
        final toolName = result['tool'] as String? ?? 'unknown';
        debugPrint('[WikiAgent] tool result: $toolName -> ${result['message']}');
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
        final steps = (response.args['steps'] as List<dynamic>?)?.cast<String>() ?? [];
        return {
          'tool': response.name,
          'plan': steps,
          'message': 'Plan: ${steps.length} step${steps.length == 1 ? '' : 's'}',
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
        final path = _cleanPath(rawPath);
        if (path.isEmpty) {
          return {
            'tool': response.name,
            'message': 'Path is required. Got: "$rawPath"',
          };
        }
        final entry = await _storage.readEntry(sessionId, path);
        return {
          'tool': response.name,
          'path': path,
          'found': entry != null,
          'content': entry?.rawContent ?? '',
          'message': entry == null
              ? 'Page not found: $path'
              : 'Read page ${entry.relativePath}.',
        };
      case 'write_markdown_file':
        final path = response.args['path'] as String? ?? '';
        final cleanPath = _cleanPath(path);
        if (cleanPath.isEmpty) {
          return {
            'tool': response.name,
            'message': 'Path is required and must be a valid wiki path. Got: "$path"',
          };
        }
        final content = response.args['content'] as String? ?? '';
        final entry = await _storage.writeMarkdownFile(
          sessionId: sessionId,
          relativePath: cleanPath,
          content: content,
        );
        touchedPaths.add(entry.relativePath);
        deletedPaths.remove(entry.relativePath);
        return {
          'tool': response.name,
          'path': entry.relativePath,
          'message': 'Wrote ${entry.relativePath}.',
        };
      case 'delete_markdown_file':
        final path = response.args['path'] as String? ?? '';
        final cleanPath = _cleanPath(path);
        if (cleanPath.isEmpty) {
          return {
            'tool': response.name,
            'message': 'Path is required and must be a valid wiki path. Got: "$path"',
          };
        }
        final normalized = _storage.normalizeRelativePath(cleanPath);
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

    return '''
You are a wiki builder and maintainer for "${session.title}" (Grade ${session.gradeOverride}). Your job is to construct and evolve a persistent, interconnected knowledge base by reading sources, extracting key ideas, and maintaining cross-references. Output ONLY tool calls. Never emit free text, reasoning, or explanations.

CORE PRINCIPLES:
- The wiki is a LIVING ARTIFACT. Each ingest strengthens it — new pages, updated connections, refined understanding.
- Extract and synthesize. Don't just summarize sources — identify core concepts, named entities, relationships, and contradictions.
- Cross-reference obsessively. Every concept page links to related entities and sources. Every entity page links to concepts that define or explain it.
- Track evolution. Note when new sources confirm, contradict, or refine existing claims. Update log.md with what changed and why.
- Organize by PURPOSE, not format: sources are raw input. Concepts are recurring ideas. Entities are named things (people, places, species, etc.). Syntheses are cross-source insights. Reviews are gaps and next questions.

WORKFLOW (ingest mode):
1. list_existing_pages — understand current wiki structure and coverage. This is MANDATORY FIRST.
2. Call plan() with all steps you intend to take based on current state. Then call complete_step(index) after finishing each step.
3. For each source: identify key concepts, entities, and facts.
4. write or update concept/*.md pages with definitions, examples from sources, links to related entities and sources.
5. write or update entities/*.md pages with descriptions, roles, relationships, and citations.
6. write sources/[title].md summarizing the source and highlighting what's new or contradictory.
7. Update syntheses/*.md — revise cross-source comparisons, timelines, and conclusions.
8. Update index.md with new pages and revised metadata.
9. Append to log.md: what was added, what was updated, what contradictions emerged, what questions remain.
10. finish_run with a one-line summary.

FRONTMATTER TEMPLATE (YAML):
---
title: [Page Title]
category: [sources|concepts|entities|syntheses|reviews]
slug: [kebab-case-url-slug]
materialIds: [comma-separated source IDs that informed this page]
lastUpdated: YYYY-MM-DD
status: [draft|active|deprecated]
---

FILE STRUCTURE:
- index.md — master index. Organized by category. Each entry: [Title](path) — one-line summary.
- log.md — append-only changelog. Format: `## [YYYY-MM-DD HH:MM] [ingest|lint|query] | [brief summary]`
- sources/*.md — one page per study material. Summary + key claims.
- concepts/*.md — abstract ideas, definitions, principles, recurring themes. Links to entities and sources.
- entities/*.md — concrete things: people, places, species, events, objects. Links to related concepts and sources.
- syntheses/*.md — cross-source comparisons, timelines, arguments, patterns. Cite all sources.
- reviews/*.md — lint findings, gaps, contradictions, suggested next questions. Only in lint mode.

PATH FORMAT:
CORRECT: "sources/chapter1.md", "concepts/photosynthesis.md", "entities/carbon-cycle.md"
WRONG: quotes around path, angle brackets, variables, spaces in filenames

RULES:
1. ALWAYS list_existing_pages FIRST. This informs your plan. Never call plan() before examining existing structure.
2. ALWAYS call plan() AFTER list_existing_pages and before any writes. Plan must include concrete steps based on what exists now and what you just learned.
3. Before updating an existing page, read_existing_page. Preserve content; refine and extend.
4. Cross-linking is mandatory: if page A mentions concept B, link it: [concept](../concepts/b.md). If concept B relates to entity C, reciprocate.
5. Flag contradictions explicitly in syntheses/ or log.md. Never silently overwrite old claims. Example: "Source X claims [A]. Source Y claims [B]. See syntheses/contradiction-A-vs-B.md"
6. Avoid duplication: if an entity already has a page, link to it from other pages rather than repeating its description.
7. Only delete a page if it is truly superseded or a duplicate. Default: update.
8. Produce a tool call for every user message. No free text, no reasoning in responses.

CONTENT QUALITY:
- Write for grade ${session.gradeOverride} comprehension. Define jargon. Use examples.
- Synthesis pages should connect at least 2–3 sources. Show patterns and differences.
- Log entries should indicate what was *added*, *updated*, or *contradicted* — help readers see the wiki's evolution.

Current date: ${DateFormat('yyyy/MM/dd HH:mm z').format(DateTime.now())}
Allowed categories: $categories
''';
  }

  String _buildIngestPrompt(Session session, List<StudyMaterial> materials) {
    final hasPhotos = materials.any((m) => m.kind == MaterialKind.photo);
    final buffer = StringBuffer()
      ..writeln('Ingest all session materials into the wiki. Update existing pages when appropriate instead of duplicating them.')
      ..writeln()
      ..writeln('Session: ${session.title}')
      ..writeln('Grade: ${session.gradeOverride}')
      ..writeln('Material count: ${materials.length}')
      ..writeln()
      ..writeln('Materials:')
      ..writeln(_materialsContext(materials))
      ..writeln();
    if (hasPhotos) {
      buffer.writeln('Note: Image attachments for photo materials are included above. Use them to extract content for wiki pages.');
      buffer.writeln();
    }
    buffer.writeln('Start by listing existing pages if needed. Then read any page you need, write/update wiki pages, update index.md and log.md, and finish.');
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

  String _cleanPath(String raw) {
    if (raw.isEmpty) return '';
    // Strip XML artifacts that flutter_gemma can emit
    var cleaned = raw.replaceAll('<|"|>', '"').replaceAll('<|"|', '"');
    // Strip any angle-bracket sequences the model might hallucinate
    cleaned = cleaned.replaceAll(RegExp(r'<\|[^>]*>'), '');
    // Collapse repeated slashes
    cleaned = cleaned.replaceAll(RegExp(r'/+'), '/');
    // Strip trailing whitespace around the whole thing
    cleaned = cleaned.trim();
    // Reject: empty, or contains obviously bad chars (no angle brackets, no pipe tags)
    if (cleaned.isEmpty || cleaned.contains('<') || cleaned.contains('>|') || !RegExp(r'^[a-zA-Z0-9_/.\-]+$').hasMatch(cleaned)) {
      debugPrint('[WikiAgent] _cleanPath rejecting: "$raw" -> "$cleaned"');
      return '';
    }
    return cleaned;
  }

  /// Attempt to parse a flushed text blob as a JSON tool call.
  /// flutter_gemma flushes raw tokens as TextResponse when the function buffer
  /// exceeds 1024 chars. The flushed text may contain partial JSON.
  gemma.FunctionCallResponse? _tryRecoverToolCall(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    // Strip Gemma raw token artifacts
    var clean = trimmed
        .replaceAll(RegExp(r'<\|[^>]*>'), '')
        .replaceAll('call:', '')
        .replaceAll('call', '')
        .trim();

    // Try to find JSON object (may be wrapped in backticks or extra text)
    final jsonStart = clean.indexOf('{');
    final jsonEnd = clean.lastIndexOf('}');
    if (jsonStart == -1 || jsonEnd == -1 || jsonEnd <= jsonStart) return null;

    var jsonStr = clean.substring(jsonStart, jsonEnd + 1);
    if (jsonStr.length < 10) return null;

    // Unescape newlines that break JSON parsing — model embeds raw \n in strings
    jsonStr = _tryFixJsonNewlines(jsonStr);

    // Extract name from JSON
    final nameMatch = RegExp(r'"name"\s*:\s*"([^"]+)"').firstMatch(jsonStr);
    if (nameMatch == null) return null;
    final name = nameMatch.group(1)!;

    const validNames = {
      'plan',
      'complete_step',
      'list_existing_pages',
      'read_existing_page',
      'write_markdown_file',
      'delete_markdown_file',
      'finish_run',
    };
    if (!validNames.contains(name)) return null;

    // Try full JSON parse first
    try {
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      final argsRaw = decoded['args'] as Map<String, dynamic>?;
      if (argsRaw == null) return gemma.FunctionCallResponse(name: name, args: {});
      final args = _flattenArgs(argsRaw);
      debugPrint('[WikiAgent] _tryRecoverToolCall: name=$name args=$args');
      return gemma.FunctionCallResponse(name: name, args: args);
    } catch (_) {
      // Fallback: manual extraction for malformed JSON
    }

    // Fallback: extract path from the innermost path value
    final pathMatch = RegExp(r'"path"\s*:\s*"([^"]+)"').firstMatch(jsonStr);
    final path = pathMatch?.group(1);
    final contentMatch = RegExp(r'"content"\s*:\s*"([\s\S]*?)"(?:\s*,|\s*\})').firstMatch(jsonStr);
    final content = contentMatch?.group(1);

    final args = <String, Object?>{};
    if (path != null) args['path'] = path;
    if (content != null) args['content'] = content;

    debugPrint('[WikiAgent] _tryRecoverToolCall fallback: name=$name args=$args');
    return gemma.FunctionCallResponse(name: name, args: args);
  }

  /// Recursively flatten nested objects — model sometimes wraps args like
  /// {"path": {"path": "...", "content": "..."}} instead of {"path": "...", "content": "..."}
  Map<String, Object?> _flattenArgs(Map<String, dynamic> args) {
    final result = <String, Object?>{};
    for (final entry in args.entries) {
      if (entry.value is Map) {
        result.addAll(_flattenArgs(entry.value as Map<String, dynamic>));
      } else {
        result[entry.key] = entry.value;
      }
    }
    return result;
  }

  /// Replace raw newlines in JSON string values with \n escape sequences.
  /// The model embeds YAML frontmatter with unescaped newlines, breaking JSON parse.
  String _tryFixJsonNewlines(String json) {
    // Strategy: find all "content": "..." or "summary": "..." string values
    // and escape their inner newlines
    return json.replaceAllMapped(
      RegExp(r'("(?:content|summary)"\s*:\s*")([\s\S]*?)"(?=\s*,|\s*\})'),
      (m) {
        final openQuote = m.group(1)!;
        final value = m.group(2)!;
        final escaped = value.replaceAll('\n', '\\n').replaceAll('\r', '\\r');
        return '$openQuote$escaped"';
      },
    );
  }

  String _materialsContext(List<StudyMaterial> materials) {
    final buffer = StringBuffer();
    for (final material in materials) {
      buffer
        ..writeln('- [${material.id}] ${material.title} (${material.kind.name})')
        ..writeln('  Preview: ${material.preview}');
      if (material.kind == MaterialKind.text) {
        final trimmed = material.content.trim();
        final snippet = trimmed.length > 1400
            ? '${trimmed.substring(0, 1400)}...'
            : trimmed;
        buffer.writeln('  Content: $snippet');
      } else if (material.kind == MaterialKind.photo) {
        final imageCount = material.content.split('\n').where((p) => p.isNotEmpty).length;
        buffer.writeln('  Images: $imageCount image(s) attached');
      }
    }
    return buffer.toString().trim();
  }
}
