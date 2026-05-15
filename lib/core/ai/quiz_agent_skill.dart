/// Runtime quiz-agent skill for the in-app Gemma workflow.
///
/// This is not a Codex skill file. It is the app-side skill contract used to
/// steer the local model through extraction, generation, review, and repair.
class QuizAgentSkill {
  const QuizAgentSkill._();

  static List<String> workflowSteps(String locale) {
    switch (locale) {
      case 'id':
        return const [
          'Ekstrak pertanyaan dari materi',
          'Buat draf pertanyaan dengan metadata jawaban',
          'Tinjau kualitas kuis',
          'Buat/perbaiki pertanyaan pengganti',
        ];
      default:
        return const [
          'Extract questions from materials',
          'Generate question drafts with answer metadata',
          'Review quiz quality',
          'Generate or repair replacement questions',
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
        return '''PERAN: Buat draf kuis dari materi pelajaran dan pertanyaan yang sudah ada.

TUGAS:
1. Gunakan pertanyaan dari <context> sebagai prioritas utama.
2. Jika jumlah pertanyaan kurang dari target, buat pertanyaan BARU dari materi.
3. Pastikan pertanyaan mencakup materi secara seimbang.
4. Gunakan bahasa netral dan jelas.
5. Setiap pertanyaan harus dapat dijawab dari materi dan memiliki tepat satu jawaban benar jika berupa pilihan ganda.

FORMAT OUTPUT (KETAT):
Gunakan format blok berikut untuk setiap item. Jangan gunakan markdown bebas.

[QUESTION]
Pertanyaan yang ditampilkan ke siswa.
[OPTIONS]
A. Pilihan pertama
B. Pilihan kedua
[CORRECT]
B
[EXPLANATION]
Mengapa jawaban benar.
[EVIDENCE]
Dukungan singkat dari materi.
[END]

ATURAN:
- Gunakan bahasa yang sama dengan materi pelajaran.
- Jangan tampilkan kunci jawaban di bagian [QUESTION] atau [OPTIONS].
- [CORRECT], [EXPLANATION], dan [EVIDENCE] adalah metadata internal untuk pemeriksaan kualitas.
- Tolak secara diam-diam ide pertanyaan yang tidak didukung materi, ambigu, atau memiliki lebih dari satu jawaban benar.''';
      default:
        return '''ROLE: Generate quiz drafts from study materials and existing questions.

TASK:
1. Use questions from <context> as top priority.
2. If the question count is below target, generate NEW questions from the material.
3. Ensure questions cover the material in a balanced way.
4. Use neutral and clear language.
5. Every question must be answerable from the material and must have exactly one correct answer if it is multiple choice.

FORMAT OUTPUT (STRICT):
Use the following block format for every item. Do not use free-form markdown.

[QUESTION]
Question shown to the student.
[OPTIONS]
A. First option
B. Second option
[CORRECT]
B
[EXPLANATION]
Why the answer is correct.
[EVIDENCE]
Short support from the study material.
[END]

RULES:
- Use the same language as the study materials.
- Do not reveal the answer in [QUESTION] or [OPTIONS].
- [CORRECT], [EXPLANATION], and [EVIDENCE] are internal quality metadata.
- Silently reject question ideas that are unsupported by the material, ambiguous, or have more than one correct answer.''';
    }
  }

  static String reviewInstruction(String locale) {
    switch (locale) {
      case 'id':
        return '''PERAN: Peninjau kualitas kuis.

TUGAS:
Tinjau draf kuis. Kembalikan hanya item yang valid atau item yang sudah diperbaiki dalam format blok yang sama.

KRITERIA:
- Jawaban harus didukung materi.
- Pilihan ganda harus memiliki tepat satu jawaban benar.
- Distraktor harus masuk akal tetapi salah.
- Pertanyaan tidak boleh membocorkan jawaban.
- Jangan sertakan kunci jawaban di [QUESTION] atau [OPTIONS].
- [EXPLANATION] dan [EVIDENCE] wajib ada.

Jika item tidak dapat diperbaiki dengan aman dari materi, hilangkan item tersebut.''';
      default:
        return '''ROLE: Quiz quality reviewer.

TASK:
Review quiz drafts. Return only valid items or safely fixed items in the same block format.

CRITERIA:
- The answer must be supported by the material.
- Multiple-choice questions must have exactly one correct answer.
- Distractors must be plausible but wrong.
- The question must not leak the answer.
- Do not include answer keys in [QUESTION] or [OPTIONS].
- [EXPLANATION] and [EVIDENCE] are required.

If an item cannot be safely fixed from the material, omit it.''';
    }
  }

  static String generationPrompt({
    required String sessionTitle,
    required int targetCount,
    required String extractedQuestions,
    required String textContext,
    String? reviewFeedback,
  }) {
    final feedbackBlock =
        reviewFeedback == null || reviewFeedback.trim().isEmpty
            ? ''
            : '''

Avoid these previous quality failures:
$reviewFeedback''';

    return '''Generate exactly $targetCount quiz draft items for "$sessionTitle".

If <context> has enough questions, use a balanced subset. If it has fewer, use all good questions and generate the rest from Study Materials.$feedbackBlock

<context>
$extractedQuestions
</context>

Study Materials:
$textContext''';
  }

  static String reviewPrompt({
    required String textContext,
    required String draftText,
    required int targetCount,
  }) {
    return '''Review these quiz drafts and return up to $targetCount validated or fixed items.

Study Materials:
$textContext

Draft Items:
$draftText''';
  }
}
