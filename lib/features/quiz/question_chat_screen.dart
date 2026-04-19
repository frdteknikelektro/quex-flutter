import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_filex/open_filex.dart';

import '../../app/theme.dart';
import '../../core/ai/gemma_inference_service.dart';
import '../../core/ai/quex_ai.dart';
import '../../core/ai/tutor_event.dart';
import '../../core/db/daos.dart';
import '../../core/models/models.dart';
import '../../core/state/app_state.dart';

class QuestionChatScreen extends ConsumerStatefulWidget {
  final int sessionId;
  final int quizId;
  final int questionId;

  const QuestionChatScreen({
    super.key,
    required this.sessionId,
    required this.quizId,
    required this.questionId,
  });

  @override
  ConsumerState<QuestionChatScreen> createState() => _QuestionChatScreenState();
}

class _QuestionChatScreenState extends ConsumerState<QuestionChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final Object _gemmaOwnerToken = Object();
  bool _sending = false;
  String? _streamingContent; // reply tokens accumulating
  String?
      _thinkingContent; // thinking tokens accumulating (null = not thinking)
  bool _thinkingExpanded = false;
  StreamSubscription<TutorEvent>? _streamSub;
  Future<GemmaInferenceService>? _modelFuture;

  @override
  void initState() {
    super.initState();
    unawaited(_warmModel());
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    unawaited(QuexAi.releaseGemmaService(_gemmaOwnerToken));
    super.dispose();
  }

  Future<GemmaInferenceService> _ensureModel() {
    final current = QuexAi.gemmaService;
    if (current != null &&
        current.isInitialized &&
        QuexAi.isCurrentGemmaOwner(_gemmaOwnerToken)) {
      return Future.value(current);
    }

    final existingFuture = _modelFuture;
    if (existingFuture != null) return existingFuture;

    final future = _loadModel();
    _modelFuture = future;
    future.whenComplete(() {
      if (mounted) _modelFuture = null;
    });
    return future;
  }

  Future<GemmaInferenceService> _loadModel() async {
    return await QuexAi.acquireGemmaService(_gemmaOwnerToken);
  }

  Future<void> _warmModel() async {
    try {
      await _ensureModel();
    } catch (_) {
      // Send path will surface model load failure if needed.
    }
  }

  Future<void> _stopGeneration() async {
    await _streamSub?.cancel();
    _streamSub = null;
    if (mounted) {
      setState(() {
        _sending = false;
        _streamingContent = null;
        _thinkingContent = null;
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage(
      Question question, List<QuestionMessage> history) async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    late final GemmaInferenceService service;
    try {
      service = await _ensureModel();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not load model: $error'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    setState(() {
      _sending = true;
      _streamingContent = '';
      _thinkingContent = null;
      _thinkingExpanded = false;
    });
    _controller.clear();

    final materials =
        ref.read(materialsProvider(widget.sessionId)).valueOrNull ?? [];

    // Save user message
    await QuestionMessageDAO().insert(QuestionMessage(
      questionId: widget.questionId,
      role: QuestionMessageRole.user,
      content: text,
      createdAt: DateTime.now(),
    ));
    ref.invalidate(questionMessagesProvider(widget.questionId));
    _scrollToBottom();

    final accumulatedReply = StringBuffer();
    final accumulatedThinking = StringBuffer();

    try {
      final stream = service.getQuestionTutorReplyStreaming(
        question: question,
        materials: materials,
        history: history,
        userMessage: text,
      );

      await _streamSub?.cancel();
      final completer = Completer<void>();

      _streamSub = stream.listen(
        (event) {
          if (!mounted) return;
          if (event is TutorThinking) {
            accumulatedThinking.write(event.token);
            setState(() => _thinkingContent = accumulatedThinking.toString());
          } else if (event is TutorReply) {
            accumulatedReply.write(event.token);
            setState(() => _streamingContent = accumulatedReply.toString());
            _scrollToBottom();
          }
        },
        onDone: () => completer.complete(),
        onError: (e) => completer.completeError(e),
        cancelOnError: true,
      );

      await completer.future;

      final reply = accumulatedReply.toString();
      final thinking = accumulatedThinking.toString();
      if (mounted) {
        setState(() {
          _streamingContent = null;
          _sending = false;
          // Freeze thinking: keep content but mark as done (not null → collapsible pill remains)
          _thinkingContent = thinking.isEmpty ? null : thinking;
          _thinkingExpanded = false;
        });
      }

      // Save assistant reply
      await QuestionMessageDAO().insert(QuestionMessage(
        questionId: widget.questionId,
        role: QuestionMessageRole.assistant,
        content: reply,
        createdAt: DateTime.now(),
      ));
      ref.invalidate(questionMessagesProvider(widget.questionId));
      _scrollToBottom();

      // Evaluate score with updated history
      final updatedHistory = [
        ...history,
        QuestionMessage(
          questionId: question.id!,
          role: QuestionMessageRole.user,
          content: text,
          createdAt: DateTime.now(),
        ),
        QuestionMessage(
          questionId: question.id!,
          role: QuestionMessageRole.assistant,
          content: reply,
          createdAt: DateTime.now(),
        ),
      ];

      final score = await service.evaluateQuestionScore(
        question: question,
        materials: materials,
        history: updatedHistory,
      );

      if (score != null && mounted) {
        await QuestionDAO().saveScore(widget.questionId, score);
        ref.invalidate(questionProvider(widget.questionId));
        ref.invalidate(quizBundleProvider(widget.quizId));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _streamingContent = null;
          _thinkingContent = null;
          _sending = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Quex is thinking… try again in a moment.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final questionAsync = ref.watch(questionProvider(widget.questionId));
    final messagesAsync =
        ref.watch(questionMessagesProvider(widget.questionId));
    final materialsAsync = ref.watch(materialsProvider(widget.sessionId));

    return questionAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
      data: (question) {
        if (question == null) {
          return Scaffold(
            appBar: AppBar(leading: const BackButton()),
            body: const Center(child: Text('Question not found')),
          );
        }

        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.pop(),
            ),
            title: Text(
              'Question ${question.orderIndex + 1}',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          body: Column(
            children: [
              // Materials thumbnail strip
              materialsAsync.whenData((materials) {
                    if (materials.isEmpty) return const SizedBox.shrink();
                    return _MaterialsStrip(
                      materials: materials,
                      sessionId: widget.sessionId,
                      scheme: scheme,
                      theme: theme,
                    );
                  }).value ??
                  const SizedBox.shrink(),

              // Question card
              _QuestionCard(question: question, scheme: scheme, theme: theme),

              // Score badge (if scored)
              if (question.score != null)
                _ScoreBadgeRow(
                    score: question.score!, scheme: scheme, theme: theme),

              // Messages
              Expanded(
                child: messagesAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Error: $e')),
                  data: (messages) => (messages.isEmpty &&
                          _streamingContent == null &&
                          _thinkingContent == null)
                      ? _EmptyChat(scheme: scheme, theme: theme)
                      : _MessageList(
                          messages: messages,
                          streamingContent: _streamingContent,
                          thinkingContent: _thinkingContent,
                          thinkingExpanded: _thinkingExpanded,
                          onThinkingToggle: () => setState(
                              () => _thinkingExpanded = !_thinkingExpanded),
                          isSending: _sending,
                          scrollController: _scrollController,
                          scheme: scheme,
                          theme: theme,
                        ),
                ),
              ),

              // Input bar
              _InputBar(
                controller: _controller,
                sending: _sending,
                onSend: () => messagesAsync.whenData(
                  (messages) => _sendMessage(question, messages),
                ),
                onStop: _stopGeneration,
                scheme: scheme,
                theme: theme,
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Materials thumbnail strip ────────────────────────────────────────────────

class _MaterialsStrip extends StatelessWidget {
  final List<StudyMaterial> materials;
  final int sessionId;
  final ColorScheme scheme;
  final ThemeData theme;

  const _MaterialsStrip({
    required this.materials,
    required this.sessionId,
    required this.scheme,
    required this.theme,
  });

  static ({String emoji, Color color}) _kindMeta(
          MaterialKind kind, ColorScheme scheme) =>
      switch (kind) {
        MaterialKind.text => (emoji: '📝', color: scheme.primaryContainer),
        MaterialKind.document => (
            emoji: '📄',
            color: scheme.secondaryContainer
          ),
        MaterialKind.photo => (emoji: '🖼️', color: scheme.tertiaryContainer),
      };

  static const double _thumbSize = 54;

  Widget _buildThumbnail(StudyMaterial m, ColorScheme scheme) {
    if (m.kind == MaterialKind.photo && m.content.isNotEmpty) {
      final firstPath = m.content.split('\n').firstWhere(
            (p) => p.isNotEmpty,
            orElse: () => '',
          );
      if (firstPath.isNotEmpty) {
        return ClipRRect(
          borderRadius: Br.sm,
          child: Image.file(
            File(firstPath),
            width: _thumbSize,
            height: _thumbSize,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _emojiAvatar(m.kind, scheme),
          ),
        );
      }
    }
    return _emojiAvatar(m.kind, scheme);
  }

  Widget _emojiAvatar(MaterialKind kind, ColorScheme scheme) {
    final meta = _kindMeta(kind, scheme);
    return Container(
      width: _thumbSize,
      height: _thumbSize,
      decoration: BoxDecoration(color: meta.color, borderRadius: Br.sm),
      alignment: Alignment.center,
      child: Text(meta.emoji, style: const TextStyle(fontSize: 22)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 96,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        itemCount: materials.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final m = materials[index];
          return SizedBox(
            width: 64,
            child: InkWell(
              borderRadius: Br.sm,
              onTap: () async {
                if (m.kind == MaterialKind.document) {
                  final result = await OpenFilex.open(m.content);
                  if (result.type != ResultType.done && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text('Could not open: ${result.message}')),
                    );
                  }
                } else {
                  context.push('/session/$sessionId/material/${m.id}');
                }
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _buildThumbnail(m, scheme),
                  const SizedBox(height: 2),
                  Text(
                    m.title,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontSize: 10,
                      height: 1.1,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Score badge row ─────────────────────────────────────────────────────────

class _ScoreBadgeRow extends StatelessWidget {
  final double score;
  final ColorScheme scheme;
  final ThemeData theme;

  const _ScoreBadgeRow({
    required this.score,
    required this.scheme,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;
    final IconData icon;

    if (score >= 0.8) {
      color = const Color(0xFF4CAF50);
      label = 'Correct! 🎉';
      icon = Icons.check_circle;
    } else if (score >= 0.4) {
      color = const Color(0xFFFFB347);
      label = 'Partial credit — keep going!';
      icon = Icons.remove_circle;
    } else {
      color = const Color(0xFFFF6B6B);
      label = 'Not quite — let\'s keep discussing';
      icon = Icons.cancel;
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: Br.md,
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            '${(score * 100).round()}%',
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Question card ───────────────────────────────────────────────────────────

class _QuestionCard extends StatelessWidget {
  final Question question;
  final ColorScheme scheme;
  final ThemeData theme;

  const _QuestionCard({
    required this.question,
    required this.scheme,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: Br.lg,
        border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            question.questionText,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.onPrimaryContainer,
            ),
          ),
          if (question.type == QuestionType.multipleChoice &&
              question.options.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: question.options.asMap().entries.map((e) {
                final letter = String.fromCharCode(65 + e.key);
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: Br.full,
                    border: Border.all(
                        color: scheme.primary.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    '$letter. ${e.value}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Message list ─────────────────────────────────────────────────────────────

class _MessageList extends StatelessWidget {
  final List<QuestionMessage> messages;
  final String? streamingContent;
  final String? thinkingContent;
  final bool thinkingExpanded;
  final VoidCallback onThinkingToggle;
  final bool isSending;
  final ScrollController scrollController;
  final ColorScheme scheme;
  final ThemeData theme;

  const _MessageList({
    required this.messages,
    required this.streamingContent,
    required this.thinkingContent,
    required this.thinkingExpanded,
    required this.onThinkingToggle,
    required this.isSending,
    required this.scrollController,
    required this.scheme,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    // Extra slots: thinking bubble + reply bubble (when active)
    final hasThinking = thinkingContent != null;
    final hasStreaming = streamingContent != null;
    final extraItems = (hasThinking ? 1 : 0) + (hasStreaming ? 1 : 0);
    final totalItems = messages.length + extraItems;

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      itemCount: totalItems,
      itemBuilder: (context, index) {
        // Thinking bubble — appears before streaming reply
        if (hasThinking && index == messages.length) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _ThinkingBubble(
              content: thinkingContent!,
              expanded: thinkingExpanded,
              isStreaming: isSending && streamingContent != null
                  ? false // reply started — thinking done
                  : isSending, // still thinking if sending and no reply yet
              onToggle: onThinkingToggle,
              scheme: scheme,
              theme: theme,
            ),
          );
        }

        // Streaming reply bubble — after thinking
        final replyIndex = messages.length + (hasThinking ? 1 : 0);
        if (hasStreaming && index == replyIndex) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.78,
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                    bottomLeft: Radius.circular(4),
                    bottomRight: Radius.circular(18),
                  ),
                ),
                child: streamingContent!.isEmpty
                    ? _TypingIndicator(scheme: scheme)
                    : MarkdownBody(
                        data: streamingContent!,
                        styleSheet:
                            MarkdownStyleSheet.fromTheme(theme).copyWith(
                          p: theme.textTheme.bodyMedium
                              ?.copyWith(color: scheme.onSurface),
                        ),
                      ),
              ),
            ),
          );
        }

        final msg = messages[index];
        final isUser = msg.role == QuestionMessageRole.user;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Align(
            alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.78,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser
                    ? scheme.primaryContainer
                    : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 18),
                ),
              ),
              child: isUser
                  ? Text(
                      msg.content,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onPrimaryContainer,
                      ),
                    )
                  : MarkdownBody(
                      data: msg.content,
                      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                        p: theme.textTheme.bodyMedium
                            ?.copyWith(color: scheme.onSurface),
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }
}

// ─── Thinking bubble ──────────────────────────────────────────────────────────

class _ThinkingBubble extends StatelessWidget {
  final String content;
  final bool expanded;
  final bool isStreaming;
  final VoidCallback onToggle;
  final ColorScheme scheme;
  final ThemeData theme;

  const _ThinkingBubble({
    required this.content,
    required this.expanded,
    required this.isStreaming,
    required this.onToggle,
    required this.scheme,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final labelColor = scheme.onSurfaceVariant;
    final bgColor = scheme.surfaceContainerLow;
    final borderColor = scheme.outlineVariant;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.85,
        ),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: Br.md,
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header — always visible, tap to toggle
            InkWell(
              onTap: content.isEmpty ? null : onToggle,
              borderRadius: expanded
                  ? const BorderRadius.vertical(top: Radius.circular(16))
                  : Br.md,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isStreaming)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: _TypingIndicator(scheme: scheme),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Icon(Icons.psychology_outlined,
                            size: 14, color: labelColor),
                      ),
                    Text(
                      isStreaming ? 'Thinking…' : 'Thought process',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: labelColor,
                        fontWeight: FontWeight.w600,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    if (!isStreaming && content.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Icon(
                        expanded ? Icons.expand_less : Icons.expand_more,
                        size: 14,
                        color: labelColor,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // Expandable content
            if (expanded && content.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Text(
                  content,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                    height: 1.5,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Typing indicator ─────────────────────────────────────────────────────────

class _TypingIndicator extends StatefulWidget {
  final ColorScheme scheme;

  const _TypingIndicator({required this.scheme});

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        final offset = i / 3;
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = ((_controller.value + offset) % 1.0);
            final opacity = (t < 0.5 ? t * 2 : (1 - t) * 2).clamp(0.3, 1.0);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Opacity(
                opacity: opacity,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: widget.scheme.onSurfaceVariant,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          },
        );
      }),
    );
  }
}

// ─── Empty chat ───────────────────────────────────────────────────────────────

class _EmptyChat extends StatelessWidget {
  final ColorScheme scheme;
  final ThemeData theme;

  const _EmptyChat({required this.scheme, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline,
                size: 48, color: scheme.outlineVariant),
            const SizedBox(height: 16),
            Text(
              'Answer the question above',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Type your answer below and Quex will help you learn!',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Input bar ────────────────────────────────────────────────────────────────

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final ColorScheme scheme;
  final ThemeData theme;

  const _InputBar({
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.onStop,
    required this.scheme,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        10 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: !sending,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: 'Talk to Quex…',
                  hintStyle: TextStyle(color: scheme.onSurfaceVariant),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(color: scheme.outlineVariant),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(color: scheme.outlineVariant),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(color: scheme.primary, width: 1.5),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: sending
                  ? IconButton(
                      key: const ValueKey('stop'),
                      onPressed: onStop,
                      icon: Icon(Icons.stop_rounded,
                          color: scheme.onErrorContainer),
                      style: IconButton.styleFrom(
                        backgroundColor: scheme.errorContainer,
                        minimumSize: const Size(44, 44),
                      ),
                    )
                  : IconButton(
                      key: const ValueKey('send'),
                      onPressed: onSend,
                      icon: Icon(Icons.send_rounded, color: scheme.primary),
                      style: IconButton.styleFrom(
                        backgroundColor: scheme.primaryContainer,
                        minimumSize: const Size(44, 44),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
