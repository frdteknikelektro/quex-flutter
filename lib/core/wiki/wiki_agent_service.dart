import 'dart:async';
import 'dart:convert';

import 'package:flutter_gemma/flutter_gemma.dart' as gemma;
import 'package:intl/intl.dart';

import '../ai/gemma_inference_service.dart';
import '../ai/material_preprocessor.dart';
import '../models/models.dart';
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

class WikiAgentService {
  WikiAgentService(this._storage);

  final WikiStorageService _storage;

  static const _listPagesTool = gemma.Tool(
    name: 'list_existing_pages',
    description: 'List existing markdown pages in current session wiki.',
    parameters: {
      'type': 'object',
      'properties': {},
    },
  );

  static const _readPageTool = gemma.Tool(
    name: 'read_existing_page',
    description: 'Read one existing markdown page by relative path.',
    parameters: {
      'type': 'object',
      'properties': {
        'path': {'type': 'string'},
      },
      'required': ['path'],
    },
  );

  static const _writePageTool = gemma.Tool(
    name: 'write_markdown_file',
    description:
        'Create or update one markdown file under allowed wiki paths only.',
    parameters: {
      'type': 'object',
      'properties': {
        'path': {'type': 'string'},
        'content': {'type': 'string'},
      },
      'required': ['path', 'content'],
    },
  );

  static const _deletePageTool = gemma.Tool(
    name: 'delete_markdown_file',
    description: 'Delete one obsolete markdown file by relative path.',
    parameters: {
      'type': 'object',
      'properties': {
        'path': {'type': 'string'},
      },
      'required': ['path'],
    },
  );

  static const _finishTool = gemma.Tool(
    name: 'finish_run',
    description: 'Finish current wiki task after all file work is complete.',
    parameters: {
      'type': 'object',
      'properties': {
        'summary': {'type': 'string'},
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
      isThinking: true,
    );

    await service.addTextQuery(prompt);
    for (final item in prepared) {
      for (final image in item.images) {
        await service.addImageQuery(image);
      }
    }

    final touchedPaths = <String>{};
    final deletedPaths = <String>{};
    var summary = '';
    var plainTextRetry = 0;

    for (var turn = 0; turn < 24; turn++) {
      var sawToolCall = false;
      final toolResults = <Map<String, Object?>>[];

      await for (final response in service.generateResponses()) {
        if (response is gemma.ThinkingResponse) {
          _emitLine(onLine, response.content);
        } else if (response is gemma.TextResponse) {
          final text = response.token.trim();
          if (text.isNotEmpty) _emitLine(onLine, text);
        } else if (response is gemma.FunctionCallResponse) {
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
        if (plainTextRetry >= 3) {
          throw StateError('Wiki agent stopped without calling finish_run.');
        }
        await service.addTextQuery(
          'Use available tools to continue. Write or update wiki files as needed, then call finish_run.',
          noTool: true,
        );
        continue;
      }

      plainTextRetry = 0;
      await service.addTextQuery(
        'Tool results:\n${const JsonEncoder.withIndent('  ').convert(toolResults)}\nContinue with more tools if needed. Call finish_run only when the wiki is complete for this task.',
        noTool: true,
      );
    }

    throw StateError('Wiki agent exceeded step limit before finish_run.');
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
        final path = response.args['path'] as String? ?? '';
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
        final content = response.args['content'] as String? ?? '';
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
      case 'delete_markdown_file':
        final path = response.args['path'] as String? ?? '';
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
You are a disciplined wiki maintainer for session "${session.title}" (Grade ${session.gradeOverride}).

Write only markdown files through tools. Never answer with final prose instead of tools.
Allowed wiki structure:
- index.md
- log.md
- sources/*.md
- concepts/*.md
- entities/*.md
- syntheses/*.md
- reviews/*.md

Every category page should include YAML frontmatter with title, category, slug, sessionId, materialIds, updatedAt.
Use markdown links between related pages when helpful.
For index.md, group links by category and include reviews.
For log.md, append a new dated section for this $mode run with timestamp, touched pages, and short notes.
For sources/, create or update one source page per study material.
For concepts/, write shared ideas and recurring themes.
For entities/, create pages only for concrete named entities that matter.
For syntheses/, write cross-material summaries, comparisons, or evolving thesis pages.
For reviews/, write lint reports only.

Do not write outside these categories.
Do not invent facts not grounded in provided materials or existing wiki pages.
After all file changes are complete, call finish_run with a one-line summary.

Current date: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}
Allowed categories: $categories
''';
  }

  String _buildIngestPrompt(Session session, List<StudyMaterial> materials) {
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
      ..writeln()
      ..writeln(
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
      }
    }
    return buffer.toString().trim();
  }
}
