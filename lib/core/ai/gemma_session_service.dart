import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart' as gemma;

import '../models/models.dart';
import 'chat_prompts.dart';
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

  /// Public accessor to the underlying inference service.
  GemmaInferenceService get inference => _inference;

  static const _evaluateTool = gemma.Tool(
    name: 'evaluate_understanding',
    description: 'Rate student understanding of the question (0.0-1.0). '
        'Call it first when the student answers correctly, gives the correct '
        'option letter, or demonstrates clear comprehension.',
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
    await _createQuestionTutorSession(
      question: question,
      materials: materials,
      replayMessages: const [],
    );
  }

  /// Create a tutor session and replay a stored history into it.
  Future<void> preloadQuestionTutorSession({
    required Question question,
    required List<StudyMaterial> materials,
    required List<QuestionMessage> history,
  }) async {
    await _createQuestionTutorSession(
      question: question,
      materials: materials,
      replayMessages: _buildReplayMessages(history),
    );
  }

  Future<void> _createQuestionTutorSession({
    required Question question,
    required List<StudyMaterial> materials,
    required List<gemma.Message> replayMessages,
  }) async {
    if (!_inference.isInitialized) {
      throw StateError('Service not initialized');
    }

    // Close any existing chat to ensure clean state.
    await _inference.closeSession();

    final prepared = await MaterialPreprocessor.prepare(materials);
    final hasImages = prepared.any((p) => p.images.isNotEmpty);

    final materialsContext = prepared
        .where((p) => p.textChunk.isNotEmpty)
        .map((p) => p.textChunk)
        .join('\n\n');

    final systemInstruction = StringBuffer(
      'You are a friendly tutor helping an elementary student answer a quiz question. '
      'Keep responses short and simple. Give hints and encouragement. '
      'When the student answers correctly, first call evaluate_understanding to score it. '
      'After calling the tool, always wait for the tool response before sending your text reply. '
      'After receiving the tool response, congratulate the student (e.g., "Great job!", "Correct!", "Well done!").',
    );
    if (materialsContext.isNotEmpty) {
      systemInstruction
        ..writeln()
        ..writeln('--- STUDY MATERIALS ---')
        ..write(materialsContext);
    }

    await _inference.createSession(
      systemInstruction: systemInstruction.toString(),
      temperature: 0.8,
      topK: 40,
      supportImage: hasImages,
      promptDialect: gemma.PromptDialect.gemma4,
      toolChoice: gemma.ToolChoice.auto,
      tools: [_evaluateTool],
      supportsFunctionCalls: true,
    );

    // Collect all material images
    final allImages = <Uint8List>[];
    for (final p in prepared) {
      allImages.addAll(p.images);
    }

    final replayChain = <gemma.Message>[
      _buildQuestionPromptMessage(question),
      ...replayMessages,
    ];
    
    // Re-queue material images before replaying conversation history
    if (allImages.isNotEmpty) {
      debugPrint('[Tutor] Re-queuing ${allImages.length} images for replay');
      await _inference.addImagesToQueue(allImages);
    }
    
    await _inference.replayMessages(replayChain);
  }

  /// Send user message incrementally. No history param — InferenceChat maintains state.
  /// Yields: TutorThinking, TutorReply, or TutorEvaluation (when model calls tool).
  /// 
  /// Tool response flow: When model calls evaluate_understanding, we send a tool response
  /// back. The model will automatically continue generation after receiving the response.
  Stream<TutorEvent> sendQuestionTutorMessage(String userMessage) async* {
    if (!_inference.hasActiveSession) {
      throw StateError(
          'No active session. Call initQuestionTutorSession() first.');
    }

    final guard = ResponseLoopGuard();
    final replyBuffer = StringBuffer();
    final thinkingBuffer = StringBuffer();
    final toolCalls = <String>[];
    
    // Check if this is the first message (has pending images)
    // If so, mark as prefix for replay
    final isFirstMessage = _inference.hasPendingImages;
    await _inference.addTextQuery(userMessage, prefix: isFirstMessage);

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
        } else if (response is gemma.FunctionCallResponse || response is gemma.ParallelFunctionCallResponse) {
          // Handle both single and parallel function calls
          final calls = response is gemma.FunctionCallResponse
              ? [response]
              : (response as gemma.ParallelFunctionCallResponse).calls;
          
          for (final call in calls) {
            toolCalls.add('${call.name}(${call.args})');
            final error = guard.recordToolCall(call.name, call.args);
            if (error != null) {
              throw StateError(error);
            }
            if (call.name == 'evaluate_understanding') {
              final score = (call.args['score'] as num?)?.toDouble();
              if (score != null) {
                yield TutorEvaluation(score: score);
                // Send tool response so model can continue with congratulatory message
                // Response format: {'status': 'score_recorded', 'score: <value>}
                try {
                  await _inference.addToolResponse(
                    toolName: 'evaluate_understanding',
                    response: {'status': 'score_recorded', 'score': score},
                  );
                } catch (e) {
                  debugPrint('[Tutor] Failed to send tool response: $e');
                }
              }
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
    String locale = 'en',
    bool isThinking = false,
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
      ChatPrompts.getCoachSystemInstruction(session.title, locale),
    );
    if (textContext.isNotEmpty) {
      systemInstruction
        ..writeln('\n\n--- STUDY MATERIALS ---')
        ..write(textContext);
    }

    await _inference.createSession(
      systemInstruction: systemInstruction.toString(),
      temperature: 1.1,
      topK: 40,
      supportImage: hasImages,
      supportAudio: true,
      promptDialect: gemma.PromptDialect.gemma4,
      toolChoice: gemma.ToolChoice.auto,
      isThinking: isThinking,
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

  List<gemma.Message> _buildReplayMessages(List<QuestionMessage> history) {
    final replay = <gemma.Message>[];
    QuestionMessage? pendingUser;

    for (final message in history) {
      switch (message.role) {
        case QuestionMessageRole.user:
          pendingUser = message;
          break;
        case QuestionMessageRole.assistant:
          if (pendingUser == null) {
            break;
          }
          replay.add(
            gemma.Message.text(
              text: pendingUser.content,
              isUser: true,
            ),
          );
          replay.add(
            gemma.Message.text(
              text: message.content,
              isUser: false,
            ),
          );
          pendingUser = null;
          break;
      }
    }

    return replay;
  }

  gemma.Message _buildQuestionPromptMessage(Question question) {
    final prompt = StringBuffer()
      ..writeln('--- QUIZ QUESTION ---')
      ..writeln('Question: ${question.questionText}');

    if (question.type == QuestionType.multipleChoice && question.options.isNotEmpty) {
      prompt.writeln('Options:');
      for (var i = 0; i < question.options.length; i++) {
        prompt.writeln('${String.fromCharCode(65 + i)}) ${question.options[i]}');
      }
    }

    return gemma.Message.text(
      text: prompt.toString().trimRight(),
      isUser: false,
    );
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
    
    // Check if this is the first message (has pending images)
    // If so, mark as prefix for replay
    final isFirstMessage = _inference.hasPendingImages;
    await _inference.addTextQuery(message, prefix: isFirstMessage);

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
        } else if (response is gemma.FunctionCallResponse || response is gemma.ParallelFunctionCallResponse) {
          // Handle both single and parallel function calls
          final calls = response is gemma.FunctionCallResponse
              ? [response]
              : (response as gemma.ParallelFunctionCallResponse).calls;
          
          for (final call in calls) {
            toolCalls.add('${call.name}(${call.args})');
          }
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

  /// Send an audio-only coach message. Audio bytes must be WAV 16kHz mono 16-bit.
  Stream<TutorEvent> sendCoachAudioMessage(Uint8List audioBytes) async* {
    if (!_inference.hasActiveSession) {
      throw StateError('No active session. Call initCoachSession() first.');
    }

    final guard = ResponseLoopGuard();
    final replyBuffer = StringBuffer();
    final thinkingBuffer = StringBuffer();
    final toolCalls = <String>[];

    await _inference.addAudioQuery(audioBytes);

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
        } else if (response is gemma.FunctionCallResponse || response is gemma.ParallelFunctionCallResponse) {
          final calls = response is gemma.FunctionCallResponse
              ? [response]
              : (response as gemma.ParallelFunctionCallResponse).calls;
          for (final call in calls) {
            toolCalls.add('${call.name}(${call.args})');
          }
        }
      }
    } finally {
      _debugGemmaAudit(
        label: 'CoachAudio',
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
      _debugPrintChunked('[$label][Gemma][tools]', toolCalls.join('\n'));
    }
  }

  void _debugPrintChunked(String label, String text) {
    if (text.isEmpty) {
      debugPrint('$label <empty>');
      return;
    }

    const chunkSize = 700;
    for (var i = 0; i < text.length; i += chunkSize) {
      final end = (i + chunkSize < text.length) ? i + chunkSize : text.length;
      debugPrint('$label ${text.substring(i, end)}');
    }
  }
}
