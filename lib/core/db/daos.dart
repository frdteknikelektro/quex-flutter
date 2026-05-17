import 'package:sqflite/sqflite.dart';

import '../models/models.dart';
import 'database.dart';

class ProfileDAO {
  Future<Database> get _db => QuexDatabase.instance;

  Future<int> insert(Profile profile) async {
    return (await _db).insert('profiles', profile.toMap());
  }

  Future<List<Profile>> getAll() async {
    final rows = await (await _db).query('profiles', orderBy: 'created_at ASC');
    return rows.map(Profile.fromMap).toList();
  }

  Future<Profile?> getById(int id) async {
    final rows = await (await _db).query(
      'profiles',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    return Profile.fromMap(rows.first);
  }

  Future<void> update(Profile profile) async {
    await (await _db).update(
      'profiles',
      profile.toMap(),
      where: 'id = ?',
      whereArgs: [profile.id],
    );
  }

  Future<void> delete(int id) async {
    await (await _db).delete('profiles', where: 'id = ?', whereArgs: [id]);
  }

  /// Deletes profile and all associated data via FK CASCADE:
  /// - Sessions, Materials, Quizzes, Questions, Chat messages
  Future<void> deleteCascade(int id) async {
    await (await _db).delete('profiles', where: 'id = ?', whereArgs: [id]);
  }
}

class SessionDAO {
  Future<Database> get _db => QuexDatabase.instance;

  Future<int> insert(Session session) async {
    return (await _db).insert('sessions', session.toMap());
  }

  Future<List<Session>> getByProfile(int profileId) async {
    final rows = await (await _db).query(
      'sessions',
      where: 'profile_id = ?',
      whereArgs: [profileId],
      orderBy: 'created_at DESC',
    );
    return rows.map(Session.fromMap).toList();
  }

  Future<List<Session>> getRecent(int limit) async {
    final rows = await (await _db)
        .query('sessions', orderBy: 'created_at DESC', limit: limit);
    return rows.map(Session.fromMap).toList();
  }

