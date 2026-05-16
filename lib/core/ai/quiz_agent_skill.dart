/// Runtime quiz-agent skill for the in-app Gemma workflow.
///
/// This is not a Codex skill file. It is the app-side skill contract used to
/// steer the local model through extraction, AI review, and generation.
class QuizAgentSkill {
  const QuizAgentSkill._();

  static List<String> workflowSteps(String locale) {
    switch (locale) {
      case 'id':
        return const [
          'Ekstrak pertanyaan dari materi',
          'Tinjau pertanyaan yang akan dibuat',
          'Buat kuis',
        ];
      default:
        return const [
          'Extract questions from materials',
          'Review questions to generate',
          'Generate quiz',
        ];
    }
  }

  static String extractionInstruction(String locale) {
    switch (locale) {
      case 'id':
        return '''PERAN: Ekstrak pertanyaan kuis yang ada dari materi pelajaran.

FORMAT OUTPUT (KETAT):
Ekstrak semua pertanyaan kuis yang ditemukan dalam materi sebagai paragraf markdown sederhana.
Untuk setiap pertanyaan, sertakan teks pertanyaan dan semua pilihan jawaban jika ada.
Jangan sertakan kunci jawaban, label jawaban benar, pembahasan, atau catatan guru.

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
- Sertakan semua pilihan jawaban/opsi persis seperti yang tertulis.
- JANGAN sertakan kunci jawaban, label jawaban benar, penanda solusi, pembahasan, atau catatan guru.
- Hapus baris seperti "Answer:", "Correct answer:", "Kunci jawaban:", "Jawaban:", "Pembahasan:", atau padanannya.
- Gunakan format paragraf sederhana, bukan daftar.
- Pisahkan pertanyaan dengan baris baru.
- Jika tidak ada pertanyaan yang ditemukan, balas dengan string kosong.
- Pertahankan bahasa asli dari pertanyaan.''';
      default:
        return '''ROLE: Extract existing quiz questions from study materials.

OUTPUT FORMAT (STRICT):
Extract all quiz questions found in the materials as a simple markdown paragraph.
For each question, include the question text and all answer choices if present.
Do not include answer keys, correct-answer labels, solution markers, explanations, or teacher notes.

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
- Include all answer choices/options exactly as shown
- Do NOT include answer keys, correct-answer labels, solution markers, explanations, or teacher notes
- Remove lines such as "Answer:", "Correct answer:", "Key answer:", "Kunci jawaban:", "Jawaban:", "Pembahasan:", or equivalent
- Use simple paragraph format, not a list
- Separate questions with newlines
- If no questions are found, respond with an empty string
- Preserve the original language of the questions''';
    }
  }

  static String generationInstruction(String locale) {
    switch (locale) {
      case 'id':
        return '''PERAN: Buat kuis pilihan ganda dari tinjauan AI dan materi.

TUGAS:
1. Ikuti <review> sebagai rencana utama.
2. Gunakan hanya pertanyaan yang ditandai USABLE/FIXABLE.
3. Buat pertanyaan baru untuk topik penting yang belum tercakup.
4. Setiap pertanyaan wajib didukung materi.
5. Buat tepat jumlah item yang diminta jika materi cukup.

FORMAT OUTPUT (KETAT):
Gunakan format blok berikut untuk setiap item. Jangan gunakan markdown bebas.

[QUESTION]
Pertanyaan yang ditampilkan ke siswa.
[OPTIONS]
A. Pilihan pertama
B. Pilihan kedua
C. Pilihan ketiga
D. Pilihan keempat
[CORRECT]
A
[END]

ATURAN:
- Hanya pilihan ganda.
- Setiap item wajib punya tepat 4 opsi: A, B, C, D.
- [CORRECT] wajib satu huruf A-D dan harus sesuai opsi benar.
- Gunakan bahasa yang sama dengan materi pelajaran.
- Jangan tampilkan kunci jawaban di bagian [QUESTION] atau [OPTIONS].
- Hindari "semua benar" atau "tidak ada yang benar".
- Tolak diam-diam ide yang tidak didukung materi, ambigu, atau punya lebih dari satu jawaban benar.''';
      default:
        return '''ROLE: Generate multiple-choice quiz items from AI review and materials.

TASK:
1. Follow <review> as the main plan.
2. Use only questions marked USABLE/FIXABLE.
3. Create new questions for important uncovered topics.
4. Every question must be supported by the material.
5. Generate exactly the requested item count if the material supports it.

FORMAT OUTPUT (STRICT):
Use the following block format for every item. Do not use free-form markdown.

[QUESTION]
Question shown to the student.
[OPTIONS]
A. First option
B. Second option
C. Third option
D. Fourth option
[CORRECT]
A
[END]

RULES:
- Multiple-choice only.
- Each item must have exactly 4 options: A, B, C, D.
- [CORRECT] is required, must be one letter A-D, and must match the correct option.
- Use the same language as the study materials.
- Do not reveal the answer in [QUESTION] or [OPTIONS].
- Avoid "all of the above" or "none of the above".
- Silently reject ideas that are unsupported, ambiguous, or have more than one correct answer.''';
    }
  }

