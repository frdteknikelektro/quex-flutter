import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quex/features/processing/emoji_memory_game.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const emojiPool = [
    '🍎',
    '🍌',
    '🍇',
    '🍉',
    '🍓',
    '🍒',
    '🍋',
    '🍊',
  ];

  Map<String, List<int>> _positions(List<String> deck) {
    final map = <String, List<int>>{};
    for (var i = 0; i < deck.length; i++) {
      map.putIfAbsent(deck[i], () => []).add(i);
    }
    return map;
  }

  test('buildEmojiMemoryDeck creates 12 cards across 6 pairs', () {
    final deck = buildEmojiMemoryDeck(
      pairCount: 6,
      emojiPool: emojiPool,
      seed: 17,
    );

    expect(deck, hasLength(12));
    expect(deck.toSet(), hasLength(6));
    for (final emoji in deck.toSet()) {
      expect(deck.where((value) => value == emoji), hasLength(2));
    }
  });

  testWidgets('matches stay revealed and mismatches flip back', (tester) async {
    final deck = buildEmojiMemoryDeck(
      pairCount: 6,
      emojiPool: emojiPool,
      seed: 17,
    );
    final positions = _positions(deck);
    final matchEmoji = positions.entries.firstWhere(
      (entry) => entry.value.length == 2,
    );
    final mismatchPair = positions.entries
        .where((entry) => entry.key != matchEmoji.key)
        .take(2)
        .toList();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmojiMemoryGame(
            pairCount: 6,
            emojiPool: emojiPool,
            seed: 17,
            mismatchDelay: const Duration(milliseconds: 20),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (var i = 0; i < 12; i++) {
      expect(find.byKey(ValueKey('memory-card-$i')), findsOneWidget);
    }

    final matchIndices = matchEmoji.value;
    await tester.tap(find.byKey(ValueKey('memory-card-${matchIndices[0]}')));
    await tester.pump();
    await tester.tap(find.byKey(ValueKey('memory-card-${matchIndices[1]}')));
    await tester.pumpAndSettle();
    expect(find.text(matchEmoji.key), findsNWidgets(2));

    final mismatchEmojiA = mismatchPair[0].key;
    final mismatchEmojiB = mismatchPair[1].key;
    await tester
        .tap(find.byKey(ValueKey('memory-card-${mismatchPair[0].value[0]}')));
    await tester.pump();
    await tester
        .tap(find.byKey(ValueKey('memory-card-${mismatchPair[1].value[0]}')));
    await tester.pumpAndSettle();
    expect(find.text(mismatchEmojiA), findsNothing);
    expect(find.text(mismatchEmojiB), findsNothing);
  });

  testWidgets('shows completion state and replay resets the board', (
    tester,
  ) async {
    final deck = buildEmojiMemoryDeck(
      pairCount: 6,
      emojiPool: emojiPool,
      seed: 29,
    );
    final positions = _positions(deck);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmojiMemoryGame(
            pairCount: 6,
            emojiPool: emojiPool,
            seed: 29,
            mismatchDelay: const Duration(milliseconds: 20),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final indices in positions.values) {
      await tester.tap(find.byKey(ValueKey('memory-card-${indices[0]}')));
      await tester.pump();
      await tester.tap(find.byKey(ValueKey('memory-card-${indices[1]}')));
      await tester.pumpAndSettle();
    }

    expect(find.text('All pairs matched'), findsOneWidget);
    expect(find.text('Replay'), findsOneWidget);

    await tester.tap(find.text('Replay'));
    await tester.pumpAndSettle();

    expect(find.text('All pairs matched'), findsNothing);
    for (var i = 0; i < 12; i++) {
      expect(find.byKey(ValueKey('memory-card-$i')), findsOneWidget);
    }
  });
}
