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
  final int questionCount;
  final DateTime createdAt;

  const Session({
    this.id,
    required this.profileId,
    required this.title,
    required this.emoji,
    required this.gradeOverride,
    required this.questionCount,
    required this.createdAt,
  });

  Session copyWith({
    int? id,
    int? profileId,
    String? title,
    String? emoji,
    int? gradeOverride,
    int? questionCount,
    DateTime? createdAt,
  }) {
    return Session(
      id: id ?? this.id,
      profileId: profileId ?? this.profileId,
      title: title ?? this.title,
      emoji: emoji ?? this.emoji,
      gradeOverride: gradeOverride ?? this.gradeOverride,
      questionCount: questionCount ?? this.questionCount,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'profile_id': profileId,
        'title': title,
        'emoji': emoji,
        'grade_override': gradeOverride,
        'question_count': questionCount,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory Session.fromMap(Map<String, dynamic> map) {
    return Session(
      id: map['id'] as int?,
      profileId: map['profile_id'] as int,
      title: map['title'] as String,
      emoji: map['emoji'] as String,
      gradeOverride: map['grade_override'] as int,
      questionCount: map['question_count'] as int,
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
      kind: MaterialKind.values.firstWhere((value) => value.name == map['kind']),
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

@immutable
class Question {
  final int? id;
  final int quizId;
  final QuestionSource source;
  final String questionText;
  final String optionA;
  final String optionB;
  final String optionC;
  final String optionD;
  final String correctOption;
  final String explanation;
  final String? userAnswer;
  final int orderIndex;

  const Question({
    this.id,
    required this.quizId,
    required this.source,
    required this.questionText,
    required this.optionA,
    required this.optionB,
    required this.optionC,
    required this.optionD,
    required this.correctOption,
    required this.explanation,
    this.userAnswer,
    required this.orderIndex,
  });

  bool? get isCorrect {
    if (userAnswer == null) return null;
    return userAnswer == correctOption;
  }

  String optionForLetter(String letter) {
    switch (letter.toUpperCase()) {
      case 'A':
        return optionA;
      case 'B':
        return optionB;
      case 'C':
        return optionC;
      case 'D':
        return optionD;
      default:
        return optionA;
    }
  }

  Question copyWith({
    int? id,
    int? quizId,
    QuestionSource? source,
    String? questionText,
    String? optionA,
    String? optionB,
    String? optionC,
    String? optionD,
    String? correctOption,
    String? explanation,
    String? userAnswer,
    int? orderIndex,
  }) {
    return Question(
      id: id ?? this.id,
      quizId: quizId ?? this.quizId,
      source: source ?? this.source,
      questionText: questionText ?? this.questionText,
      optionA: optionA ?? this.optionA,
      optionB: optionB ?? this.optionB,
      optionC: optionC ?? this.optionC,
      optionD: optionD ?? this.optionD,
      correctOption: correctOption ?? this.correctOption,
      explanation: explanation ?? this.explanation,
      userAnswer: userAnswer ?? this.userAnswer,
      orderIndex: orderIndex ?? this.orderIndex,
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'quiz_id': quizId,
        'source_type': source.name,
        'question_text': questionText,
        'option_a': optionA,
        'option_b': optionB,
        'option_c': optionC,
        'option_d': optionD,
        'correct_option': correctOption,
        'explanation': explanation,
        'user_answer': userAnswer,
        'order_index': orderIndex,
      };

  factory Question.fromMap(Map<String, dynamic> map) {
    return Question(
      id: map['id'] as int?,
      quizId: map['quiz_id'] as int,
      source: QuestionSource.values.firstWhere(
        (value) => value.name == map['source_type'],
        orElse: () => QuestionSource.generated,
      ),
      questionText: map['question_text'] as String,
      optionA: map['option_a'] as String,
      optionB: map['option_b'] as String,
      optionC: map['option_c'] as String,
      optionD: map['option_d'] as String,
      correctOption: map['correct_option'] as String,
      explanation: map['explanation'] as String,
      userAnswer: map['user_answer'] as String?,
      orderIndex: map['order_index'] as int,
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
