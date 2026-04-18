import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class QuexDatabase {
  static Database? _db;
  static const String _dbName = 'quex.db';
  static const int _version = 4;

  static Future<Database> get instance async {
    if (_db != null) return _db!;
    _db = await _init();
    return _db!;
  }

  static Future<Database> _init() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);

    return openDatabase(
      path,
      version: _version,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        await db.rawQuery('PRAGMA journal_mode = WAL');
      },
    );
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE profiles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        emoji TEXT NOT NULL DEFAULT '🧒',
        grade INTEGER NOT NULL DEFAULT 3,
        default_question_count INTEGER NOT NULL DEFAULT 20,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        profile_id INTEGER NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
        title TEXT NOT NULL,
        emoji TEXT NOT NULL DEFAULT '📘',
        grade_override INTEGER NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE materials (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
        kind TEXT NOT NULL,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        page_index INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE quizzes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
        question_count INTEGER NOT NULL,
        score INTEGER,
        created_at INTEGER NOT NULL,
        completed_at INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE questions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        quiz_id INTEGER NOT NULL REFERENCES quizzes(id) ON DELETE CASCADE,
        source_type TEXT NOT NULL,
        type TEXT NOT NULL DEFAULT 'multipleChoice',
        question_text TEXT NOT NULL,
        options TEXT NOT NULL DEFAULT '[]',
        user_answer TEXT,
        order_index INTEGER NOT NULL DEFAULT 0,
        score REAL
      )
    ''');

    await db.execute('''
      CREATE TABLE question_messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        question_id INTEGER NOT NULL REFERENCES questions(id) ON DELETE CASCADE,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE chat_messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('CREATE INDEX idx_sessions_profile ON sessions(profile_id)');
    await db.execute('CREATE INDEX idx_sessions_created ON sessions(created_at DESC)');
    await db.execute('CREATE INDEX idx_materials_session ON materials(session_id, page_index)');
    await db.execute('CREATE INDEX idx_quizzes_session ON quizzes(session_id, created_at DESC)');
    await db.execute('CREATE INDEX idx_questions_quiz_order ON questions(quiz_id, order_index)');
    await db.execute('CREATE INDEX idx_question_messages_question ON question_messages(question_id, created_at)');
    await db.execute('CREATE INDEX idx_chat_session ON chat_messages(session_id, created_at)');

    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('profiles', {
      'name': 'Raina',
      'emoji': '👧',
      'grade': 3,
      'default_question_count': 20,
      'created_at': now,
    });
    await db.insert('profiles', {
      'name': 'Kindi',
      'emoji': '👦',
      'grade': 2,
      'default_question_count': 20,
      'created_at': now + 1,
    });
  }

  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE questions_v2 (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          quiz_id INTEGER NOT NULL REFERENCES quizzes(id) ON DELETE CASCADE,
          source_type TEXT NOT NULL,
          type TEXT NOT NULL DEFAULT 'multipleChoice',
          question_text TEXT NOT NULL,
          options TEXT NOT NULL DEFAULT '[]',
          correct_answer TEXT NOT NULL,
          explanation TEXT NOT NULL,
          user_answer TEXT,
          order_index INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await db.execute('''
        INSERT INTO questions_v2
          (id, quiz_id, source_type, type, question_text, options, correct_answer, explanation, user_answer, order_index)
        SELECT
          id, quiz_id, source_type, 'multipleChoice', question_text,
          json_array(option_a, option_b, option_c, option_d),
          correct_option, explanation, user_answer, order_index
        FROM questions
      ''');
      await db.execute('DROP TABLE questions');
      await db.execute('ALTER TABLE questions_v2 RENAME TO questions');
      await db.execute('CREATE INDEX idx_questions_quiz_order ON questions(quiz_id, order_index)');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE questions ADD COLUMN score REAL');
      await db.execute('''
        CREATE TABLE question_messages (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          question_id INTEGER NOT NULL REFERENCES questions(id) ON DELETE CASCADE,
          role TEXT NOT NULL,
          content TEXT NOT NULL,
          created_at INTEGER NOT NULL
        )
      ''');
      await db.execute('CREATE INDEX idx_question_messages_question ON question_messages(question_id, created_at)');
    }
    if (oldVersion < 4) {
      // Remove question_count from sessions
      await db.execute('''
        CREATE TABLE sessions_v4 (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          profile_id INTEGER NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
          title TEXT NOT NULL,
          emoji TEXT NOT NULL DEFAULT '📘',
          grade_override INTEGER NOT NULL,
          created_at INTEGER NOT NULL
        )
      ''');
      await db.execute('''
        INSERT INTO sessions_v4 (id, profile_id, title, emoji, grade_override, created_at)
        SELECT id, profile_id, title, emoji, grade_override, created_at FROM sessions
      ''');
      await db.execute('DROP TABLE sessions');
      await db.execute('ALTER TABLE sessions_v4 RENAME TO sessions');
      await db.execute('CREATE INDEX idx_sessions_profile ON sessions(profile_id)');
      await db.execute('CREATE INDEX idx_sessions_created ON sessions(created_at DESC)');

      // Remove correct_answer + explanation from questions
      await db.execute('''
        CREATE TABLE questions_v4 (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          quiz_id INTEGER NOT NULL REFERENCES quizzes(id) ON DELETE CASCADE,
          source_type TEXT NOT NULL,
          type TEXT NOT NULL DEFAULT 'multipleChoice',
          question_text TEXT NOT NULL,
          options TEXT NOT NULL DEFAULT '[]',
          user_answer TEXT,
          order_index INTEGER NOT NULL DEFAULT 0,
          score REAL
        )
      ''');
      await db.execute('''
        INSERT INTO questions_v4 (id, quiz_id, source_type, type, question_text, options, user_answer, order_index, score)
        SELECT id, quiz_id, source_type, type, question_text, options, user_answer, order_index, score FROM questions
      ''');
      await db.execute('DROP TABLE questions');
      await db.execute('ALTER TABLE questions_v4 RENAME TO questions');
      await db.execute('CREATE INDEX idx_questions_quiz_order ON questions(quiz_id, order_index)');
    }
  }

  static Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
