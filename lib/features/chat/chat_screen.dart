import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_filex/open_filex.dart';

import '../../app/breakpoints.dart';
import '../../app/theme.dart';
import '../../core/ai/gemma_inference_service.dart';
import '../../core/ai/quex_ai.dart';
import '../../core/ai/tutor_event.dart';
import '../../core/db/daos.dart';
import '../../core/models/models.dart';
import '../../core/state/app_state.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final int sessionId;
  final List<int>? preselectedMaterialIds;

  const ChatScreen({
    super.key,
    required this.sessionId,
    this.preselectedMaterialIds,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final Object _gemmaOwnerToken = Object();
  bool _sending = false;
  bool _modelLoading = false;
  String? _streamingContent;
  String? _thinkingContent;
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
    if (mounted) setState(() => _modelLoading = true);
    try {
      return await QuexAi.acquireGemmaService(_gemmaOwnerToken);
    } finally {
      if (mounted) setState(() => _modelLoading = false);
    }
  }

  Future<void> _warmModel() async {
    try {
      await _ensureModel();
    } catch (_) {
      // Send path will surface model load failure if needed.
    }
  }

  Future<void> _resetChat() async {
    await ChatDAO().deleteBySession(widget.sessionId);
    ref.invalidate(chatMessagesProvider(widget.sessionId));
    ref.invalidate(sessionBundleProvider(widget.sessionId));
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
      SessionBundle bundle, List<StudyMaterial> chatMaterials) async {
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

    await ChatDAO().insert(ChatMessage(
      sessionId: widget.sessionId,
      role: ChatRole.user,
      content: text,
      createdAt: DateTime.now(),
    ));
    ref.invalidate(chatMessagesProvider(widget.sessionId));
    ref.invalidate(sessionBundleProvider(widget.sessionId));
    _scrollToBottom();

    final accumulatedReply = StringBuffer();
    final accumulatedThinking = StringBuffer();

    try {
      final stream = service.getCoachReplyStreaming(
        session: bundle.session,
        materials: chatMaterials,
        history: bundle.messages,
        message: text,
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

      // Save first, then wait for provider to reload before clearing the
      // streaming bubble — prevents scroll landing on the user bubble.
      await ChatDAO().insert(ChatMessage(
        sessionId: widget.sessionId,
        role: ChatRole.assistant,
        content: reply,
        createdAt: DateTime.now(),
      ));
      ref.invalidate(chatMessagesProvider(widget.sessionId));
      ref.invalidate(sessionBundleProvider(widget.sessionId));
      await ref.read(sessionBundleProvider(widget.sessionId).future);

      if (mounted) {
        setState(() {
          _streamingContent = null;
          _sending = false;
          _thinkingContent = thinking.isEmpty ? null : thinking;
          _thinkingExpanded = false;
        });
      }
      _scrollToBottom();
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
    final compact = MediaQuery.sizeOf(context).width < QuexBreakpoints.tablet;

    final bundleAsync = ref.watch(sessionBundleProvider(widget.sessionId));

    return bundleAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
      data: (bundle) {
        if (bundle == null) {
          return Scaffold(
            appBar: AppBar(leading: const BackButton()),
            body: const Center(child: Text('Session not found')),
          );
        }

        final messages = bundle.messages;
        final hasThinking = _thinkingContent != null;
        final hasStreaming = _streamingContent != null;
        final isEmpty = messages.isEmpty && !hasThinking && !hasStreaming;

        final chatMaterials = widget.preselectedMaterialIds == null
            ? bundle.materials
            : bundle.materials
                .where((m) => widget.preselectedMaterialIds!.contains(m.id))
                .toList();

        final suggestions = QuexAi.highlights(chatMaterials);

        final chatColumn = Column(
          children: [
            if (chatMaterials.isNotEmpty)
              _MaterialsStrip(
                materials: chatMaterials,
                sessionId: widget.sessionId,
                scheme: scheme,
                theme: theme,
              ),
            Expanded(
              child: isEmpty
                  ? _EmptyChat(
                      scheme: scheme,
                      theme: theme,
                      suggestions: suggestions,
                      onSuggestionTap: (s) {
                        _controller.text = s;
                        _sendMessage(bundle, chatMaterials);
                      },
                    )
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
            _InputBar(
              controller: _controller,
              sending: _sending,
              modelLoading: _modelLoading,
              onSend: () => _sendMessage(bundle, chatMaterials),
              onStop: _stopGeneration,
              scheme: scheme,
              theme: theme,
            ),
          ],
        );

        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () =>
                  context.canPop() ? context.pop() : context.go('/'),
            ),
            title: Text(
              '${bundle.session.emoji} ${bundle.session.title}',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            actions: [
              if (!isEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: TextButton(
                    onPressed: _sending
                        ? null
                        : () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Reset chat?'),
                                content:
                                    const Text('All messages will be deleted.'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('Reset'),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) _resetChat();
                          },
                    child: const Text('Reset'),
                  ),
                ),
            ],
          ),
          body: compact
              ? chatColumn
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: chatColumn),
                    Container(width: 1, color: scheme.outlineVariant),
                    SizedBox(
                      width: 280,
                      child: _TipsPanel(
                        session: bundle.session,
                        suggestions: suggestions,
                        scheme: scheme,
                        theme: theme,
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

// ─── Materials strip ──────────────────────────────────────────────────────────

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

// ─── Message list ─────────────────────────────────────────────────────────────

class _MessageList extends StatelessWidget {
  final List<ChatMessage> messages;
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
    final hasThinking = thinkingContent != null;
    final hasStreaming = streamingContent != null;
    final extraItems = (hasThinking ? 1 : 0) + (hasStreaming ? 1 : 0);
    final totalItems = messages.length + extraItems;

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      itemCount: totalItems,
      itemBuilder: (context, index) {
        if (hasThinking && index == messages.length) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _ThinkingBubble(
              content: thinkingContent!,
              expanded: thinkingExpanded,
              isStreaming:
                  isSending && streamingContent != null ? false : isSending,
              onToggle: onThinkingToggle,
              scheme: scheme,
              theme: theme,
            ),
          );
        }

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
        final isUser = msg.role == ChatRole.user;
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
  final List<String> suggestions;
  final void Function(String) onSuggestionTap;

  const _EmptyChat({
    required this.scheme,
    required this.theme,
    required this.suggestions,
    required this.onSuggestionTap,
  });

  static const _quickPrompts = [
    ('Summarize', 'Summarize this session for me'),
    ('Quiz hints', 'Give me quiz hints for this session'),
    ('Explain simply', 'Explain this session simply'),
  ];

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
              'Ask Quex anything',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Ask about your notes, get a summary, or request quiz hints.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: _quickPrompts
                  .map((p) => ActionChip(
                        label: Text(p.$1),
                        onPressed: () => onSuggestionTap(p.$2),
                      ))
                  .toList(),
            ),
            if (suggestions.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: suggestions
                    .take(4)
                    .map((s) => ActionChip(
                          label: Text('Ask about "$s"'),
                          onPressed: () => onSuggestionTap('Tell me about $s'),
                        ))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Tips panel (tablet sidebar) ─────────────────────────────────────────────

class _TipsPanel extends StatelessWidget {
  final Session session;
  final List<String> suggestions;
  final ColorScheme scheme;
  final ThemeData theme;

  const _TipsPanel({
    required this.session,
    required this.suggestions,
    required this.scheme,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Session',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            '${session.emoji} ${session.title}',
            style:
                theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurface),
          ),
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              'Suggested topics',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: suggestions
                  .map((s) => Chip(
                        label: Text(s,
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: scheme.onSurfaceVariant)),
                        backgroundColor: scheme.surfaceContainerLow,
                        side: BorderSide(color: scheme.outlineVariant),
                        padding: EdgeInsets.zero,
                      ))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Input bar ────────────────────────────────────────────────────────────────

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final bool modelLoading;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final ColorScheme scheme;
  final ThemeData theme;

  const _InputBar({
    required this.controller,
    required this.sending,
    required this.modelLoading,
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
                enabled: !sending && !modelLoading,
                textInputAction: TextInputAction.newline,
                maxLines: 4,
                minLines: 1,
                decoration: InputDecoration(
                  hintText: 'Ask Quex…',
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
              child: modelLoading
                  ? SizedBox(
                      key: const ValueKey('loading'),
                      width: 44,
                      height: 44,
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: scheme.primary,
                          ),
                        ),
                      ),
                    )
                  : sending
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
