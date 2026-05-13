import 'package:intl/intl.dart';

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
    switch (locale) {
      case 'id':
        return '''PERAN: Ekstrak pertanyaan kuis yang ada dari materi pelajaran.

TUGAS:
1. Cari pertanyaan kuis, latihan, atau evaluasi dalam teks/gambar.
2. PERKUAT konteks: Jika pertanyaan bergantung pada gambar, diagram, atau paragraf tertentu, tulis ulang pertanyaan agar menyertakan konteks tersebut. 
   Contoh: "Berapa hasilnya?" -> "Berdasarkan diagram siklus air, berapa hasil dari...?"
3. JANGAN menyertakan pilihan jawaban jika ada. Fokus pada teks pertanyaan.

FORMAT OUTPUT (KETAT):
Gunakan penanda [Q] dan [/Q] untuk setiap pertanyaan.
Jika ada konteks tambahan yang diperlukan, letakkan di antara [CONTEXT] dan [/CONTEXT] sebelum [Q].

Contoh:
[CONTEXT] Dalam ekosistem hutan... [/CONTEXT] [Q] Apa peran produsen? [/Q]
[Q] Sebutkan 3 jenis batuan! [/Q]

ATURAN:
- Gunakan bahasa yang sama dengan materi.
- Jika tidak ada pertanyaan, biarkan kosong.
- JANGAN memberikan angka/nomor pertanyaan.''';
      default:
        return '''ROLE: Extract existing quiz questions from study materials.

TASK:
1. Find quiz questions, exercises, or evaluations in the text/images.
2. HARDEN context: If a question depends on a specific image, diagram, or paragraph, rewrite the question to include that context.
   Example: "What is the result?" -> "Based on the water cycle diagram, what is the result of...?"
3. DO NOT include answer options if present. Focus on the question text.

OUTPUT FORMAT (STRICT):
Use [Q] and [/Q] markers for each question.
If additional context is needed, place it between [CONTEXT] and [/CONTEXT] before [Q].

Example:
[CONTEXT] In a forest ecosystem... [/CONTEXT] [Q] What is the role of producers? [/Q]
[Q] Name 3 types of rocks! [/Q]

RULES:
- Use the same language as the materials.
- If no questions found, leave empty.
- DO NOT use numbering.''';
    }
  }

  /// Returns the system instruction for quiz generation (Session 2).
  static String getQuizGenerationInstruction(String sessionTitle, String locale) {
    switch (locale) {
      case 'id':
        return '''PERAN: Buat kuis dari materi pelajaran dan pertanyaan yang sudah ada.

TUGAS:
1. Gunakan pertanyaan dari <context> sebagai prioritas utama.
2. Jika <context> kosong atau jumlah pertanyaan kurang dari target, buat pertanyaan BARU dari materi.
3. Pastikan pertanyaan mencakup materi secara seimbang.
4. Gunakan bahasa netral dan jelas.

FORMAT OUTPUT (KETAT):
Gunakan penanda [Q] dan [/Q] untuk setiap pertanyaan.
Jika ada konteks tambahan, letakkan di antara [CONTEXT] dan [/CONTEXT] sebelum [Q].

Contoh:
[CONTEXT] Matahari adalah bintang... [/CONTEXT] [Q] Berapa jarak bumi ke matahari? [/Q]
[Q] Apa ibu kota Indonesia? [/Q]

ATURAN:
- JANGAN gunakan angka/nomor.
- Pisahkan setiap blok [CONTEXT][Q] dengan baris baru.
- Akhiri dengan kata "FINISHED" di baris terakhir.
- Gunakan bahasa yang sama dengan materi pelajaran.''';
      default:
        return '''ROLE: Generate a quiz from study materials and existing questions.

TASK:
1. Use questions from <context> as top priority.
2. If <context> is empty or question count is below target, generate NEW questions from materials.
3. Ensure questions cover the material in a balanced way.
4. Use neutral and clear language.

OUTPUT FORMAT (STRICT):
Use [Q] and [/Q] markers for each question.
If additional context is needed, place it between [CONTEXT] and [/CONTEXT] before [Q].

Example:
[CONTEXT] The sun is a star... [/CONTEXT] [Q] What is the distance from Earth to the Sun? [/Q]
[Q] What is the capital of France? [/Q]

RULES:
- DO NOT use numbering.
- Separate each [CONTEXT][Q] block with a newline.
- End with the word "FINISHED" on its own line.
- Use the same language as the study materials.''';
    }
  }
}
