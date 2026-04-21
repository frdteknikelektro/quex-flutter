import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart' as gemma;

import '../models/models.dart';
import 'gemma_inference_service.dart';
import 'response_loop_guard.dart';
import 'material_preprocessor.dart';
import 'tutor_event.dart';

/// Service for managing persistent chat sessions (tutor and coach).
///
/// Works with [GemmaInferenceService] to provide conversation state
/// across multiple user messages. Each screen visit initializes once,
/// then sends messages incrementally.
class GemmaSessionService {
  GemmaSessionService(this._inference);

  final GemmaInferenceService _inference;

  static const _evaluateTool = gemma.Tool(
    name: 'evaluate_understanding',
    description: 'Rate student understanding of the question (0.0-1.0). '
        'Call when student answers correctly, gives correct option letter, '
        'or demonstrates clear comprehension.',
    parameters: {
      'type': 'object',
      'properties': {
        'score': {
          'type': 'number',
          'minimum': 0.0,
          'maximum': 1.0,
          'description': '0.0=wrong, 0.5=partial, 1.0=correct',
        },
      },
      'required': ['score'],
    },
  );

  /// Initialize question tutor session ONCE per screen visit.
  /// Materials processed once, images sent once.
  Future<void> initQuestionTutorSession({
    required Question question,
    required List<StudyMaterial> materials,
  }) async {
    if (!_inference.isInitialized) {
      throw StateError('Service not initialized');
    }

    // Close any existing chat to ensure clean state.
    await _inference.closeSession();

    final prepared = await MaterialPreprocessor.prepare(materials);
    final hasImages = prepared.any((p) => p.images.isNotEmpty);

    final optionsText = question.type == QuestionType.multipleChoice
        ? question.options
            .asMap()
            .entries
            .map((e) => '${String.fromCharCode(65 + e.key)}) ${e.value}')
            .join('\n')
        : '';

    final materialsContext = prepared
        .where((p) => p.textChunk.isNotEmpty)
        .map((p) => p.textChunk)
        .join('\n\n');

    final systemInstruction = StringBuffer(
      'You are a friendly tutor helping an elementary student answer a quiz question. '
      'Keep responses short and simple. Give hints and encouragement, and do NOT reveal '
      'the answer directly until they demonstrate understanding.\n\n'
      'Use the evaluate_understanding tool only when the student answers correctly or '
      'clearly demonstrates understanding. Otherwise reply in plain text.\n\n'
      '--- QUIZ QUESTION ---\n'
      'Question: ${question.questionText}\n',
    );
    if (optionsText.isNotEmpty) {
      systemInstruction.writeln('Options:\n$optionsText');
    }
    if (materialsContext.isNotEmpty) {
      systemInstruction
        ..writeln()
        ..writeln('--- STUDY MATERIALS ---')
        ..write(materialsContext);
    }

    await _inference.createSession(
      systemInstruction: systemInstruction.toString(),
      temperature: 0.7,
      supportImage: hasImages,
      promptDialect: gemma.PromptDialect.gemma4,
      toolChoice: gemma.ToolChoice.auto,
      tools: [_evaluateTool],
      supportsFunctionCalls: true,
    );

    // Queue all images to be included with first user message
    final allImages = <Uint8List>[];
    for (final p in prepared) {
      allImages.addAll(p.images);
    }
    if (allImages.isNotEmpty) {
      debugPrint('[Tutor] Queuing ${allImages.length} images');
      await _inference.addImagesToQueue(allImages);
    }
  }

  /// Send user message incrementally. No history param — InferenceChat maintains state.
  /// Yields: TutorThinking, TutorReply, or TutorEvaluation (when model calls tool).
  Stream<TutorEvent> sendQuestionTutorMessage(String userMessage) async* {
    if (!_inference.hasActiveSession) {
      throw StateError(
          'No active session. Call initQuestionTutorSession() first.');
    }

    final guard = ResponseLoopGuard();
    final replyBuffer = StringBuffer();
    final thinkingBuffer = StringBuffer();
    final toolCalls = <String>[];
    await _inference.addTextQuery(userMessage);

    try {
      await for (final response in _inference.generateResponses()) {
        if (response is gemma.ThinkingResponse) {
          thinkingBuffer.write(response.content);
          yield TutorThinking(response.content);
        } else if (response is gemma.TextResponse) {
          replyBuffer.write(response.token);
          final error = guard.recordTextToken(response.token);
          if (error != null) {
            throw StateError(error);
          }
          yield TutorReply(response.token);
        } else if (response is gemma.FunctionCallResponse) {
          toolCalls.add('${response.name}(${response.args})');
          final error = guard.recordToolCall(response.name, response.args);
          if (error != null) {
            throw StateError(error);
          }
          if (response.name == 'evaluate_understanding') {
            final score = (response.args['score'] as num?)?.toDouble();
            if (score != null) {
              yield TutorEvaluation(score: score);
            }
          }
        }
      }
    } finally {
      _debugGemmaAudit(
        label: 'Tutor',
        thinking: thinkingBuffer.toString(),
        reply: replyBuffer.toString(),
        toolCalls: toolCalls,
      );
    }
  }

