import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/daos.dart';
import '../models/models.dart';

const activeProfileIdKey = 'active_profile_id';

final activeProfileProvider = StateProvider<int?>((ref) => null);

/// True once the user has selected a profile in this app session.
/// Resets to false every cold-start (not persisted).
final sessionProfileSetProvider = StateProvider<bool>((ref) => false);

final profilesProvider = FutureProvider<List<Profile>>((ref) async {
  return ProfileDAO().getAll();
});

final recentSessionsProvider = FutureProvider.family<List<Session>, int>(
  (ref, profileId) => SessionDAO().getByProfile(profileId),
);

final sessionProvider = FutureProvider.family<Session?, int>(
  (ref, sessionId) => SessionDAO().getById(sessionId),
);

final materialsProvider = FutureProvider.family<List<StudyMaterial>, int>(
  (ref, sessionId) => MaterialDAO().getBySession(sessionId),
);

final quizzesProvider = FutureProvider.family<List<Quiz>, int>(
  (ref, sessionId) => QuizDAO().getBySession(sessionId),
);

final questionsProvider = FutureProvider.family<List<Question>, int>(
  (ref, quizId) => QuestionDAO().getByQuiz(quizId),
);

final chatMessagesProvider = FutureProvider.family<List<ChatMessage>, int>(
  (ref, sessionId) => ChatDAO().getBySession(sessionId),
);

Future<int?> readActiveProfileId() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getInt(activeProfileIdKey);
}

Future<void> saveActiveProfileId(int profileId) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(activeProfileIdKey, profileId);
}

class SessionBundle {
  final Session session;
  final List<StudyMaterial> materials;
  final List<Quiz> quizzes;
  final List<ChatMessage> messages;

  const SessionBundle({
    required this.session,
    required this.materials,
    required this.quizzes,
    required this.messages,
  });
}

final sessionBundleProvider = FutureProvider.family<SessionBundle?, int>(
  (ref, sessionId) async {
    final session = await SessionDAO().getById(sessionId);
    if (session == null) return null;
    final materials = await MaterialDAO().getBySession(sessionId);
    final quizzes = await QuizDAO().getBySession(sessionId);
    final messages = await ChatDAO().getBySession(sessionId);
    return SessionBundle(
      session: session,
      materials: materials,
      quizzes: quizzes,
      messages: messages,
    );
  },
);

class QuizBundle {
  final Quiz quiz;
  final List<Question> questions;

  const QuizBundle({
    required this.quiz,
    required this.questions,
  });
}

final quizBundleProvider = FutureProvider.family<QuizBundle?, int>(
  (ref, quizId) async {
    final quiz = await QuizDAO().getById(quizId);
    if (quiz == null) return null;
    final questions = await QuestionDAO().getByQuiz(quizId);
    return QuizBundle(quiz: quiz, questions: questions);
  },
);
