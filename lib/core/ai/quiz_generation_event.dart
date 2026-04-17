import '../models/models.dart';

sealed class QuizGenerationEvent {}

class QuizThinkingToken extends QuizGenerationEvent {
  final String token;
  QuizThinkingToken(this.token);
}

class QuizTextToken extends QuizGenerationEvent {
  final String token;
  QuizTextToken(this.token);
}

class QuizGenerationStarted extends QuizGenerationEvent {
  final int total;
  QuizGenerationStarted(this.total);
}

class QuizQuestionGenerated extends QuizGenerationEvent {
  final Question question;
  final int index; // 1-based
  final int total;
  QuizQuestionGenerated(this.question, this.index, this.total);
}

class QuizGenerationComplete extends QuizGenerationEvent {
  final List<Question> questions;
  QuizGenerationComplete(this.questions);
}

class QuizGenerationError extends QuizGenerationEvent {
  final String message;
  QuizGenerationError(this.message);
}
