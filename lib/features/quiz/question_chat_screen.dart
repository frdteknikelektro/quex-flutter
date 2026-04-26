import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../widgets/math_markdown.dart';
import 'package:go_router/go_router.dart';
import 'package:open_filex/open_filex.dart';

import '../../app/theme.dart';
import '../../core/ai/gemma_inference_service.dart';
import '../../core/ai/gemma_service_host.dart';
import '../../core/ai/gemma_session_service.dart';
import '../../core/ai/tutor_event.dart';
import '../../core/db/daos.dart';
import '../../core/models/models.dart';
import '../../core/state/app_state.dart';
import '../../generated/l10n/app_localizations.dart';

class QuestionChatScreen extends ConsumerStatefulWidget {
  final int sessionId;
  final int quizId;
  final int questionId;
  final GemmaInferenceService Function()? gemmaServiceFactory;

  const QuestionChatScreen({
    super.key,
    required this.sessionId,
    required this.quizId,
    required this.questionId,
    this.gemmaServiceFactory,
  });

  @override
  ConsumerState<QuestionChatScreen> createState() => _QuestionChatScreenState();
}

class _QuestionChatScreenState extends ConsumerState<QuestionChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  late final GemmaServiceHost _gemmaHost;
  bool _sending = false;
  bool _modelLoading = false;
  Future<void>? _preloadFuture;
  String? _streamingContent; // reply tokens accumulating
  String?
      _thinkingContent; // thinking tokens accumulating (null = not thinking)
  bool _thinkingExpanded = false;
  StreamSubscription<TutorEvent>? _streamSub;
  GemmaSessionService? _sessionService;

  // Persistent session state
  double? _currentScore;

  @override
  void initState() {
    super.initState();
    _gemmaHost = GemmaServiceHost(
      service: widget.gemmaServiceFactory?.call(),
    );
    unawaited(_warmModel());
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    unawaited(_gemmaHost.dispose());
    super.dispose();
  }

  Future<GemmaInferenceService> _ensureModel() {
    return _gemmaHost.ensureInitialized();
  }

  Future<void> _warmModel() async {
    try {
      if (mounted) setState(() => _modelLoading = true);
      await _ensureModel();
    } catch (_) {
      // Send path will surface model load failure if needed.
    } finally {
      if (mounted) setState(() => _modelLoading = false);
    }
  }

  void _startTutorSessionPreload(
    Question question,
    List<StudyMaterial> materials,
    List<QuestionMessage> messages,
  ) {
    if (_preloadFuture != null) return;

    final future = _preloadTutorSession(question, materials, messages);
    _preloadFuture = future;
    future.then((_) {
      if (!mounted) return;
      setState(() {});
    }).catchError((Object error) {
      debugPrint('Failed to preload tutor session: $error');
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      setState(() {
        _sessionService = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.questionChatFailedToPreload(error.toString()))),
      );
    });
  }

  Future<void> _preloadTutorSession(
    Question question,
    List<StudyMaterial> materials,
    List<QuestionMessage> messages,
  ) async {
    final service = await _ensureModel();
    _sessionService = GemmaSessionService(service);
    await _sessionService!.preloadQuestionTutorSession(
      question: question,
      materials: materials,
      history: messages,
    );
  }

  /// Initialize tutor session with proper guards for concurrent calls.
  Future<void> _ensureTutorSession(
    Question question,
    List<StudyMaterial> materials,
    List<QuestionMessage> messages,
  ) async {
    _startTutorSessionPreload(question, materials, messages);
    final preload = _preloadFuture;
    if (preload == null) {
      throw StateError('Failed to start tutor preload.');
    }
    await preload;
  }

  /// Handle score from tool evaluation.
  Future<void> _handleScore(double score) async {
    if (!mounted) return;

    setState(() => _currentScore = score);

    await QuestionDAO().saveScore(widget.questionId, score);
    ref.invalidate(questionProvider(widget.questionId));
    ref.invalidate(quizBundleProvider(widget.quizId));
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
    Question question,
    List<StudyMaterial> materials,
    List<QuestionMessage> messages,
  ) async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    // Initialize session once per screen visit.
    try {
      await _ensureTutorSession(question, materials, messages);
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        final message = e is StateError && e.message.contains('model')
            ? l10n.chatCouldNotLoadModel(e.toString())
            : l10n.chatFailedToStartSession;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
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
      final stream = _sessionService!.sendQuestionTutorMessage(text);

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
          } else if (event is TutorEvaluation) {
            unawaited(_handleScore(event.score));
          }
        },
        onDone: () => completer.complete(),
        onError: (e) => completer.completeError(e),
        cancelOnError: true,
      );

      await completer.future;

      final reply = accumulatedReply.toString();
      final thinking = accumulatedThinking.toString();

      // Save assistant reply
      if (reply.isNotEmpty) {
        await QuestionMessageDAO().insert(QuestionMessage(
          questionId: widget.questionId,
          role: QuestionMessageRole.assistant,
          content: reply,
          createdAt: DateTime.now(),
        ));
        ref.invalidate(questionMessagesProvider(widget.questionId));
        await ref.read(questionMessagesProvider(widget.questionId).future);
      }

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
      debugPrint('Tutor stream error: $e');

      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        setState(() {
          _sessionService = null;
          _streamingContent = null;
          _thinkingContent = null;
          _sending = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.chatSessionInterrupted),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final questionAsync = ref.watch(questionProvider(widget.questionId));
    final materialsAsync = ref.watch(materialsProvider(widget.sessionId));
    final materials = materialsAsync.valueOrNull ?? const <StudyMaterial>[];
    final materialsReady = materialsAsync.hasValue;
    final messagesAsync =
        ref.watch(questionMessagesProvider(widget.questionId));
    final messages = messagesAsync.valueOrNull ?? const <QuestionMessage>[];
    final messagesReady = messagesAsync.hasValue;

    final currentQuestion = questionAsync.valueOrNull;
    if (currentQuestion != null &&
        materialsReady &&
        messagesReady &&
        _preloadFuture == null) {
      _startTutorSessionPreload(
        currentQuestion,
        materials,
        messages,
      );
    }

    return questionAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text(l10n.chatError(e.toString())))),
      data: (question) {
        if (question == null) {
          return Scaffold(
            appBar: AppBar(leading: const BackButton()),
            body: Center(child: Text(l10n.questionChatNotFound)),
          );
        }

        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.pop(),
            ),
            title: Text(
              l10n.questionChatTitle(question.orderIndex + 1),
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          body: Column(
            children: [
              if (materials.isNotEmpty)
                _MaterialsStrip(
                  materials: materials,
                  sessionId: widget.sessionId,
                  scheme: scheme,
                  theme: theme,
                ),
              if ((_currentScore ?? question.score) != null)
                _ScoreBadgeRow(
                    score: _currentScore ?? question.score ?? 0.0,
                    scheme: scheme,
                    theme: theme),

              Expanded(
                child: messagesAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Error: $e')),
                  data: (messages) => (messages.isEmpty &&
                          _streamingContent == null &&
                          _thinkingContent == null)
                      ? _ThreadList(
                          question: question,
                          messages: const [],
                          streamingContent: null,
                          thinkingContent: null,
                          thinkingExpanded: _thinkingExpanded,
                          onThinkingToggle: () => setState(
                              () => _thinkingExpanded = !_thinkingExpanded),
                          isSending: _sending,
                          scrollController: _scrollController,
                          scheme: scheme,
                          theme: theme,
                        )
                      : _ThreadList(
                          question: question,
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
                modelLoading: _modelLoading,
                canSend: materialsReady && messagesReady,
                onSend: () => _sendMessage(question, materials, messages),
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
                    final l10n = AppLocalizations.of(context)!;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(l10n.materialCouldNotOpen(result.message))),
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
    final l10n = AppLocalizations.of(context)!;
    final Color color;
    final String label;
    final IconData icon;

    if (score >= 0.8) {
      color = const Color(0xFF4CAF50);
      label = l10n.questionChatScoreCorrect;
      icon = Icons.check_circle;
    } else if (score >= 0.4) {
      color = const Color(0xFFFFB347);
      label = l10n.questionChatScorePartial;
      icon = Icons.remove_circle;
    } else {
      color = const Color(0xFFFF6B6B);
      label = l10n.questionChatScoreIncorrect;
      icon = Icons.cancel;
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
    final l10n = AppLocalizations.of(context)!;
    final hasOptions = question.type == QuestionType.multipleChoice &&
        question.options.isNotEmpty;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: double.infinity,
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(18),
          ),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.questionChatQuestionLabel,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 8),
              MathMarkdownBody(
                data: question.questionText,
                styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                  p: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                    height: 1.25,
                  ),
                ),
                textStyle: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                  height: 1.25,
                ),
              ),
              if (hasOptions) ...[
                const SizedBox(height: 14),
                ...question.options.asMap().entries.map((entry) {
                  final letter = String.fromCharCode(65 + entry.key);
                  final isLast = entry.key == question.options.length - 1;
                  return Padding(
                    padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 24,
                          child: Text(
                            '$letter.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Expanded(
                          child: MathMarkdownBody(
                            data: entry.value,
                            styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                              p: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                                height: 1.35,
                              ),
                            ),
                            textStyle: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Conversation thread ─────────────────────────────────────────────────────

class _ThreadList extends StatelessWidget {
  final Question question;
  final List<QuestionMessage> messages;
  final String? streamingContent;
  final String? thinkingContent;
  final bool thinkingExpanded;
  final VoidCallback onThinkingToggle;
  final bool isSending;
  final ScrollController scrollController;
  final ColorScheme scheme;
  final ThemeData theme;

  const _ThreadList({
    required this.question,
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
    // Question bubble + extra slots: thinking bubble + reply bubble (when active)
    final hasThinking = thinkingContent != null;
    final hasStreaming = streamingContent != null;
    final extraItems = (hasThinking ? 1 : 0) + (hasStreaming ? 1 : 0);
    final totalItems = 1 + messages.length + extraItems;

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      itemCount: totalItems,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _QuestionCard(
              question: question,
              scheme: scheme,
              theme: theme,
            ),
          );
        }

        final messageIndex = index - 1;

        // Thinking bubble — appears before streaming reply
        if (hasThinking && messageIndex == messages.length) {
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
        if (hasStreaming && messageIndex == replyIndex) {
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
                    : MathMarkdownBody(
                        data: streamingContent!,
                        styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                          p: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurface,
                          ),
                        ),
                        textStyle: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurface,
                        ),
                      ),
              ),
            ),
          );
        }

        final msg = messages[messageIndex];
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
                  : MathMarkdownBody(
                      data: msg.content,
                      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                        p: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurface,
                        ),
                      ),
                      textStyle: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurface,
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
    final l10n = AppLocalizations.of(context)!;
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
                      isStreaming ? l10n.chatThinking : l10n.chatThoughtProcess,
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

// ─── Input bar ────────────────────────────────────────────────────────────────

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final bool modelLoading;
  final bool canSend;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final ColorScheme scheme;
  final ThemeData theme;

  const _InputBar({
    required this.controller,
    required this.sending,
    required this.modelLoading,
    required this.canSend,
    required this.onSend,
    required this.onStop,
    required this.scheme,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
                enabled: !sending && !modelLoading && canSend,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: l10n.questionChatTalkToQuex,
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
                          icon: Icon(
                            Icons.stop_rounded,
                            color: scheme.onErrorContainer,
                          ),
                          style: IconButton.styleFrom(
                            backgroundColor: scheme.errorContainer,
                            minimumSize: const Size(44, 44),
                          ),
                        )
                      : IconButton(
                          key: const ValueKey('send'),
                          onPressed: canSend ? onSend : null,
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
