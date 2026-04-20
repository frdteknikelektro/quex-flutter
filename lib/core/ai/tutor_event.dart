sealed class TutorEvent {
  const TutorEvent();
}

class TutorThinking extends TutorEvent {
  final String token;
  const TutorThinking(this.token);
}

class TutorReply extends TutorEvent {
  final String token;
  const TutorReply(this.token);
}

class TutorEvaluation extends TutorEvent {
  final double score;
  const TutorEvaluation({required this.score});
}
