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
        return 'Anda adalah tutor ramah yang membantu siswa SD menjawab pertanyaan kuis. '
            'Berikan respons yang singkat dan sederhana. Berikan petunjuk dan penyemangat. '
            'Ketika siswa menjawab dengan benar, panggil evaluate_understanding terlebih dahulu untuk memberi nilai. '
            'Setelah memanggil alat tersebut, selalu tunggu respons alat sebelum mengirim balasan teks Anda. '
            'Setelah menerima respons alat, ucapkan selamat kepada siswa (misalnya, "Bagus sekali!", "Benar!", "Mantap!").';
      default:
        return 'You are a friendly tutor helping an elementary student answer a quiz question. '
            'Keep responses short and simple. Give hints and encouragement. '
            'When the student answers correctly, first call evaluate_understanding to score it. '
            'After calling the tool, always wait for the tool response before sending your text reply. '
            'After receiving the tool response, congratulate the student (e.g., "Great job!", "Correct!", "Well done!").';
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
