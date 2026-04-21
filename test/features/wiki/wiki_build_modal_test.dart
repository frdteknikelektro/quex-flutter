import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:quex/features/wiki/wiki_build_modal.dart';

import '../../support/fake_gemma_inference_service.dart';

void main() {
  testWidgets('wiki build modal owns and disposes its Gemma service',
      (tester) async {
    final service = FakeGemmaInferenceService();

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: TextButton(
                  onPressed: () {
                    showDialog<void>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => WikiBuildModal(
                        sessionId: 1,
                        gemmaServiceFactory: () => service,
                        buildRunner: (_) async {},
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(service.initializeCalls, 1);
    expect(service.disposeCalls, 0);
    expect(service.isInitialized, isTrue);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(service.disposeCalls, 1);
    expect(service.closeSessionCalls, 1);
  });
}
