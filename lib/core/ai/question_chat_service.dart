import 'dart:async';
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
  static QuestionChatService? _instance;

  factory QuestionChatService() =>
      _instance ??= QuestionChatService._internal();

  QuestionChatService._internal();

  final GemmaChatService _chatService = GemmaChatService.getInstance();
  bool _sessionCreated = false;
  bool _sessionConsumed = false;
  bool _sessionWarmupComplete = false;
  double? _pendingScore;
  final List<Uint8List> _materialImages = [];
  String? _activeQuestionContext;
  bool _questionContextInjected = false;
  Future<void>? _prewarmFuture;
  Completer<void>? _questionTurnCompleter;
  int _questionTurnId = 0;
  bool _questionTurnCancelled = false;
  int _resetEpoch = 0;
  int _sessionGeneration = 0;
  Future<void> _lifecycleQueue = Future.value();

  bool get isInitialized => _chatService.isInitialized;
  bool get hasSession => _sessionCreated;
  int? get effectiveMaxTokens => _chatService.effectiveMaxTokens;
  int get sessionGeneration => _sessionGeneration;

  Future<void> initialize() => _chatService.initialize();

  int beginQuestionTurn() {
    final completer = _questionTurnCompleter;
    if (completer != null && !completer.isCompleted) {
      return _questionTurnId;
    }
    _questionTurnId++;
    _questionTurnCancelled = false;
    _questionTurnCompleter = Completer<void>();
    return _questionTurnId;
  }

  void cancelQuestionTurn(int questionTurnId) {
    if (_questionTurnCompleter == null || _questionTurnId != questionTurnId) {
      return;
    }
    _questionTurnCancelled = true;
  }

  bool isQuestionTurnCancelled(int questionTurnId) =>
      _questionTurnId == questionTurnId && _questionTurnCancelled;

  bool isQuestionTurnActive(int questionTurnId) =>
      _questionTurnCompleter != null && _questionTurnId == questionTurnId;

  void endQuestionTurn([int? questionTurnId]) {
    final completer = _questionTurnCompleter;
    if (completer == null) return;
    if (questionTurnId != null && _questionTurnId != questionTurnId) return;
    _questionTurnCompleter = null;
    _questionTurnCancelled = false;
    if (!completer.isCompleted) completer.complete();
  }

  Future<void> waitForQuestionTurnToEnd() =>
      _questionTurnCompleter?.future ?? Future.value();

  Future<T> _runExclusive<T>(Future<T> Function() action) {
    final previous = _lifecycleQueue;
    late final Future<T> result;
    result = previous.catchError((_) {}).then((_) => action());
    _lifecycleQueue = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  Future<void> prewarmSession({
    required List<StudyMaterial> materials,
    String locale = 'en',
    bool isThinking = false,
  }) {
    final existing = _prewarmFuture;
    if (existing != null) {
      return existing;
    }
    if (_sessionCreated && !_sessionConsumed && _sessionWarmupComplete) {
      return Future.value();
    }

    final epoch = _resetEpoch;
    final future = _runExclusive(
      () => _prewarmSession(
        materials: materials,
        locale: locale,
        isThinking: isThinking,
        epoch: epoch,
      ),
    );
    late final Future<void> tracked;
    tracked = future.whenComplete(() {
      if (identical(_prewarmFuture, tracked)) {
        _prewarmFuture = null;
      }
    });
    _prewarmFuture = tracked;
    return tracked;
  }

  Future<void> _prewarmSession({
    required List<StudyMaterial> materials,
    required String locale,
    required bool isThinking,
    required int epoch,
  }) async {
    if (!_chatService.isInitialized) {
      await _chatService.initialize();
    }
    if (epoch != _resetEpoch) return;

    final prepared = await _prepareSessionContext(materials);
    if (epoch != _resetEpoch) return;

    if (_sessionCreated && !_sessionConsumed && _sessionWarmupComplete) {
      return;
    }

    final createdGeneration = await _createNativeSession(
      prepared: prepared,
      locale: locale,
      isThinking: isThinking,
    );
    debugPrint(
        '[QuestionChatService] Prewarm native session created: generation=$createdGeneration');
    if (epoch != _resetEpoch) {
      await _discardSessionGeneration(createdGeneration);
      return;
    }
    await _runWarmupInference(prepared.images);
    if (epoch != _resetEpoch) {
      await _discardSessionGeneration(createdGeneration);
      return;
    }
    _activeQuestionContext = null;
    _sessionConsumed = false;
    _sessionWarmupComplete = true;
    debugPrint(
        '[QuestionChatService] Prewarmed tutor session ready: generation=$createdGeneration');
  }

  Future<void> createSession({
    required Question question,
    required List<StudyMaterial> materials,
    required int questionTurnId,
    String locale = 'en',
    bool isThinking = false,
  }) =>
      _runExclusive(() async {
        final prewarmFuture = _prewarmFuture;
        if (prewarmFuture != null) {
          await prewarmFuture;
        }
        if (!isQuestionTurnActive(questionTurnId) ||
            isQuestionTurnCancelled(questionTurnId)) {
          _activeQuestionContext = null;
          _questionContextInjected = false;
          return;
        }
        _activeQuestionContext = _buildQuestionContext(question);
        _questionContextInjected = false;

        if (_sessionCreated && !_sessionConsumed && _sessionWarmupComplete) {
          _sessionConsumed = true;
          debugPrint(
              '[QuestionChatService] Consuming prewarmed tutor session for question ${question.id}');
          return;
        }

        final prepared = await _prepareSessionContext(materials);
        if (!isQuestionTurnActive(questionTurnId) ||
            isQuestionTurnCancelled(questionTurnId)) {
          _activeQuestionContext = null;
          return;
        }

        final createdGeneration = await _createNativeSession(
          prepared: prepared,
          locale: locale,
          isThinking: isThinking,
        );
        if (!isQuestionTurnActive(questionTurnId) ||
            isQuestionTurnCancelled(questionTurnId)) {
          await _discardSessionGeneration(createdGeneration);
          return;
        }
        _sessionWarmupComplete = false;
        _sessionConsumed = true;
      });

  Future<_TutorSessionContext> _prepareSessionContext(
    List<StudyMaterial> materials,
  ) async {
    final prepared = await MaterialPreprocessor.prepare(materials);
    final textContext = prepared
        .where((p) => p.textChunk.isNotEmpty)
        .map((p) => p.textChunk)
        .join('\n\n');
    final images = prepared.expand((p) => p.images).toList();

    debugPrint(
        '[QuestionChatService] prepared tutor context: ${images.length} material images');

    return _TutorSessionContext(
      textContext: textContext,
      images: images,
    );
  }

  Future<int> _createNativeSession({
    required _TutorSessionContext prepared,
    required String locale,
    required bool isThinking,
  }) async {
    _materialImages
      ..clear()
      ..addAll(prepared.images);

    final systemInstruction = StringBuffer(
      ChatPrompts.getTutorSystemInstruction(locale),
    );
    if (prepared.textContext.isNotEmpty) {
      systemInstruction
        ..writeln()
        ..writeln('--- STUDY MATERIALS ---')
        ..write(prepared.textContext);
    }
    systemInstruction
      ..writeln()
      ..writeln('Wait for a --- QUIZ QUESTION --- block before tutoring.')
      ..writeln('Treat that block as the only active quiz question.');

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
    _sessionWarmupComplete = false;
    _sessionGeneration++;
    return _sessionGeneration;
  }

  Future<void> _runWarmupInference(List<Uint8List> images) async {
    const prompt =
        'Internal warmup. Read the study materials for later tutoring. '
        'Do not explain. Reply exactly READY.';
    final warmupImages = List<Uint8List>.from(images);
    final responseBuffer = StringBuffer();
    final previousPendingScore = _pendingScore;
    _pendingScore = null;
    _materialImages.clear();

    try {
      final Stream<({String? text, String? thinking})> stream;
      if (warmupImages.isNotEmpty) {
        stream = _chatService.sendMessageWithImages(prompt, warmupImages);
      } else {
        stream = _chatService.sendMessage(prompt);
      }

      await for (final event in stream) {
        if (event.text != null) responseBuffer.write(event.text);
        if (event.thinking != null) {
          debugPrint('[QuestionChatService] hidden warmup thinking discarded');
        }
      }

      if (!responseBuffer.toString().contains('READY')) {
        debugPrint(
            '[QuestionChatService] Warmup completed without READY sentinel: ${responseBuffer.toString()}');
      }
    } finally {
      _pendingScore = previousPendingScore;
    }
  }

  /// Send the opener/greeting message. Returns stream of tutor events.
  Stream<TutorEvent> sendOpener(
    String locale, {
    List<Uint8List> images = const [],
  }) async* {
    _pendingScore = null;
    final allImages = <Uint8List>[..._materialImages, ...images];
    _materialImages.clear();

    final openerMessage = _withActiveQuestion(
      ChatPrompts.getTutorOpenerMessage(locale),
    );
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
    await _injectQuestionContextIfNeeded();

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
    await _injectQuestionContextIfNeeded();
    await for (final event in _chatService.sendAudioMessage(audioBytes)) {
      if (event.thinking != null) yield TutorThinking(event.thinking!);
      if (event.text != null) yield TutorReply(event.text!);
    }
    if (_pendingScore != null) yield TutorEvaluation(score: _pendingScore!);
  }

  Future<void> _injectQuestionContextIfNeeded() async {
    if (!_chatService.hasActiveSession || _questionContextInjected) {
      return;
    }
    final context = _activeQuestionContext;
    if (context == null || context.isEmpty) return;

    await _chatService.addAssistantContext(context);
    _questionContextInjected = true;
    _activeQuestionContext = null;
  }

  dynamic getSessionMetrics() => _chatService.getSessionMetrics();

  Future<void> stopGeneration() => _chatService.stopGeneration();

  Future<void> resetSession() {
    _resetEpoch++;
    return _runExclusive(_resetSessionLocked);
  }

  Future<void> _resetSessionLocked() async {
    await _chatService.closeSession();
    _sessionCreated = false;
    _sessionConsumed = false;
    _sessionWarmupComplete = false;
    _activeQuestionContext = null;
    _pendingScore = null;
    _materialImages.clear();
    _prewarmFuture = null;
    _questionContextInjected = false;
    _sessionGeneration++;
  }

  Future<void> resetSessionForGeneration(int sessionGeneration) =>
      _runExclusive(() async {
        if (_sessionGeneration != sessionGeneration) {
          debugPrint(
              '[QuestionChatService] Skipping reset for stale generation: requested=$sessionGeneration current=$_sessionGeneration');
          return;
        }
        _resetEpoch++;
        await _chatService.closeSession();
        if (_sessionGeneration != sessionGeneration) return;
        _sessionCreated = false;
        _sessionConsumed = false;
        _sessionWarmupComplete = false;
        _activeQuestionContext = null;
        _pendingScore = null;
        _materialImages.clear();
        _prewarmFuture = null;
        _questionContextInjected = false;
        _sessionGeneration++;
      });

  Future<void> dispose() => resetSession();

  Future<void> _discardSessionGeneration(int sessionGeneration) async {
    if (_sessionGeneration != sessionGeneration) return;
    await _chatService.closeSession();
    if (_sessionGeneration != sessionGeneration) return;
    _sessionCreated = false;
    _sessionConsumed = false;
    _sessionWarmupComplete = false;
    _activeQuestionContext = null;
    _pendingScore = null;
    _materialImages.clear();
    _questionContextInjected = false;
    _sessionGeneration++;
  }

  Future<void> stopActiveQuestionSession(int sessionGeneration) =>
      _runExclusive(() async {
        if (!_sessionCreated ||
            !_sessionConsumed ||
            _sessionGeneration != sessionGeneration) {
          debugPrint(
              '[QuestionChatService] Ignoring stale question cleanup: requested=$sessionGeneration current=$_sessionGeneration');
          return;
        }
        debugPrint(
            '[QuestionChatService] Stopping active question generation: generation=$sessionGeneration');
        await _chatService.stopGeneration();
      });

  String _withActiveQuestion(String message) {
    final context = _activeQuestionContext;
    if (context == null || context.isEmpty) return message;
    return '$context\n\n$message';
  }

  String _buildQuestionContext(Question question) {
    final buffer = StringBuffer()
      ..writeln('--- QUIZ QUESTION ---')
      ..writeln('Question: ${question.questionText}');
    if (question.type == QuestionType.multipleChoice &&
        question.options.isNotEmpty) {
      buffer.writeln('Options:');
      for (var i = 0; i < question.options.length; i++) {
        buffer
            .writeln('${String.fromCharCode(65 + i)}) ${question.options[i]}');
      }
    }
    return buffer.toString().trim();
  }

  static const _evaluateTool = gemma.Tool(
    name: 'evaluate_understanding',
    description: 'Rate the student\'s attempted answer to the active quiz '
        'question from 0.0 to 1.0. Call this whenever the student gives a '
        'clear answer attempt, including correct, partial, or wrong answers.',
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

class _TutorSessionContext {
  final String textContext;
  final List<Uint8List> images;

  const _TutorSessionContext({
    required this.textContext,
    required this.images,
  });
}
