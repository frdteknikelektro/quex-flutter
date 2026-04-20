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
  }) async {
    return _run(
      service: service,
      session: session,
      materials: materials,
      sessionId: sessionId,
      prompt: _buildIngestPrompt(session, materials),
      systemInstruction: _buildSystemInstruction(session, mode: 'ingest'),
      onLine: onLine,
    );
  }

  Future<WikiAgentResult> runLint({
    required GemmaInferenceService service,
    required Session session,
    required List<StudyMaterial> materials,
    required int sessionId,
    WikiAgentLineCallback? onLine,
  }) async {
    return _run(
      service: service,
      session: session,
      materials: materials,
      sessionId: sessionId,
      prompt: _buildLintPrompt(session),
      systemInstruction: _buildSystemInstruction(session, mode: 'lint'),
      onLine: onLine,
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
  }) async {
    final prepared = await MaterialPreprocessor.prepare(materials);
    final hasImages = prepared.any((item) => item.images.isNotEmpty);
    final totalImages = prepared.fold(0, (sum, p) => sum + p.images.length);
    debugPrint('[WikiAgent] start: materials=${materials.length} images=$totalImages hasImages=$hasImages');

    await service.createSession(
      systemInstruction: systemInstruction,
      temperature: 0.2,
      topK: 1,
      supportImage: hasImages,
      tools: const [
        _listPagesTool,
        _readPageTool,
        _writePageTool,
        _deletePageTool,
        _finishTool,
      ],
      supportsFunctionCalls: true,
      isThinking: false,
    );

    for (final item in prepared) {
      for (final image in item.images) {
        await service.addImageQuery(image);
      }
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
You are a wiki maintenance agent. Your job is to build, update, and lint study wikis by calling tools exactly as instructed. Output ONLY tool calls. Never emit free text, reasoning, or explanations.

RULES — follow these exactly:

1. ALWAYS call list_existing_pages FIRST before writing any new page. Check what already exists.
2. Call read_existing_page BEFORE updating an existing page. Read it first to avoid losing content.
3. Call write_markdown_file to create or overwrite wiki pages. Include YAML frontmatter (title, category, slug, materialIds) and markdown body.
4. Call delete_markdown_file only for truly redundant or superseded pages.
5. Call finish_run ONLY after all file changes are done. Provide a one-line summary.
6. NEVER produce free text as a response. If you cannot decide, call a tool.

WIKI STRUCTURE:
- index.md  — category index with links grouped by category
- log.md    — append a new dated section for this run
- sources/*.md  — one page per study material
- concepts/*.md — shared ideas and recurring themes
- entities/*.md — concrete named entities only
- syntheses/*.md — cross-material summaries and comparisons
- reviews/*.md  — lint reports only

PATH FORMAT — path arguments must be plain strings. CORRECT: "sources/chapter1.md". WRONG: "\"sources/chapter1.md\"" or "sources/<tag>" or any wrapper. No extra quotes, no tags, no brackets.

OUTPUT RULE: You MUST output a tool call response for every user message. Do not explain what you are doing. Do not output thinking, reasoning, or intermediate text. Only structured tool calls are valid responses.

Current date: ${DateFormat('yyyy/MM/dd HH:mm z').format(DateTime.now())} (use YYYY/MM/DD HH:MM format in log entries)
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
