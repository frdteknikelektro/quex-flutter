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

FORMAT OUTPUT (KETAT):
Ekstrak semua pertanyaan kuis yang ditemukan dalam materi sebagai paragraf markdown sederhana.
Untuk setiap pertanyaan, sertakan teks pertanyaan dan pilihan apa pun jika ada.

Contoh format:
Apa ibu kota Prancis?
- London
- Paris
- Berlin
- Madrid

Berapa 2 + 2?
- 3
- 4
- 5
- 6

ATURAN:
- Ekstrak hanya pertanyaan kuis yang sebenarnya, bukan pernyataan umum.
- JANGAN sertakan semua pilihan jawaban jika ada.
- Gunakan format paragraf sederhana, bukan daftar.
- Pisahkan pertanyaan dengan baris baru.
- Jika tidak ada pertanyaan yang ditemukan, balas dengan string kosong.
- Pertahankan bahasa asli dari pertanyaan.''';
      default:
        return '''ROLE: Extract existing quiz questions from study materials.

OUTPUT FORMAT (STRICT):
Extract all quiz questions found in the materials as a simple markdown paragraph.
For each question, include the question text and any options if present.

Example format:
What is the capital of France?
- London
- Paris
- Berlin
- Madrid

What is 2 + 2?
- 3
- 4
- 5
- 6

RULES:
- Extract only actual quiz questions, not general statements
- DO NOT include all answer options if present
- Use simple paragraph format, not a list
- Separate questions with newlines
- If no questions are found, respond with an empty string
- Preserve the original language of the questions''';
    }
  }

  /// Returns the system instruction for quiz generation (Session 2).
  static String getQuizGenerationInstruction(String sessionTitle, String locale) {
    switch (locale) {
      case 'id':
        return '''PERAN: Buat kuis dari materi pelajaran dan pertanyaan yang sudah ada.

TUGAS:
1. Gunakan pertanyaan dari <context> sebagai prioritas utama. Jika <context> memiliki lebih dari target jumlah pertanyaan, pilih secara acak.
2. Jika <context> kosong atau jumlah pertanyaan kurang dari target, buat pertanyaan BARU dari materi hingga mencapai target.
3. Pastikan pertanyaan mencakup materi secara seimbang.
4. Gunakan bahasa netral dan jelas.

FORMAT OUTPUT (KETAT):
Setiap pertanyaan dipisahkan oleh tanda "---" di baris baru.
Sertakan teks pertanyaan dan pilihan jawaban (jika ada) menggunakan format markdown.

Contoh:
Apa ibu kota Prancis?
- London
- Paris
- Berlin
- Madrid
---
Siapa penemu lampu pijar?
- Thomas Edison
- Nikola Tesla
---

ATURAN:
- JANGAN gunakan angka/nomor.
- Gunakan bahasa yang sama dengan materi pelajaran.''';
      default:
        return '''ROLE: Generate a quiz from study materials and existing questions.

TASK:
1. Use questions from <context> as top priority. If <context> has more than the target count, randomly select a subset.
2. If <context> is empty or question count is below target, generate NEW questions from materials to reach the target count.
3. Ensure questions cover the material in a balanced way.
4. Use neutral and clear language.

FORMAT OUTPUT (STRICT):
Separate each question with "---" on a new line.
Include question text and options (if any) using markdown format.

Example:
What is the capital of France?
- London
- Paris
- Berlin
- Madrid
---
Who invented the light bulb?
- Thomas Edison
- Nikola Tesla
---

RULES:
- DO NOT use numbering.
- Use the same language as the study materials.''';
    }
  }
}