  Future<Session?> getById(int id) async {
    final rows = await (await _db).query(
      'sessions',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    return Session.fromMap(rows.first);
  }

  Future<void> update(Session session) async {
    await (await _db).update(
      'sessions',
      session.toMap(),
      where: 'id = ?',
      whereArgs: [session.id],
    );
  }

  Future<void> delete(int id) async {
    await (await _db).delete('sessions', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> countByProfile(int profileId) async {
    final result = await (await _db).rawQuery(
      'SELECT COUNT(*) AS c FROM sessions WHERE profile_id = ?',
      [profileId],
    );
    return result.first['c'] as int;
  }

  Future<void> deleteAllByProfile(int profileId) async {
    await (await _db).delete(
      'sessions',
      where: 'profile_id = ?',
      whereArgs: [profileId],
    );
  }
}

class MaterialDAO {
  Future<Database> get _db => QuexDatabase.instance;

  Future<int> insert(StudyMaterial material) async {
    return (await _db).insert('materials', material.toMap());
  }

  Future<List<StudyMaterial>> getBySession(int sessionId) async {
    final rows = await (await _db).query(
      'materials',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'page_index ASC, id ASC',
    );
    return rows.map(StudyMaterial.fromMap).toList();
  }

  Future<int> countBySession(int sessionId) async {
    final result = await (await _db).rawQuery(
      'SELECT COUNT(*) AS c FROM materials WHERE session_id = ?',
      [sessionId],
    );
    return result.first['c'] as int;
  }

  Future<void> update(StudyMaterial material) async {
    await (await _db).update(
      'materials',
      material.toMap(),
      where: 'id = ?',
      whereArgs: [material.id],
    );
  }

  Future<void> delete(int id) async {
    await (await _db).delete('materials', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteBySession(int sessionId) async {
    await (await _db)
        .delete('materials', where: 'session_id = ?', whereArgs: [sessionId]);
  }
}

class QuizDAO {
  Future<Database> get _db => QuexDatabase.instance;

  Future<int> insert(Quiz quiz) async {
    return (await _db).insert('quizzes', quiz.toMap());
  }

  Future<List<Quiz>> getBySession(int sessionId) async {
    final rows = await (await _db).query(
      'quizzes',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'created_at DESC',
    );
    return rows.map(Quiz.fromMap).toList();
  }

  Future<Quiz?> getById(int id) async {
    final rows = await (await _db).query(
      'quizzes',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    return Quiz.fromMap(rows.first);
  }

  Future<void> updateQuestionCount(int quizId, int count) async {
    await (await _db).update(
      'quizzes',
      {'question_count': count},
      where: 'id = ?',
      whereArgs: [quizId],
    );
  }

  Future<void> complete(int quizId, int score) async {
    await (await _db).update(
      'quizzes',
      {
        'score': score,
        'completed_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [quizId],
    );
  }

  Future<void> delete(int id) async {
    await (await _db).delete('quizzes', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteCompletedByProfile(int profileId) async {
    final db = await _db;
    await db.rawDelete('''
      DELETE FROM quizzes 
      WHERE completed_at IS NOT NULL 
      AND session_id IN (
        SELECT id FROM sessions WHERE profile_id = ?
      )
    ''', [profileId]);
  }
}

class QuestionDAO {
  Future<Database> get _db => QuexDatabase.instance;

  Future<int> insert(Question question) async {
    return (await _db).insert('questions', question.toMap());
  }

  Future<void> insertAll(List<Question> questions) async {
    final db = await _db;
    final batch = db.batch();
    for (final question in questions) {
      batch.insert('questions', question.toMap());
    }
    await batch.commit(noResult: true);
  }

  Future<List<Question>> getByQuiz(int quizId) async {
    final rows = await (await _db).query(
      'questions',
      where: 'quiz_id = ?',
      whereArgs: [quizId],
      orderBy: 'order_index ASC',
    );
    return rows.map(Question.fromMap).toList();
  }

  Future<void> saveAnswer(int questionId, String answer) async {
    await (await _db).update(
      'questions',
      {'user_answer': answer},
      where: 'id = ?',
      whereArgs: [questionId],
    );
  }

  Future<void> saveAnswerAndScore(
    int questionId, {
    required String answer,
    required double score,
  }) async {
    await (await _db).update(
      'questions',
      {
        'user_answer': answer,
        'score': score,
      },
      where: 'id = ?',
      whereArgs: [questionId],
    );
  }

  Future<Question?> getById(int id) async {
    final rows = await (await _db).query(
      'questions',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    return Question.fromMap(rows.first);
  }

  Future<void> saveScore(int questionId, double score) async {
    await (await _db).update(
      'questions',
      {'score': score},
      where: 'id = ?',
      whereArgs: [questionId],
    );
  }

  Future<void> deleteByQuiz(int quizId) async {
    await (await _db)
        .delete('questions', where: 'quiz_id = ?', whereArgs: [quizId]);
  }
}

class QuestionMessageDAO {
  Future<Database> get _db => QuexDatabase.instance;

  Future<int> insert(QuestionMessage message) async {
    return (await _db).insert('question_messages', message.toMap());
  }

  Future<List<QuestionMessage>> getByQuestion(int questionId) async {
    final rows = await (await _db).query(
      'question_messages',
      where: 'question_id = ?',
      whereArgs: [questionId],
      orderBy: 'created_at ASC',
    );
    return rows.map(QuestionMessage.fromMap).toList();
  }

  Future<void> deleteByQuestion(int questionId) async {
    await (await _db).delete(
      'question_messages',
      where: 'question_id = ?',
      whereArgs: [questionId],
    );
  }
}

class ChatDAO {
  Future<Database> get _db => QuexDatabase.instance;

  Future<int> insert(ChatMessage message) async {
    return (await _db).insert('chat_messages', message.toMap());
  }

  Future<List<ChatMessage>> getBySession(int sessionId) async {
    final rows = await (await _db).query(
      'chat_messages',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'created_at ASC',
    );
    return rows.map(ChatMessage.fromMap).toList();
  }

  Future<void> deleteBySession(int sessionId) async {
    await (await _db).delete('chat_messages',
        where: 'session_id = ?', whereArgs: [sessionId]);
  }
}
