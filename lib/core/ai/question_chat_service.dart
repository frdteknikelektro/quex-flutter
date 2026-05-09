import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart' as gemma;

import '../models/models.dart';
import 'chat_prompts.dart';
import 'gemma_chat_service.dart';
import 'material_preprocessor.dart';
import 'tutor_event.dart';

/// Question tutor chat service.
///
/// Wraps [GemmaChatService] with tutor-specific logic:
/// - Tutor system prompt + question context
/// - evaluate_understanding tool for scoring answers
/// - Material image injection on first message
class QuestionChatService {
  final GemmaChatService _chatService = GemmaChatService.getInstance();
  bool _sessionCreated = false;
  double? _pendingScore;
  final List<Uint8List> _materialImages = [];

  bool get isInitialized => _chatService.isInitialized;
  bool get hasSession => _sessionCreated;
  int? get effectiveMaxTokens => _chatService.effectiveMaxTokens;

  Future<void> initialize() => _chatService.initialize();

  Future<void> createSession({
    required Question question,
    required List<StudyMaterial> materials,
    String locale = 'en',
    bool isThinking = false,
  }) async {
    final prepared = await MaterialPreprocessor.prepare(materials);

    final textContext = prepared
        .where((p) => p.textChunk.isNotEmpty)
        .map((p) => p.textChunk)
        .join('\n\n');

    _materialImages
      ..clear()
      ..addAll(prepared.expand((p) => p.images));

    debugPrint(
        '[QuestionChatService] createSession: ${_materialImages.length} material images');

    final systemInstruction = StringBuffer(
      ChatPrompts.getTutorSystemInstruction(locale),
    );
    if (textContext.isNotEmpty) {
      systemInstruction
        ..writeln()
        ..writeln('--- STUDY MATERIALS ---')
        ..write(textContext);
    }

    systemInstruction.writeln('\n--- QUIZ QUESTION ---');
    systemInstruction.writeln('Question: ${question.questionText}');
    if (question.type == QuestionType.multipleChoice &&
        question.options.isNotEmpty) {
      systemInstruction.writeln('Options:');
      for (var i = 0; i < question.options.length; i++) {
        systemInstruction
            .writeln('${String.fromCharCode(65 + i)}) ${question.options[i]}');
      }
    }

    await _chatService.createSession(
      systemInstruction: systemInstruction.toString(),
      temperature: 1.0,
      topP: 0.95,
      topK: 64,
      isThinking: isThinking,
      tools: [_evaluateTool],
      toolExecutor: (name, args) async {
        if (name == 'evaluate_understanding') {
          _pendingScore = (args['score'] as num?)?.toDouble();
          debugPrint('[QuestionChatService] tool called: score=$_pendingScore');
        }
        return {'status': 'score_recorded', 'score': _pendingScore ?? 0.0};
      },
    );
    _sessionCreated = true;
  }

  /// Send the opener/greeting message. Returns stream of tutor events.
  Stream<TutorEvent> sendOpener(
    String locale, {
    List<Uint8List> images = const [],
  }) async* {
    _pendingScore = null;
    final allImages = <Uint8List>[..._materialImages, ...images];
    _materialImages.clear();

    final openerMessage = ChatPrompts.getTutorOpenerMessage(locale);
    final Stream<({String? text, String? thinking})> stream;

    if (allImages.isNotEmpty) {
      stream = _chatService.sendMessageWithImages(openerMessage, allImages);
    } else {
      stream = _chatService.sendMessage(openerMessage);
    }

    await for (final event in stream) {
      if (event.thinking != null) yield TutorThinking(event.thinking!);
      if (event.text != null) yield TutorReply(event.text!);
    }
  }

  /// Stream TutorThinking, TutorReply, and optionally TutorEvaluation events.
  ///
  /// Material images are sent with the first message, then cleared.
  /// [images] are user-attached images sent with this message.
  /// TutorEvaluation is appended at end of stream if evaluate_understanding was called.
  Stream<TutorEvent> sendMessage(String message,
      {List<Uint8List> images = const []}) async* {
    _pendingScore = null;

    final Stream<({String? text, String? thinking})> stream;
    if (_materialImages.isNotEmpty || images.isNotEmpty) {
      final allImages = [..._materialImages, ...images];
      _materialImages.clear();
      debugPrint(
          '[QuestionChatService] sendMessage: including ${allImages.length} images');
      stream = _chatService.sendMessageWithImages(message, allImages);
    } else {
      stream = _chatService.sendMessage(message);
    }

    await for (final event in stream) {
      if (event.thinking != null) yield TutorThinking(event.thinking!);
      if (event.text != null) yield TutorReply(event.text!);
    }

    if (_pendingScore != null) yield TutorEvaluation(score: _pendingScore!);
  }

  Stream<TutorEvent> sendUserAudio(Uint8List audioBytes) async* {
    _pendingScore = null;
    await for (final event in _chatService.sendAudioMessage(audioBytes)) {
      if (event.thinking != null) yield TutorThinking(event.thinking!);
      if (event.text != null) yield TutorReply(event.text!);
    }
    if (_pendingScore != null) yield TutorEvaluation(score: _pendingScore!);
  }

  dynamic getSessionMetrics() => _chatService.getSessionMetrics();

  Future<void> stopGeneration() => _chatService.stopGeneration();

  Future<void> resetSession() async {
    await _chatService.closeSession();
    _sessionCreated = false;
    _pendingScore = null;
    _materialImages.clear();
  }

  Future<void> dispose() => resetSession();

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
}
