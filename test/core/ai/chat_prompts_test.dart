import 'package:flutter_test/flutter_test.dart';
import 'package:quex/core/ai/chat_prompts.dart';

void main() {
  group('ChatPrompts tutor system instruction', () {
    test('English prompt stays compact and answer-focused', () {
      final prompt = ChatPrompts.getTutorSystemInstruction('en');

      expect(prompt, contains('--- QUIZ QUESTION ---'));
      expect(prompt, contains('default 1-3 short sentences'));
      expect(prompt, contains('Direct answer request: give the answer first'));
      expect(prompt, contains('scoring is handled by the app UI'));
      expect(prompt, isNot(contains('evaluate_understanding')));
    });

    test('Indonesian prompt stays compact and answer-focused', () {
      final prompt = ChatPrompts.getTutorSystemInstruction('id');

      expect(prompt, contains('--- QUIZ QUESTION ---'));
      expect(prompt, contains('default 1-3 kalimat pendek'));
      expect(prompt, contains('beri jawaban dulu'));
      expect(prompt, contains('Penilaian pilihan ganda ditangani oleh UI'));
      expect(prompt, isNot(contains('evaluate_understanding')));
    });
  });
}
