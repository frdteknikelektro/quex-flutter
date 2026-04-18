import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/breakpoints.dart';
import '../../core/ai/quex_ai.dart';
import '../../core/db/daos.dart';
import '../../core/models/models.dart';
import '../../core/state/app_state.dart';
import '../../widgets/quex_ui.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final int sessionId;

  const ChatScreen({super.key, required this.sessionId});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  bool _sending = false;

  Future<void> _sendMessage(SessionBundle bundle) async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() => _sending = true);
    await ChatDAO().insert(
      ChatMessage(
        sessionId: widget.sessionId,
        role: ChatRole.user,
        content: text,
        createdAt: DateTime.now(),
      ),
    );
    final reply = await QuexAi.coachReply(
      session: bundle.session,
      materials: bundle.materials,
      history: bundle.messages,
      message: text,
    );
    await ChatDAO().insert(
      ChatMessage(
        sessionId: widget.sessionId,
        role: ChatRole.assistant,
        content: reply,
        createdAt: DateTime.now(),
      ),
    );
    if (!mounted) return;

    ref.invalidate(chatMessagesProvider(widget.sessionId));
    ref.invalidate(sessionBundleProvider(widget.sessionId));
    _controller.clear();
    setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < QuexBreakpoints.tablet;
    final bundleAsync = ref.watch(sessionBundleProvider(widget.sessionId));

    return bundleAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        body: Center(child: Text('Failed to load chat: $error')),
      ),
      data: (bundle) {
        if (bundle == null) {
          return const Scaffold(
            body: Center(child: Text('Session not found')),
          );
        }

        final suggestions = QuexAi.highlights(bundle.materials);

        return Scaffold(
          appBar: AppBar(title: Text('${bundle.session.emoji} ${bundle.session.title}')),
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
            child: compact
                ? Column(
                    children: [
                      _ChatPanel(
                        bundle: bundle,
                        controller: _controller,
                        sending: _sending,
                        onSend: _sending ? null : () => _sendMessage(bundle),
                      ),
                      const SizedBox(height: 16),
                      _TipsPanel(session: bundle.session, suggestions: suggestions),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _ChatPanel(
                          bundle: bundle,
                          controller: _controller,
                          sending: _sending,
                          onSend: _sending ? null : () => _sendMessage(bundle),
                        ),
                      ),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 360,
                        child: _TipsPanel(session: bundle.session, suggestions: suggestions),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

class _ChatPanel extends StatelessWidget {
  final SessionBundle bundle;
  final TextEditingController controller;
  final bool sending;
  final VoidCallback? onSend;

  const _ChatPanel({
    required this.bundle,
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return QuexPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const QuexSectionHeader(
            title: 'Study chat',
            subtitle: 'Ask for summaries, examples, or a quiz review.',
          ),
          const SizedBox(height: 16),
          if (bundle.messages.isEmpty)
            const QuexEmptyState(
              icon: Icons.chat_bubble_outline,
              title: 'Start the conversation',
              message: 'Ask about the session, ask for a summary, or request a quiz hint.',
            )
          else
            ...bundle.messages.map(
              (message) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Align(
                  alignment: message.role == ChatRole.user
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 520),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: message.role == ChatRole.user
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: message.role == ChatRole.user
                        ? Text(message.content)
                        : MarkdownBody(
                            data: message.content,
                            styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                              p: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            maxLines: 3,
            minLines: 1,
            decoration: InputDecoration(
              hintText: 'Ask a question about the session...',
              suffixIcon: IconButton(
                onPressed: onSend,
                icon: sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                label: const Text('Summarize'),
                onPressed: () => controller.text = 'Summarize this session',
              ),
              ActionChip(
                label: const Text('Make quiz hints'),
                onPressed: () => controller.text = 'Give me quiz hints',
              ),
              ActionChip(
                label: const Text('Explain simply'),
                onPressed: () => controller.text = 'Explain this simply',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TipsPanel extends StatelessWidget {
  final Session session;
  final List<String> suggestions;

  const _TipsPanel({
    required this.session,
    required this.suggestions,
  });

  @override
  Widget build(BuildContext context) {
    return QuexPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const QuexSectionHeader(
            title: 'Conversation tips',
            subtitle: 'Tablet layouts keep the chat and context visible together.',
          ),
          const SizedBox(height: 16),
          Text(
            'Session',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(session.title),
          const SizedBox(height: 16),
          Text(
            'Suggested topics',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (suggestions.isEmpty)
            const Text('Add more materials to get stronger prompts.')
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: suggestions.map((item) => QuexTonePill(label: item)).toList(),
            ),
        ],
      ),
    );
  }
}
