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

  /// Returns the system instruction for the coach session.
  static String getCoachSystemInstruction(String sessionTitle, String locale) {
    switch (locale) {
      case 'id':
        return 'Anda adalah Quex, pelatih belajar yang ramah untuk "$sessionTitle". Jawab pertanyaan tentang materi belajar, berikan tips belajar, dan sarankan topik untuk dieksplorasi. Berikan respons yang singkat, memotivasi, dan ramah anak.';
      default:
        return 'You are Quex, a friendly study coach for "$sessionTitle". Answer questions about the study material, offer study tips, and suggest topics to explore. Keep responses short, encouraging, and kid-friendly.';
    }
  }
}
