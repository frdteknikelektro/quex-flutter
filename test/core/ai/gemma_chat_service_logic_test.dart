import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gemma/flutter_gemma.dart' as gemma;
import 'package:quex/core/ai/gemma_chat_service.dart';

void main() {
  group('GemmaChatService Logic', () {
    late GemmaChatService service;

    setUp(() {
      service = GemmaChatService.getInstance();
    });

    test('should yield regular text tokens immediately', () async {
      final input = Stream.fromIterable([
        gemma.TextResponse('Hello '),
        gemma.TextResponse('world!'),
      ]);

      final output = await service.processResponseStream(input).toList();

      expect(output.length, 2);
      expect(output[0].text, 'Hello ');
      expect(output[1].text, 'world!');
    });

    test('should buffer and suppress JSON tool calls from text stream', () async {
      final input = Stream.fromIterable([
        gemma.TextResponse('Sure! '),
        gemma.TextResponse('{"name": '),
        gemma.TextResponse('"evaluate_understanding", '),
        gemma.TextResponse('"parameters": {"score": 1.0}}'),
        gemma.TextResponse(' Great job!'),
      ]);

      final output = await service.processResponseStream(input).toList();

      expect(output.any((e) => e.text != null && e.text!.contains('evaluate_understanding')), isFalse);
      expect(output[0].text, 'Sure! ');
      expect(output.last.text, ' Great job!');
    });

    test('should buffer and yield channel tags as thinking', () async {
      final input = Stream.fromIterable([
        gemma.TextResponse('Answer: '),
        gemma.TextResponse('<|channel>thought\nI should check the math.'),
        gemma.TextResponse(' It seems correct.<channel|>'),
        gemma.TextResponse(' Correct!'),
      ]);

      final output = await service.processResponseStream(input).toList();

      expect(output[0].text, 'Answer: ');
      expect(output[1].thinking, 'I should check the math.');
      expect(output[2].thinking, ' It seems correct.');
      expect(output[3].text, ' Correct!');
    });

    test('should handle tag embedded in text token', () async {
      final input = Stream.fromIterable([
        gemma.TextResponse('Start <|channel>thought\nReasoning<channel|> End'),
      ]);

      final output = await service.processResponseStream(input).toList();

      expect(output[0].text, 'Start ');
      expect(output[1].thinking, 'Reasoning');
      expect(output[2].text, ' End');
    });

    test('should flush buffer if stream ends without complete JSON', () async {
      final input = Stream.fromIterable([
        gemma.TextResponse('This looks like JSON: {"name": "incomplete"'),
      ]);

      final output = await service.processResponseStream(input).toList();

      expect(output.last.text, 'This looks like JSON: {"name": "incomplete"');
    });

    test('should handle ThinkingResponse correctly', () async {
      final input = Stream.fromIterable([
        gemma.ThinkingResponse('Thinking...'),
        gemma.TextResponse('Final answer'),
      ]);

      final output = await service.processResponseStream(input).toList();

      expect(output[0].thinking, 'Thinking...');
      expect(output[1].text, 'Final answer');
    });

    test('should deduplicate tool calls if library also yields them', () async {
      final input = Stream.fromIterable([
        gemma.TextResponse('{"name": "test_tool", "parameters": {}}'),
        gemma.FunctionCallResponse(name: 'test_tool', args: {}),
      ]);

      final output = await service.processResponseStream(input).toList();

      expect(output.isEmpty, isTrue);
    });
  });
}
