import 'package:flutter_test/flutter_test.dart';
import 'package:quex/core/models/models.dart';
import 'package:quex/features/quiz/question_chat_screen.dart';

void main() {
  const question = Question(
    id: 700,
    quizId: 200,
    source: QuestionSource.generated,
    type: QuestionType.multipleChoice,
    questionText: 'Which option is correct?',
    options: ['Alpha', 'Beta', 'Gamma', 'Delta'],
    correctAnswer: 'B',
    orderIndex: 0,
  );

  group('question answer selection helpers', () {
    test('scores multiple-choice answers deterministically', () {
      expect(scoreQuestionOptionSelection(question, 1), 1.0);
      expect(scoreQuestionOptionSelection(question, 0), 0.0);
    });

    test('does not score questions without a correct answer', () {
      final unscoredQuestion = question.copyWith(correctAnswer: '');

      expect(scoreQuestionOptionSelection(unscoredQuestion, 1), isNull);
    });

    test('normalizes stored answer labels', () {
      expect(normalizeQuestionOptionLetter('b'), 'B');
      expect(normalizeQuestionOptionLetter('B) Beta'), 'B');
      expect(normalizeQuestionOptionLetter(null), isNull);
    });

    test('builds hidden explanation prompts without chat display content', () {
      expect(
        buildAnswerExplanationPrompt(
          selectedAnswer: 'c',
          isCorrect: true,
          correctAnswer: 'C',
        ),
        'User menjawab: C, dan jawabannya benar. Tolong bantu jelaskan',
      );
      expect(
        buildAnswerExplanationPrompt(
          selectedAnswer: 'A',
          isCorrect: false,
          correctAnswer: 'B',
        ),
        'User menjawab: A, dan jawabannya salah. '
        'Jawaban yang benar adalah B. Tolong bantu jelaskan',
      );
    });

    test('reveals both wrong selection and correct option', () {
      final wrongSelection = questionAnswerOptionFeedback(
        letter: 'A',
        selectedAnswer: 'A',
        correctAnswer: 'B',
      );
      final correctOption = questionAnswerOptionFeedback(
        letter: 'B',
        selectedAnswer: 'A',
        correctAnswer: 'B',
      );

      expect(wrongSelection.isSelected, isTrue);
      expect(wrongSelection.isIncorrect, isTrue);
      expect(wrongSelection.isCorrect, isFalse);

      expect(correctOption.isSelected, isFalse);
      expect(correctOption.isIncorrect, isFalse);
      expect(correctOption.isCorrect, isTrue);
    });
  });
}
