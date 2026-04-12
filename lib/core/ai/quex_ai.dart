import 'dart:math';

import '../models/models.dart';

class QuexAi {
  static List<Question> buildQuiz({
    required Session session,
    required List<StudyMaterial> materials,
    required int questionCount,
  }) {
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

      final options = <String>[
        correct,
        ...distractors.take(3),
      ];
      options.shuffle(rng);

      final correctLetter = ['A', 'B', 'C', 'D'][options.indexOf(correct)];
      questions.add(
        Question(
          quizId: -1,
          source: QuestionSource.generated,
          questionText: templates[index % templates.length],
          optionA: options[0],
          optionB: options[1],
          optionC: options[2],
          optionD: options[3],
          correctOption: correctLetter,
          explanation: 'This option best reflects the material on "${session.title}".',
          orderIndex: index,
        ),
      );
    }
    return questions;
  }

  static String coachReply({
    required Session session,
    required List<StudyMaterial> materials,
    required List<ChatMessage> history,
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

  static String sessionSummary(Session session, List<StudyMaterial> materials) {
    return _sessionSummary(session, materials);
  }

  static List<String> highlights(List<StudyMaterial> materials) => _topics(materials);

  static List<String> _snippets(List<StudyMaterial> materials) {
    final snippets = <String>[];
    for (final material in materials) {
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
    final words = <String>[];
    for (final material in materials) {
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
    final otherSnippets = focus.where((item) => item != current).map(_shorten).toList();
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

  static String _sessionSummary(Session session, List<StudyMaterial> materials) {
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
