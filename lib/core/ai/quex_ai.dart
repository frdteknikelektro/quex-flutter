import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'gemma_service_manager.dart';
import 'gemma_inference_service.dart';
import 'tutor_event.dart';
import '../models/models.dart';

class QuexAi {
  static GemmaServiceManager _gemmaServiceManager =
      GemmaServiceManager.instance;

  @visibleForTesting
  static void setGemmaServiceManager(GemmaServiceManager manager) {
    _gemmaServiceManager = manager;
  }

  @visibleForTesting
  static void resetGemmaServiceManager() {
    _gemmaServiceManager = GemmaServiceManager.instance;
  }

  static GemmaInferenceService? get gemmaService =>
      _gemmaServiceManager.current;

  /// Whether the Gemma service is initialized and ready for inference.
  static bool get isReady => _gemmaServiceManager.isReady;

  static bool isCurrentGemmaOwner(Object ownerToken) =>
      _gemmaServiceManager.isCurrentOwner(ownerToken);

  static Future<GemmaInferenceService> acquireGemmaService(
    Object ownerToken,
  ) {
    return _gemmaServiceManager.acquire(ownerToken);
  }

  static Future<void> releaseGemmaService(Object ownerToken) {
    return _gemmaServiceManager.release(ownerToken);
  }

  /// Build a rule-based quiz from study materials (fallback when AI unavailable).
  static List<Question> buildQuizRuleBased({
    required Session session,
    required List<StudyMaterial> materials,
  }) {
    const questionCount = 10;
    final snippets = _snippets(materials);
    final focus = snippets.isEmpty
        ? [session.title, 'study skills', 'important ideas']
        : snippets;
    final templates = <String>[
      'Which idea is best supported by this material?',
      'What is the clearest takeaway from this section?',
      'Which statement matches the study material?',
      'What should the learner remember most?',
    ];

    final questions = <Question>[];
    for (var index = 0; index < questionCount; index++) {
      final source = focus[index % focus.length];
      final rng = Random(source.hashCode ^ index);
      final correct = _shorten(source);
      final distractors = _distractors(
        focus: focus,
        current: source,
        sessionTitle: session.title,
      );

      final options = <String>[correct, ...distractors.take(3)];
      options.shuffle(rng);

      questions.add(
        Question(
          quizId: -1,
          source: QuestionSource.generated,
          type: QuestionType.multipleChoice,
          questionText: templates[index % templates.length],
          options: options,
          orderIndex: index,
        ),
      );
    }
    return questions;
  }

  /// Get coach reply with optional LLM enhancement.
  /// Uses Gemma E4B when available, otherwise falls back to rule-based responses.
  static Future<String> coachReply({
    required Session session,
    required List<StudyMaterial> materials,
    required List<ChatMessage> history,
    required String message,
  }) async {
    // Try LLM-powered coach reply if service is available
    final service = gemmaService;
    if (service != null && service.isInitialized) {
      try {
        return await service.getCoachReply(
          session: session,
          materials: materials,
          history: history,
          message: message,
        );
      } catch (_) {
        // Fall back to rule-based on error
      }
    }

    // Rule-based fallback
    return _coachReplyRuleBased(
      session: session,
      materials: materials,
      message: message,
    );
  }

  static String _coachReplyRuleBased({
    required Session session,
    required List<StudyMaterial> materials,
    required String message,
  }) {
    final topics = _topics(materials);
    final lower = message.toLowerCase();

    if (lower.contains('quiz') || lower.contains('test')) {
      return 'I can help you review "${session.title}". '
          'Try a quiz on ${topics.isEmpty ? 'the main ideas' : topics.first}.';
    }
    if (lower.contains('summary') || lower.contains('summarize')) {
      return 'Here is the short version: ${_sessionSummary(session, materials)}';
    }
    if (lower.contains('help') || lower.contains('explain')) {
      return 'Start with the title, then look for repeated ideas like '
          '${topics.isEmpty ? 'definitions and examples' : topics.join(', ')}.';
    }

    final topicText = topics.isEmpty ? session.title : topics.first;
    return 'For ${session.title}, focus on $topicText and turn it into a simple question. '
        'I can also make a quiz or summary if you want.';
  }

  /// Get tutor reply for a specific question, plus an AI-evaluated score (0.0–1.0).
  /// Uses two separate Gemma calls: one for reply, one for evaluation.
  /// Throws [StateError] if Gemma service is not initialized.
  static Future<({String reply, double? score})> questionCoachReply({
    required Question question,
    required List<StudyMaterial> materials,
    required List<QuestionMessage> history,
    required String userMessage,
  }) async {
    if (!isReady) throw StateError('Gemma service not initialized.');
    final service = gemmaService;
    if (service == null || !service.isInitialized) {
      throw StateError('Gemma service not initialized.');
    }
    final reply = await service.getQuestionTutorReply(
      question: question,
      materials: materials,
      history: history,
      userMessage: userMessage,
    );
    final updatedHistory = [
      ...history,
      QuestionMessage(
        questionId: question.id!,
        role: QuestionMessageRole.user,
        content: userMessage,
        createdAt: DateTime.now(),
      ),
      QuestionMessage(
        questionId: question.id!,
        role: QuestionMessageRole.assistant,
        content: reply,
        createdAt: DateTime.now(),
      ),
    ];
    final score = await service.evaluateQuestionScore(
      question: question,
      materials: materials,
      history: updatedHistory,
    );
    return (reply: reply, score: score);
  }

