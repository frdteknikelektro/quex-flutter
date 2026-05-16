import 'dart:convert';

import 'package:flutter/foundation.dart';

@immutable
class Profile {
  final int? id;
  final String name;
  final String emoji;
  final int grade;
  final int defaultQuestionCount;
  final DateTime createdAt;

  const Profile({
    this.id,
    required this.name,
    required this.emoji,
    required this.grade,
    this.defaultQuestionCount = 20,
    required this.createdAt,
  });

  Profile copyWith({
    int? id,
    String? name,
    String? emoji,
    int? grade,
    int? defaultQuestionCount,
    DateTime? createdAt,
  }) {
    return Profile(
      id: id ?? this.id,
      name: name ?? this.name,
      emoji: emoji ?? this.emoji,
      grade: grade ?? this.grade,
      defaultQuestionCount: defaultQuestionCount ?? this.defaultQuestionCount,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'emoji': emoji,
        'grade': grade,
        'default_question_count': defaultQuestionCount,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory Profile.fromMap(Map<String, dynamic> map) {
    return Profile(
      id: map['id'] as int?,
      name: map['name'] as String,
      emoji: map['emoji'] as String,
      grade: map['grade'] as int,
      defaultQuestionCount: map['default_question_count'] as int? ?? 20,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }
}

@immutable
class Session {
  final int? id;
  final int profileId;
  final String title;
  final String emoji;
  final int gradeOverride;
  final DateTime createdAt;

  const Session({
    this.id,
    required this.profileId,
    required this.title,
    required this.emoji,
    required this.gradeOverride,
    required this.createdAt,
  });

  Session copyWith({
    int? id,
    int? profileId,
    String? title,
    String? emoji,
    int? gradeOverride,
    DateTime? createdAt,
  }) {
    return Session(
      id: id ?? this.id,
      profileId: profileId ?? this.profileId,
      title: title ?? this.title,
      emoji: emoji ?? this.emoji,
      gradeOverride: gradeOverride ?? this.gradeOverride,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'profile_id': profileId,
        'title': title,
        'emoji': emoji,
        'grade_override': gradeOverride,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory Session.fromMap(Map<String, dynamic> map) {
    return Session(
      id: map['id'] as int?,
      profileId: map['profile_id'] as int,
      title: map['title'] as String,
      emoji: map['emoji'] as String,
      gradeOverride: map['grade_override'] as int,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }
}

enum MaterialKind { text, document, photo }

@immutable
class StudyMaterial {
  final int? id;
  final int sessionId;
  final MaterialKind kind;
  final String title;
  final String content;
  final int pageIndex;
  final DateTime createdAt;

  const StudyMaterial({
    this.id,
    required this.sessionId,
    required this.kind,
    required this.title,
    required this.content,
    required this.pageIndex,
    required this.createdAt,
  });

  StudyMaterial copyWith({
    int? id,
    int? sessionId,
    MaterialKind? kind,
    String? title,
    String? content,
    int? pageIndex,
    DateTime? createdAt,
  }) {
    return StudyMaterial(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      kind: kind ?? this.kind,
      title: title ?? this.title,
      content: content ?? this.content,
      pageIndex: pageIndex ?? this.pageIndex,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  String get preview {
    final snippet = content.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (snippet.isEmpty) return title;
    if (snippet.length <= 80) return snippet;
    return '${snippet.substring(0, 80)}...';
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'session_id': sessionId,
        'kind': kind.name,
        'title': title,
        'content': content,
        'page_index': pageIndex,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory StudyMaterial.fromMap(Map<String, dynamic> map) {
    return StudyMaterial(
      id: map['id'] as int?,
      sessionId: map['session_id'] as int,
      kind:
          MaterialKind.values.firstWhere((value) => value.name == map['kind']),
      title: map['title'] as String,
      content: map['content'] as String,
      pageIndex: map['page_index'] as int,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }
}

@immutable
class Quiz {
  final int? id;
  final int sessionId;
  final int questionCount;
  final int? score;
  final DateTime createdAt;
  final DateTime? completedAt;

  const Quiz({
    this.id,
    required this.sessionId,
    required this.questionCount,
    this.score,
    required this.createdAt,
    this.completedAt,
  });

  bool get isCompleted => completedAt != null;

  Quiz copyWith({
    int? id,
    int? sessionId,
    int? questionCount,
    int? score,
    DateTime? createdAt,
    DateTime? completedAt,
  }) {
    return Quiz(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      questionCount: questionCount ?? this.questionCount,
      score: score ?? this.score,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'session_id': sessionId,
        'question_count': questionCount,
        'score': score,
        'created_at': createdAt.millisecondsSinceEpoch,
        'completed_at': completedAt?.millisecondsSinceEpoch,
      };

  factory Quiz.fromMap(Map<String, dynamic> map) {
    return Quiz(
      id: map['id'] as int?,
      sessionId: map['session_id'] as int,
      questionCount: map['question_count'] as int,
      score: map['score'] as int?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      completedAt: map['completed_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(map['completed_at'] as int),
    );
  }
}

enum QuestionSource { extracted, generated, review }

enum QuestionType { multipleChoice, textAnswer }

@immutable
class Question {
  final int? id;
  final int quizId;
  final QuestionSource source;
  final QuestionType type;
  final String questionText;
  final List<String> options;
  final String? correctAnswer;
  final String? userAnswer;
  final int orderIndex;
  final double? score;

  const Question({
    this.id,
    required this.quizId,
    required this.source,
    this.type = QuestionType.multipleChoice,
    required this.questionText,
    required this.options,
    this.correctAnswer,
    this.userAnswer,
    required this.orderIndex,
    this.score,
  });

  String? get userAnswerText {
    if (userAnswer == null) return null;
    if (type == QuestionType.textAnswer) return userAnswer;
    final idx = userAnswer!.codeUnitAt(0) - 'A'.codeUnitAt(0);
    return idx < options.length ? options[idx] : null;
  }

  Question copyWith({
    int? id,
    int? quizId,
    QuestionSource? source,
    QuestionType? type,
    String? questionText,
    List<String>? options,
    String? correctAnswer,
    String? userAnswer,
    int? orderIndex,
    double? score,
  }) {
    return Question(
      id: id ?? this.id,
      quizId: quizId ?? this.quizId,
      source: source ?? this.source,
      type: type ?? this.type,
      questionText: questionText ?? this.questionText,
      options: options ?? this.options,
      correctAnswer: correctAnswer ?? this.correctAnswer,
      userAnswer: userAnswer ?? this.userAnswer,
      orderIndex: orderIndex ?? this.orderIndex,
      score: score ?? this.score,
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'quiz_id': quizId,
        'source_type': source.name,
        'type': type.name,
        'question_text': questionText,
        'options': jsonEncode(options),
        'correct_answer': correctAnswer,
        'user_answer': userAnswer,
        'order_index': orderIndex,
        'score': score,
      };

  factory Question.fromMap(Map<String, dynamic> map) {
    final rawOptions = map['options'] as String? ?? '[]';
    final optionsList =
        (jsonDecode(rawOptions) as List<dynamic>).cast<String>();
    return Question(
      id: map['id'] as int?,
      quizId: map['quiz_id'] as int,
      source: QuestionSource.values.firstWhere(
        (v) => v.name == map['source_type'],
        orElse: () => QuestionSource.generated,
      ),
      type: QuestionType.values.firstWhere(
        (v) => v.name == (map['type'] as String? ?? 'multipleChoice'),
        orElse: () => QuestionType.multipleChoice,
      ),
      questionText: map['question_text'] as String,
      options: optionsList,
      correctAnswer: map['correct_answer'] as String?,
      userAnswer: map['user_answer'] as String?,
      orderIndex: map['order_index'] as int,
      score: map['score'] as double?,
    );
  }
}

enum QuestionMessageRole { user, assistant }

@immutable
class QuestionMessage {
  final int? id;
  final int questionId;
  final QuestionMessageRole role;
  final String content;
  final DateTime createdAt;

  const QuestionMessage({
    this.id,
    required this.questionId,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  QuestionMessage copyWith({
    int? id,
    int? questionId,
    QuestionMessageRole? role,
    String? content,
    DateTime? createdAt,
  }) {
    return QuestionMessage(
      id: id ?? this.id,
      questionId: questionId ?? this.questionId,
      role: role ?? this.role,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'question_id': questionId,
        'role': role.name,
        'content': content,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory QuestionMessage.fromMap(Map<String, dynamic> map) {
    return QuestionMessage(
      id: map['id'] as int?,
      questionId: map['question_id'] as int,
      role: QuestionMessageRole.values.firstWhere(
        (v) => v.name == map['role'],
        orElse: () => QuestionMessageRole.assistant,
      ),
      content: map['content'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }
}

enum ChatRole { user, assistant }

@immutable
class ChatMessage {
  final int? id;
  final int sessionId;
  final ChatRole role;
  final String content;
  final DateTime createdAt;

  const ChatMessage({
    this.id,
    required this.sessionId,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  ChatMessage copyWith({
    int? id,
    int? sessionId,
    ChatRole? role,
    String? content,
    DateTime? createdAt,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      role: role ?? this.role,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'session_id': sessionId,
        'role': role.name,
        'content': content,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      id: map['id'] as int?,
      sessionId: map['session_id'] as int,
      role: ChatRole.values.firstWhere(
        (value) => value.name == map['role'],
        orElse: () => ChatRole.assistant,
      ),
      content: map['content'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }
}
