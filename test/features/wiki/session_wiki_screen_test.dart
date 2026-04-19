import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quex/core/ai/gemma_service_manager.dart';
import 'package:quex/core/ai/quex_ai.dart';
import 'package:quex/core/models/models.dart';
import 'package:quex/core/state/app_state.dart';
import 'package:quex/core/state/wiki_state.dart';
import 'package:quex/features/wiki/session_wiki_screen.dart';

import '../../support/fake_gemma_inference_service.dart';

void main() {
  testWidgets('releases Gemma when wiki screen pops', (tester) async {
    final created = <FakeGemmaInferenceService>[];
    final manager = GemmaServiceManager(serviceFactory: () {
      final service = FakeGemmaInferenceService();
      created.add(service);
      return service;
    });

    QuexAi.setGemmaServiceManager(manager);
    addTearDown(QuexAi.resetGemmaServiceManager);

    final session = Session(
      id: 1,
      profileId: 1,
      title: 'Rainforest',
      emoji: '🌿',
      gradeOverride: 3,
      createdAt: DateTime(2026, 4, 19),
    );

    final bundle = SessionBundle(
      session: session,
      materials: const [],
      quizzes: const [],
      messages: const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ProviderScope(
                        overrides: [
                          sessionBundleProvider(1)
                              .overrideWith((ref) async => bundle),
                          wikiTreeProvider(1)
                              .overrideWith((ref) async => const []),
                        ],
                        child: const SessionWikiScreen(sessionId: 1),
                      ),
                    ),
                  );
                },
                child: const Text('Open wiki'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open wiki'));
    await tester.pumpAndSettle();

    expect(created, hasLength(1));
    expect(created.single.initializeCalls, 1);
    expect(created.single.disposeCalls, 0);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(created.single.disposeCalls, 1);
  });
}
