import 'package:flutter_test/flutter_test.dart';
import 'package:quex/core/ai/question_chat_service.dart';

void main() {
  group('QuestionChatService turn fence', () {
    late QuestionChatService service;

    setUp(() {
      service = QuestionChatService();
      service.endQuestionTurn();
    });

    tearDown(() {
      service.endQuestionTurn();
    });

    test('waitForQuestionTurnToEnd completes after endQuestionTurn', () async {
      service.beginQuestionTurn();

      var completed = false;
      final waiter = service.waitForQuestionTurnToEnd().then((_) {
        completed = true;
      });

      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);

      service.endQuestionTurn();
      await waiter;

      expect(completed, isTrue);
    });

    test('endQuestionTurn is idempotent when no turn is active', () async {
      service.endQuestionTurn();

      await expectLater(service.waitForQuestionTurnToEnd(), completes);
    });

    test('cancelQuestionTurn marks the active turn without ending it',
        () async {
      final turnId = service.beginQuestionTurn();

      service.cancelQuestionTurn(turnId);

      expect(service.isQuestionTurnCancelled(turnId), isTrue);
      expect(service.isQuestionTurnActive(turnId), isTrue);

      var completed = false;
      final waiter = service.waitForQuestionTurnToEnd().then((_) {
        completed = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);

      service.endQuestionTurn(turnId);
      await waiter;
      expect(completed, isTrue);
    });
  });
}