  /// Streaming coach reply for session-level chat.
  /// Yields [TutorThinking] then [TutorReply] tokens.
  /// Throws [StateError] if Gemma service is not initialized.
  static Stream<TutorEvent> coachReplyStream({
    required Session session,
    required List<StudyMaterial> materials,
    required List<ChatMessage> history,
    required String message,
  }) {
    if (!isReady) throw StateError('Gemma service not initialized.');
    final service = gemmaService;
    if (service == null || !service.isInitialized) {
      throw StateError('Gemma service not initialized.');
    }
    return service.getCoachReplyStreaming(
      session: session,
      materials: materials,
      history: history,
      message: message,
    );
  }

  /// Streaming tutor reply with thinking mode and multimodal image support.
  /// Yields [TutorThinking] tokens first, then [TutorReply] tokens.
  /// Throws [StateError] if Gemma service is not initialized.
  static Stream<TutorEvent> questionCoachReplyStream({
    required Question question,
    required List<StudyMaterial> materials,
    required List<QuestionMessage> history,
    required String userMessage,
  }) {
    if (!isReady) throw StateError('Gemma service not initialized.');
    final service = gemmaService;
    if (service == null || !service.isInitialized) {
      throw StateError('Gemma service not initialized.');
    }
    return service.getQuestionTutorReplyStreaming(
      question: question,
      materials: materials,
      history: history,
      userMessage: userMessage,
    );
  }

  /// Evaluate student understanding after a completed exchange (0.0–1.0).
  /// Returns null if service unavailable or history is empty.
  static Future<double?> evaluateScore({
    required Question question,
    required List<StudyMaterial> materials,
    required List<QuestionMessage> history,
  }) async {
    if (!isReady) return null;
    final service = gemmaService;
    if (service == null || !service.isInitialized) return null;
    return await service.evaluateQuestionScore(
      question: question,
      materials: materials,
      history: history,
    );
  }

  static String sessionSummary(Session session, List<StudyMaterial> materials) {
    return _sessionSummary(session, materials);
  }

  static List<String> highlights(List<StudyMaterial> materials) =>
      _topics(materials);

  static List<String> _snippets(List<StudyMaterial> materials) {
    final textOnly =
        materials.where((m) => m.kind == MaterialKind.text).toList();
    final snippets = <String>[];
    for (final material in textOnly) {
      final parts = material.content
          .split(RegExp(r'[\n\r\.!?]+'))
          .map((part) => part.trim())
          .where((part) => part.length >= 16);
      snippets.addAll(parts);
    }
    return snippets.isEmpty
        ? materials.map((material) => material.title).toList()
        : snippets.toList();
  }

  static List<String> _topics(List<StudyMaterial> materials) {
    final textOnly =
        materials.where((m) => m.kind == MaterialKind.text).toList();
    final words = <String>[];
    for (final material in textOnly) {
      words.addAll(
        material.content
            .split(RegExp(r'[^A-Za-z0-9]+'))
            .map((word) => word.trim())
            .where((word) => word.length > 5),
      );
    }

    final unique = <String>{};
    for (final word in words) {
      unique.add(word.toLowerCase());
    }

    return unique.take(4).map((value) => _titleCase(value)).toList();
  }

  static List<String> _distractors({
    required List<String> focus,
    required String current,
    required String sessionTitle,
  }) {
    final otherSnippets =
        focus.where((item) => item != current).map(_shorten).toList();
    final pool = <String>[
      ...otherSnippets,
      'A different idea from the lesson.',
      'An unrelated concept.',
      'Something not mentioned in "$sessionTitle".',
    ];
    return pool.toSet().toList();
  }

  static String _shorten(String text) {
    final cleaned = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.length <= 72) return cleaned;
    return '${cleaned.substring(0, 72)}...';
  }

  static String _titleCase(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
  }

  static String _sessionSummary(
      Session session, List<StudyMaterial> materials) {
    if (materials.isEmpty) {
      return 'No materials yet for "${session.title}". Add notes first, then generate a quiz.';
    }
    final highlights = _topics(materials);
    final summary = highlights.isEmpty
        ? 'key points from the materials'
        : highlights.join(', ');
    return 'The session "${session.title}" covers $summary.';
  }
}
