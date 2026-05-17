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
