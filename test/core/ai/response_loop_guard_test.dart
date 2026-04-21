import 'package:flutter_test/flutter_test.dart';

import 'package:quex/core/ai/response_loop_guard.dart';

void main() {
  test('detects repeated text sequences', () {
    final guard = ResponseLoopGuard();
    final pattern = <String>[
      'complete',
      '_',
      'step',
      '",',
    ];

    String? error;
    for (var i = 0; i < 4; i++) {
      for (final token in pattern) {
        error = guard.recordTextToken(token);
        if (error != null) break;
      }
      if (error != null) break;
    }

    expect(error, isNotNull);
    expect(error, contains('repeated text sequence'));
  });

  test('treats repeated tool-call text more aggressively', () {
    final guard = ResponseLoopGuard();
    final pattern = <String>[
      'complete',
      '_',
      'step',
      '",',
    ];

    String? error;
    for (var i = 0; i < 3; i++) {
      for (final token in pattern) {
        error = guard.recordTextToken(token, suspicious: true);
        if (error != null) break;
      }
      if (error != null) break;
    }

    expect(error, isNotNull);
    expect(error, contains('likely tool-call text sequence'));
  });
}
