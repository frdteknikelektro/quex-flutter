import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/ai/quex_ai.dart';
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
  bool _sending = false;
  bool _materialsExpanded = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage(Question question, List<QuestionMessage> history) async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() => _sending = true);
    _controller.clear();

    final materials =
        ref.read(materialsProvider(widget.sessionId)).valueOrNull ?? [];

    await QuestionMessageDAO().insert(QuestionMessage(
      questionId: widget.questionId,
      role: QuestionMessageRole.user,
      content: text,
      createdAt: DateTime.now(),
    ));
    ref.invalidate(questionMessagesProvider(widget.questionId));

    try {
      final result = await QuexAi.questionCoachReply(
        question: question,
        materials: materials,
        history: history,
        userMessage: text,
      );

      await QuestionMessageDAO().insert(QuestionMessage(
        questionId: widget.questionId,
        role: QuestionMessageRole.assistant,
        content: result.reply,
        createdAt: DateTime.now(),
      ));

      // Always update score — conversation may improve or change it
      if (result.score != null) {
        await QuestionDAO().saveScore(widget.questionId, result.score!);
        ref.invalidate(questionProvider(widget.questionId));
        ref.invalidate(quizBundleProvider(widget.quizId));
      }

      ref.invalidate(questionMessagesProvider(widget.questionId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Quex is thinking… try again in a moment.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final questionAsync = ref.watch(questionProvider(widget.questionId));
    final messagesAsync = ref.watch(questionMessagesProvider(widget.questionId));
    final materialsAsync = ref.watch(materialsProvider(widget.sessionId));

    return questionAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
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
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          body: Column(
            children: [
              // Materials peek
              materialsAsync.whenData((materials) {
                if (materials.isEmpty) return const SizedBox.shrink();
                return _MaterialsPeek(
                  materials: materials,
                  expanded: _materialsExpanded,
                  onToggle: () =>
                      setState(() => _materialsExpanded = !_materialsExpanded),
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
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Error: $e')),
                  data: (messages) => messages.isEmpty
                      ? _EmptyChat(scheme: scheme, theme: theme)
                      : _MessageList(
                          messages: messages,
                          scrollController: _scrollController,
                          scheme: scheme,
                          theme: theme,
                        ),
                ),
              ),

              // Input — always enabled
              _InputBar(
                controller: _controller,
                sending: _sending,
                onSend: () => messagesAsync.whenData(
                  (messages) => _sendMessage(question, messages),
                ),
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

// ─── Materials Peek ──────────────────────────────────────────────────────────

class _MaterialsPeek extends StatelessWidget {
  final List<StudyMaterial> materials;
  final bool expanded;
  final VoidCallback onToggle;
  final ColorScheme scheme;
  final ThemeData theme;

  const _MaterialsPeek({
    required this.materials,
    required this.expanded,
    required this.onToggle,
    required this.scheme,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row — always visible
            InkWell(
              onTap: onToggle,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.menu_book_outlined,
                        size: 16, color: scheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${materials.length} study material${materials.length == 1 ? '' : 's'}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(
                      expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 18,
                      color: scheme.primary,
                    ),
                  ],
                ),
              ),
            ),
            // Expanded content
            if (expanded)
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                itemCount: materials.length,
                separatorBuilder: (_, __) => Divider(
                  height: 16,
                  color: scheme.outlineVariant,
                ),
                itemBuilder: (context, index) {
                  final m = materials[index];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            m.kind == MaterialKind.text
                                ? Icons.text_snippet_outlined
                                : m.kind == MaterialKind.photo
                                    ? Icons.image_outlined
                                    : Icons.description_outlined,
                            size: 14,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              m.title,
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: scheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        m.content,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.5,
                        ),
                        maxLines: expanded ? null : 4,
                        overflow: expanded ? null : TextOverflow.ellipsis,
                      ),
                    ],
                  );
                },
              ),
          ],
        ),
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
  final ScrollController scrollController;
  final ColorScheme scheme;
  final ThemeData theme;

  const _MessageList({
    required this.messages,
    required this.scrollController,
    required this.scheme,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      itemCount: messages.length,
      itemBuilder: (context, index) {
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
              child: Text(
                msg.content,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color:
                      isUser ? scheme.onPrimaryContainer : scheme.onSurface,
                ),
              ),
            ),
          ),
        );
      },
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
  final ColorScheme scheme;
  final ThemeData theme;

  const _InputBar({
    required this.controller,
    required this.sending,
    required this.onSend,
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
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
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
                    borderSide:
                        BorderSide(color: scheme.primary, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: sending
                  ? SizedBox(
                      key: const ValueKey('loading'),
                      width: 44,
                      height: 44,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: scheme.primary,
                        ),
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
