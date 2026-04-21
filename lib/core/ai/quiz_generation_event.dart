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

// 2. Planning phase
class QuizPlanned extends QuizGenerationEvent {
  final int questionCount;
  final List<String> topics;
  QuizPlanned(this.questionCount, this.topics);
}

class QuizPlanAnnounced extends QuizGenerationEvent {
  final List<String> steps;
  QuizPlanAnnounced(this.steps);
}

class QuizStepCompleted extends QuizGenerationEvent {
  final int index;
  QuizStepCompleted(this.index);
}

// 3. Review phase
class QuizUnderReview extends QuizGenerationEvent {
  final List<String> issues;
  QuizUnderReview(this.issues);
}

class QuizRegenerating extends QuizGenerationEvent {
  final int index;
  QuizRegenerating(this.index);
}

// 4. Submission
class QuizSubmitted extends QuizGenerationEvent {
  final String summary;
  QuizSubmitted(this.summary);
}

class QuizGenerationComplete extends QuizGenerationEvent {
  final List<Question> questions;
  QuizGenerationComplete(this.questions);
}

class QuizGenerationError extends QuizGenerationEvent {
  final String message;
  QuizGenerationError(this.message);
}
