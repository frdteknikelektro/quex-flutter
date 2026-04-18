sealed class TutorEvent {}

class TutorThinking extends TutorEvent {
  final String token;
  TutorThinking(this.token);
}

class TutorReply extends TutorEvent {
  final String token;
  TutorReply(this.token);
}
