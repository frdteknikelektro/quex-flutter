import 'package:flutter_test/flutter_test.dart';
import 'package:quex/core/ai/tts_service.dart';

void main() {
  group('TtsService sanitizeForSpeech', () {
    test('strips emphasis, headings, lists, links, code, math, and emoji', () {
      const input = '''
# Welcome 🧠

> **Read** the _question_ carefully.

- [OpenAI](https://openai.com) says `hello`
1. ~~Don't~~ skip the image ![brain](brain.png)

| A | B |
|---|---|
| 1 | 2 |

Math: \$x^2\$ and \\(a+b\\) and \\[c+d\\]
''';

      final output = TtsService.sanitizeForSpeech(input);

      expect(
        output,
        'Welcome. Read the question carefully. OpenAI says hello. Don\'t skip the image brain. A B 1 2. Math: x^2 and a+b and c+d',
      );
    });

    test('collapses whitespace and strips stray markdown markers', () {
      const input = 'This  _is_   **fine**\n\nand   this is *too*';

      final output = TtsService.sanitizeForSpeech(input);

      expect(output, 'This is fine. and this is too');
    });

    test('removes raw urls and html tags', () {
      const input = 'Visit https://example.com <br> now';

      final output = TtsService.sanitizeForSpeech(input);

      expect(output, 'Visit now');
    });
  });
}
