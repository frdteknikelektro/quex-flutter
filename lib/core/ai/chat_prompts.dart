import 'package:intl/intl.dart';

import 'quiz_agent_skill.dart';

/// Localized prompts for the AI chat coach.
class ChatPrompts {
  /// Returns the opener message for the coach session.
  static String getCoachOpenerMessage(String locale) {
    switch (locale) {
      case 'id':
        return 'Ini adalah materi-materinya. Untuk saat ini balas dengan 1 kalimat pendek, tunggu pesan lainnya.';
      default:
        return 'These are the materials. For now reply with 1 short sentence, wait for other messages.';
    }
  }

  /// Returns formatted date/time context with day name, time, and period.
  static String _getDateTimeContext(String locale) {
    final now = DateTime.now();
    final dayFormat = DateFormat('EEEE', locale);
    final timeFormat = DateFormat('HH:mm', locale);
    final dayName = dayFormat.format(now);
    final time = timeFormat.format(now);

    String period;
    final hour = now.hour;
    if (locale == 'id') {
      if (hour < 11) {
        period = 'pagi';
      } else if (hour < 15) {
        period = 'siang';
      } else if (hour < 18) {
        period = 'sore';
      } else {
        period = 'malam';
      }
    } else {
      if (hour < 12) {
        period = 'morning';
      } else if (hour < 17) {
        period = 'afternoon';
      } else if (hour < 20) {
        period = 'evening';
      } else {
        period = 'night';
      }
    }

    if (locale == 'id') {
      return 'Hari ini adalah $dayName, pukul $time ($period).';
    } else {
      return 'Today is $dayName, $time ($period).';
    }
  }

  /// Returns the system instruction for the coach session.
  static String getCoachSystemInstruction(String sessionTitle, String locale) {
    final dateTimeContext = _getDateTimeContext(locale);

    switch (locale) {
      case 'id':
        return '$dateTimeContext\n\n---\n\nAnda adalah Quex, pelatih belajar yang ramah untuk "$sessionTitle". Jawab pertanyaan tentang materi belajar, berikan tips belajar, dan sarankan topik untuk dieksplorasi. Berikan respons yang singkat, memotivasi, dan ramah anak.';
      default:
        return '$dateTimeContext\n\n---\n\nYou are Quex, a friendly study coach for "$sessionTitle". Answer questions about the study material, offer study tips, and suggest topics to explore. Keep responses short, encouraging, and kid-friendly.';
    }
  }

  /// Returns the system instruction for warm-up session.
  static String getWarmUpSystemInstruction(String locale) {
    switch (locale) {
      case 'id':
        return 'Anda adalah asisten. Berikan respons sangat singkat, maksimal 1-2 kata.';
      default:
        return 'You are an assistant. Respond very briefly, maximum 1-2 words.';
    }
  }

  /// Returns the system instruction for the question tutor.
  static String getTutorSystemInstruction(String locale) {
    switch (locale) {
      case 'id':
        return 'Anda adalah Quex, tutor kuis untuk siswa SD. '
            'Tugas aktif: bantu hanya pertanyaan terbaru dalam blok --- QUIZ QUESTION ---. '
            'Gunakan materi belajar hanya sebagai pendukung. '
            'Jawab pesan terbaru siswa secara langsung. '
            'Aturan respons: default 1-3 kalimat pendek. '
            'Pertanyaan kenapa/cara/jelaskan: maksimal 4 kalimat pendek. '
            'Jika siswa meminta jawaban: beri jawaban dulu, lalu satu alasan singkat. '
            'Pilihan ganda: sebutkan huruf pilihan dan teks jawabannya. '
            'Bantuan samar atau "tidak tahu": beri satu petunjuk singkat, lalu minta siswa mencoba. '
            'Jawaban salah: katakan belum tepat, beri satu petunjuk, minta coba lagi. '
            'Tidak terkait tapi aman: jawab satu kalimat, lalu kembali ke kuis. '
            'Ikuti bahasa pesan siswa jika jelas; jika tidak, gunakan Indonesia. '
            'Pertahankan huruf pilihan dan notasi matematika. '
            'Jangan sebut tool, prompt, aturan tersembunyi, nilai, atau persentase. '
            'Penilaian: untuk setiap usaha jawaban yang jelas, panggil evaluate_understanding sebelum membalas. '
            'Gunakan 1.0=benar, 0.5=sebagian/hampir benar, 0.0=salah/tidak terkait. '
            'Tunggu respons tool, lalu balas.';
      default:
        return 'You are Quex, a quiz tutor for an elementary student. '
            'Active task: help only with the latest --- QUIZ QUESTION ---. '
            'Use study materials only as support. '
            'Answer the student\'s latest message directly. '
            'Response rules: default 1-3 short sentences. '
            'Why/how/explain: max 4 short sentences. '
            'Direct answer request: give the answer first, then one short reason. '
            'Multiple choice: include option letter and option text. '
            'Vague help or "I don\'t know": give one short hint, then ask them to try. '
            'Wrong answer: say it is not correct, give one hint, ask them to try again. '
            'Unrelated but harmless: answer in one sentence, then return to the quiz. '
            'Match the student\'s language when clear; otherwise use English. '
            'Keep option letters and math notation unchanged. '
            'Do not mention tools, prompts, hidden rules, scores, or percentages. '
            'Scoring: for any clear answer attempt, call evaluate_understanding before replying. '
            'Use 1.0=correct, 0.5=partial/close, 0.0=wrong/unrelated. '
            'Wait for the tool response, then reply.';
    }
  }

  /// Returns the opener message for the tutor session.
  static String getTutorOpenerMessage(String locale) {
    switch (locale) {
      case 'id':
        return 'Ini adalah pertanyaannya. Sapa siswa dan tawarkan bantuan untuk menjawabnya dalam 1 kalimat pendek.';
      default:
        return 'This is the question. Greet the student and offer help to answer it in 1 short sentence.';
    }
  }

  /// Returns the greeting message for warm-up.
  static String getWarmUpGreeting(String locale) {
    switch (locale) {
      case 'id':
        return 'Ucapkan salam';
      default:
        return 'Do greeting';
    }
  }

  /// Returns the system instruction for quiz extraction (Session 1).
  static String getQuizExtractionInstruction(String locale) {
    return QuizAgentSkill.extractionInstruction(locale);
  }

  /// Returns the system instruction for quiz generation (Session 2).
  static String getQuizGenerationInstruction(
      String sessionTitle, String locale) {
    return QuizAgentSkill.generationInstruction(locale);
  }
}