  static String reviewInstruction(String locale) {
    switch (locale) {
      case 'id':
        return '''PERAN: Tinjau pertanyaan hasil ekstraksi dan analisis materi.

TUGAS:
1. Nilai pertanyaan hasil ekstraksi terhadap materi.
2. Tandai setiap pertanyaan sebagai USABLE, FIXABLE, atau SKIP.
3. Untuk FIXABLE, beri cara perbaikan singkat.
4. Analisis topik penting di materi yang belum tercakup.
5. Beri panduan untuk pembuatan kuis pilihan ganda 4 opsi.

FORMAT OUTPUT (KETAT):
[QUESTION_REVIEW]
- USABLE: ...
- FIXABLE: ... | Issue: ... | Fix: ...
- SKIP: ... | Issue: ...

[MATERIAL_ANALYSIS]
- Topik penting: ...
- Topik belum tercakup: ...

[GENERATION_GUIDANCE]
- Gunakan: ...
- Perbaiki: ...
- Buat baru: ...
- Hindari: ...

ATURAN:
- Jangan membuat item kuis final.
- Jangan tampilkan kunci jawaban.
- Jika tidak ada pertanyaan ekstraksi, tetap analisis materi dan beri panduan.''';
      default:
        return '''ROLE: Review extracted questions and analyze study materials.

TASK:
1. Judge extracted questions against the materials.
2. Mark each question as USABLE, FIXABLE, or SKIP.
3. For FIXABLE, give a short fix direction.
4. Identify important material topics not covered.
5. Give guidance for a 4-option multiple-choice quiz.

OUTPUT FORMAT (STRICT):
[QUESTION_REVIEW]
- USABLE: ...
- FIXABLE: ... | Issue: ... | Fix: ...
- SKIP: ... | Issue: ...

[MATERIAL_ANALYSIS]
- Important topics: ...
- Missing coverage: ...

[GENERATION_GUIDANCE]
- Use: ...
- Fix: ...
- Create new: ...
- Avoid: ...

RULES:
- Do not create final quiz items.
- Do not reveal answer keys.
- If no extracted questions exist, still analyze materials and give guidance.''';
    }
  }

  static String generationPrompt({
    required String sessionTitle,
    required int targetCount,
    required String reviewText,
    required String textContext,
  }) {
    return '''Generate exactly $targetCount quiz draft items for "$sessionTitle".

<review>
$reviewText
</review>

Study Materials:
$textContext''';
  }

  static String reviewPrompt({
    required String textContext,
    required String extractedQuestions,
  }) {
    final extracted = extractedQuestions.trim().isEmpty
        ? 'No extracted questions.'
        : extractedQuestions;
    return '''Review these extracted questions and the study materials.

Extracted Questions:
$extracted

Study Materials:
$textContext''';
  }
}