  /// Initialize coach session ONCE per screen visit.
  Future<void> initCoachSession({
    required Session session,
    required List<StudyMaterial> materials,
  }) async {
    if (!_inference.isInitialized) {
      throw StateError('Service not initialized');
    }

    await _inference.closeSession();

    final prepared = await MaterialPreprocessor.prepare(materials);
    final hasImages = prepared.any((p) => p.images.isNotEmpty);

    final textContext = prepared
        .where((p) => p.textChunk.isNotEmpty)
        .map((p) => p.textChunk)
        .join('\n\n');

    final systemInstruction = StringBuffer(
      'You are Quex, a friendly study coach for "${session.title}". '
      'Answer questions about the study material, offer study tips, and suggest topics to explore. '
      'Keep responses short, encouraging, and kid-friendly.',
    );
    if (textContext.isNotEmpty) {
      systemInstruction
        ..writeln('\n\n--- STUDY MATERIALS ---')
        ..write(textContext);
    }

    await _inference.createSession(
      systemInstruction: systemInstruction.toString(),
      temperature: 0.7,
      supportImage: hasImages,
      promptDialect: gemma.PromptDialect.gemma4,
      toolChoice: gemma.ToolChoice.auto,
    );

    // Queue all images to be included with first user message
    final allImages = <Uint8List>[];
    for (final p in prepared) {
      allImages.addAll(p.images);
    }
    if (allImages.isNotEmpty) {
      debugPrint('[Coach] Queuing ${allImages.length} images');
      await _inference.addImagesToQueue(allImages);
    }
  }

  /// Send coach message incrementally.
  Stream<TutorEvent> sendCoachMessage(String message) async* {
    if (!_inference.hasActiveSession) {
      throw StateError('No active session. Call initCoachSession() first.');
    }

    final guard = ResponseLoopGuard();
    final replyBuffer = StringBuffer();
    final thinkingBuffer = StringBuffer();
    final toolCalls = <String>[];
    await _inference.addTextQuery(message);

    try {
      await for (final response in _inference.generateResponses()) {
        if (response is gemma.ThinkingResponse) {
          thinkingBuffer.write(response.content);
          yield TutorThinking(response.content);
        } else if (response is gemma.TextResponse) {
          replyBuffer.write(response.token);
          final error = guard.recordTextToken(response.token);
          if (error != null) {
            throw StateError(error);
          }
          yield TutorReply(response.token);
        } else if (response is gemma.FunctionCallResponse) {
          toolCalls.add('${response.name}(${response.args})');
        }
      }
    } finally {
      _debugGemmaAudit(
        label: 'Coach',
        thinking: thinkingBuffer.toString(),
        reply: replyBuffer.toString(),
        toolCalls: toolCalls,
      );
    }
  }

  void _debugGemmaAudit({
    required String label,
    required String thinking,
    required String reply,
    required List<String> toolCalls,
  }) {
    if (!kDebugMode) return;

    debugPrint(
      '[$label][Gemma][audit] thinking=${thinking.length} chars '
      'reply=${reply.length} chars toolCalls=${toolCalls.length}',
    );
    _debugPrintChunked('[$label][Gemma][thinking]', thinking);
    _debugPrintChunked('[$label][Gemma][reply]', reply);
    if (toolCalls.isNotEmpty) {
      debugPrint('[$label][Gemma][toolCalls] ${toolCalls.join(' | ')}');
    }
  }

  void _debugPrintChunked(String prefix, String text) {
    if (text.isEmpty) {
      debugPrint('$prefix <empty>');
      return;
    }

    const chunkSize = 900;
    for (var start = 0; start < text.length; start += chunkSize) {
      final end =
          start + chunkSize < text.length ? start + chunkSize : text.length;
      debugPrint('$prefix ${text.substring(start, end)}');
    }
  }
}
