import 'dart:math';

import 'package:flutter/material.dart';

const List<String> _defaultEmojiPool = [
  '🍎',
  '🍌',
  '🍇',
  '🍓',
  '🍒',
  '🍋',
  '🍊',
  '🍉',
  '🥝',
  '🍍',
  '⭐',
  '🌙',
  '🎈',
  '🚀',
  '🎯',
  '🧩',
  '📚',
  '🎨',
  '🪁',
  '🦋',
  '🌈',
  '🍭',
  '🧃',
  '⚽',
];

class EmojiMemoryGame extends StatefulWidget {
  final int pairCount;
  final List<String> emojiPool;
  final int? seed;
  final Duration mismatchDelay;
  final double maxWidth;

  const EmojiMemoryGame({
    super.key,
    this.pairCount = 6,
    this.emojiPool = _defaultEmojiPool,
    this.seed,
    this.mismatchDelay = const Duration(milliseconds: 650),
    this.maxWidth = 280,
  });

  @override
  State<EmojiMemoryGame> createState() => _EmojiMemoryGameState();
}

List<String> buildEmojiMemoryDeck({
  required int pairCount,
  required List<String> emojiPool,
  int? seed,
}) {
  assert(pairCount > 0);
  assert(emojiPool.length >= pairCount);

  final random = seed == null ? Random() : Random(seed);
  final pool = List<String>.from(emojiPool)..shuffle(random);
  final faces = pool.take(pairCount).toList(growable: false);
  final deck = <String>[...faces, ...faces];
  deck.shuffle(random);
  return deck;
}

class _EmojiMemoryGameState extends State<EmojiMemoryGame> {
  final List<_MemoryCard> _cards = [];
  int? _firstSelection;
  bool _isBusy = false;
  bool _isComplete = false;
  int _roundToken = 0;

  @override
  void initState() {
    super.initState();
    _resetRound();
  }

  void _resetRound() {
    _roundToken++;
    _cards
      ..clear()
      ..addAll(
        buildEmojiMemoryDeck(
          pairCount: widget.pairCount,
          emojiPool: widget.emojiPool,
          seed: widget.seed,
        ).map(_MemoryCard.new),
      );
    _firstSelection = null;
    _isBusy = false;
    _isComplete = false;
  }

  void _restartGame() {
    setState(_resetRound);
  }

  void _handleTap(int index) {
    if (_isBusy || _isComplete) return;
    final card = _cards[index];
    if (card.revealed || card.matched) return;

    setState(() {
      card.revealed = true;
    });

    final first = _firstSelection;
    if (first == null) {
      _firstSelection = index;
      return;
    }

    if (first == index) {
      return;
    }

    final firstCard = _cards[first];
    final secondCard = _cards[index];
    if (firstCard.emoji == secondCard.emoji) {
      setState(() {
        firstCard.matched = true;
        secondCard.matched = true;
        _firstSelection = null;
        _isComplete = _cards.every((card) => card.matched);
      });
      return;
    }

    final token = ++_roundToken;
    setState(() => _isBusy = true);
    Future<void>.delayed(widget.mismatchDelay, () {
      if (!mounted || token != _roundToken) return;
      setState(() {
        firstCard.revealed = false;
        secondCard.revealed = false;
        _firstSelection = null;
        _isBusy = false;
      });
    });
  }

  String _statusLabel(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    final matchedPairs = _cards.where((card) => card.matched).length ~/ 2;
    if (locale == 'id') {
      return '$matchedPairs dari ${widget.pairCount} pasangan cocok';
    }
    return '$matchedPairs / ${widget.pairCount} matched';
  }

  String _completionTitle(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    return locale == 'id' ? 'Semua pasangan cocok' : 'All pairs matched';
  }

  String _completionBody(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    return locale == 'id'
        ? 'Main lagi untuk mengacak papan baru.'
        : 'Replay to shuffle a new board.';
  }

  String _replayLabel(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    return locale == 'id' ? 'Main lagi' : 'Replay';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context).textTheme;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: widget.maxWidth),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 240),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: _isComplete
              ? _CompletionPanel(
                  key: const ValueKey('memory-complete'),
                  title: _completionTitle(context),
                  body: _completionBody(context),
                  replayLabel: _replayLabel(context),
                  onReplay: _restartGame,
                )
              : Column(
                  key: const ValueKey('memory-board'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AspectRatio(
                      aspectRatio: 4 / 3,
                      child: GridView.builder(
                        physics: const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(8),
                        itemCount: _cards.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemBuilder: (context, index) {
                          final card = _cards[index];
                          return _MemoryCardTile(
                            key: ValueKey('memory-card-$index'),
                            emoji: card.emoji,
                            revealed: card.revealed,
                            matched: card.matched,
                            onTap: () => _handleTap(index),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _statusLabel(context),
                      style: theme.labelLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _MemoryCard {
  final String emoji;
  bool revealed;
  bool matched;

  _MemoryCard(this.emoji)
      : revealed = false,
        matched = false;
}

class _MemoryCardTile extends StatelessWidget {
  final String emoji;
  final bool revealed;
  final bool matched;
  final VoidCallback onTap;

  const _MemoryCardTile({
    super.key,
    required this.emoji,
    required this.revealed,
    required this.matched,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final faceUp = revealed || matched;
    final background =
        faceUp ? scheme.primaryContainer : scheme.surfaceContainerHighest;
    final borderColor = matched ? scheme.primary : scheme.outlineVariant;

    return Semantics(
      button: true,
      label: faceUp ? emoji : 'Hidden card',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: borderColor,
                width: matched ? 2 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: faceUp ? 0.08 : 0.04),
                  blurRadius: faceUp ? 8 : 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                switchInCurve: Curves.easeOutBack,
                switchOutCurve: Curves.easeIn,
                child: faceUp
                    ? Text(
                        emoji,
                        key: const ValueKey('memory-face-up'),
                        style: const TextStyle(fontSize: 30),
                      )
                    : Icon(
                        Icons.help_outline_rounded,
                        key: const ValueKey('memory-face-down'),
                        size: 22,
                        color: scheme.onSurfaceVariant,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CompletionPanel extends StatelessWidget {
  final String title;
  final String body;
  final String replayLabel;
  final VoidCallback onReplay;

  const _CompletionPanel({
    super.key,
    required this.title,
    required this.body,
    required this.replayLabel,
    required this.onReplay,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.emoji_events_rounded,
            size: 56,
            color: scheme.primary,
          ),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            textAlign: TextAlign.center,
            style: theme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          TextButton.icon(
            onPressed: onReplay,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(replayLabel),
          ),
        ],
      ),
    );
  }
}
