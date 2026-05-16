import '../models/models.dart';

sealed class QuizGenerationEvent {}

enum QuizGenerationPhase {
  review,
  generation,
}

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

class QuizPhaseStarted extends QuizGenerationEvent {
  final QuizGenerationPhase phase;
  QuizPhaseStarted(this.phase);
}

class QuizPhaseTextToken extends QuizGenerationEvent {
  final QuizGenerationPhase phase;
  final String token;
  QuizPhaseTextToken(this.phase, this.token);
}

class QuizPhaseCompleted extends QuizGenerationEvent {
  final QuizGenerationPhase phase;
  QuizPhaseCompleted(this.phase);
}

class QuizQuestionGenerated extends QuizGenerationEvent {
  final Question question;
  final int index; // 1-based
  final int total;
  QuizQuestionGenerated(this.question, this.index, this.total);
}

// Planning phase
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

// Submission
class QuizSubmitted extends QuizGenerationEvent {
  QuizSubmitted();
}

class QuizGenerationComplete extends QuizGenerationEvent {
  final List<Question> questions;
  QuizGenerationComplete(this.questions);
}

class QuizGenerationError extends QuizGenerationEvent {
  final String message;
  QuizGenerationError(this.message);
}

// Question extraction phase
class QuizExtractionStarted extends QuizGenerationEvent {
  QuizExtractionStarted();
}

class QuizExtractionComplete extends QuizGenerationEvent {
  final String extractedQuestions;
  QuizExtractionComplete(this.extractedQuestions);
}

class QuizExtractionEmpty extends QuizGenerationEvent {
  QuizExtractionEmpty();
}

class QuizReviewComplete extends QuizGenerationEvent {
  final String reviewText;
  QuizReviewComplete(this.reviewText);
}
