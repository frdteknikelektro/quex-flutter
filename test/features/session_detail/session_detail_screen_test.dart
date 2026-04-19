import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quex/core/models/models.dart';
import 'package:quex/core/state/app_state.dart';
import 'package:quex/core/state/wiki_state.dart';
import 'package:quex/features/session_detail/session_detail_screen.dart';

void main() {
  testWidgets('shows Wiki between Study Materials and Chat with AI',
      (tester) async {
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
      ProviderScope(
        overrides: [
          sessionBundleProvider(1).overrideWith((ref) async => bundle),
          wikiHasContentProvider(1).overrideWith((ref) async => false),
        ],
        child: const MaterialApp(
          home: SessionDetailScreen(sessionId: 1),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final studyTop = tester.getTopLeft(find.text('Study Materials')).dy;
    final wikiTop = tester.getTopLeft(find.text('Wiki')).dy;
    final chatTop = tester.getTopLeft(find.text('Chat with AI')).dy;

    expect(studyTop, lessThan(wikiTop));
    expect(wikiTop, lessThan(chatTop));
  });
}
