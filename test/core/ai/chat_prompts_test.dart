import 'package:flutter_test/flutter_test.dart';
import 'package:quex/core/ai/chat_prompts.dart';

void main() {
  group('ChatPrompts tutor system instruction', () {
    test('English prompt asks for explanation-first answers', () {
      final prompt = ChatPrompts.getTutorSystemInstruction('en');

      expect(prompt, contains('give a short explanation first'));
      expect(prompt, contains('--- QUIZ QUESTION ---'));
      expect(prompt, contains('ambiguous or could refer to more than one thing'));
      expect(prompt, contains('answer related follow-up conversation naturally'));
    });

    test('Indonesian prompt asks for explanation-first answers', () {
      final prompt = ChatPrompts.getTutorSystemInstruction('id');

      expect(prompt, contains('penjelasan singkat terlebih dahulu'));
      expect(prompt, contains('--- QUIZ QUESTION ---'));
      expect(prompt, contains('pesan siswa ambigu'));
      expect(prompt, contains('percakapan lanjutan yang masih terkait secara natural'));
    });
  });
}
