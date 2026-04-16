import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/db/daos.dart';
import '../../core/models/models.dart';
import '../../core/state/app_state.dart';
import '../../widgets/quex_ui.dart';

class SessionDetailScreen extends ConsumerStatefulWidget {
  final int sessionId;

  const SessionDetailScreen({super.key, required this.sessionId});

  @override
  ConsumerState<SessionDetailScreen> createState() =>
      _SessionDetailScreenState();
}

class _SessionDetailScreenState extends ConsumerState<SessionDetailScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _staggerController;
  late final List<Animation<double>> _staggerAnimations;

  @override
  void initState() {
    super.initState();

    _staggerController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _staggerAnimations = List.generate(3, (i) {
      final start = (i * 0.15).clamp(0.0, 0.5);
      final end = (start + 0.35).clamp(0.35, 1.0);
      return Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _staggerController,
          curve: Interval(start, end, curve: Curves.easeOutCubic),
        ),
      );
    });

    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _staggerController.forward();
    });
  }

  @override
  void dispose() {
    _staggerController.dispose();
    super.dispose();
  }

  Future<void> _showEditBottomSheet(Session session) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditSessionBottomSheet(
        session: session,
        onSave: (title, emoji) async {
          await SessionDAO()
              .update(session.copyWith(title: title, emoji: emoji));
          if (!mounted) return;
          ref.invalidate(sessionBundleProvider(widget.sessionId));
          final profileId = ref.read(activeProfileProvider);
          if (profileId != null) {
            ref.invalidate(recentSessionsProvider(profileId));
          }
        },
      ),
    );
  }

  Widget _staggerWrap(int index, Widget child) {
    return AnimatedBuilder(
      animation: _staggerAnimations[index],
      builder: (context, ch) {
        final v = _staggerAnimations[index].value;
        return Opacity(
          opacity: v.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 24 * (1 - v)),
            child: ch,
          ),
        );
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bundleAsync = ref.watch(sessionBundleProvider(widget.sessionId));

    return bundleAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        body: Center(child: Text('Failed to load session: $error')),
      ),
      data: (bundle) {
        if (bundle == null) {
          return const Scaffold(
            body: Center(child: Text('Session not found')),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Session'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TextButton(
                  onPressed: () => _showEditBottomSheet(bundle.session),
                  child: const Text('Edit'),
                ),
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _staggerWrap(
                  0,
                  _SessionHeader(bundle: bundle),
                ),
                const SizedBox(height: 32),
                _staggerWrap(
                  1,
                  _NavigationCard(
                    sessionId: widget.sessionId,
                    materialCount: bundle.materials.length,
                  ),
                ),
                const SizedBox(height: 32),
                _staggerWrap(
                  2,
                  _QuizSection(
                    sessionId: widget.sessionId,
                    quizzes: bundle.quizzes,
                    hasMaterials: bundle.materials.isNotEmpty,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SessionHeader extends StatelessWidget {
  final SessionBundle bundle;

  const _SessionHeader({required this.bundle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final session = bundle.session;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        QuexAvatar(emoji: session.emoji, size: 58),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Grade ${session.gradeOverride}  •  ${DateFormat.yMMMMd().format(session.createdAt)}',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                session.title,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: scheme.primary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NavigationCard extends StatelessWidget {
  final int sessionId;
  final int materialCount;

  const _NavigationCard({
    required this.sessionId,
    required this.materialCount,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final subtitle = materialCount == 0
        ? 'Add notes and references'
        : materialCount == 1
            ? '1 study material'
            : '$materialCount study materials';

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      child: Column(
        children: [
          ListTile(
            leading: Icon(Icons.library_books_outlined, color: scheme.primary),
            title: const Text('Study Materials'),
            subtitle: Text(subtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/session/$sessionId/material'),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            leading: Icon(Icons.chat_bubble_outline, color: scheme.primary),
            title: const Text('Chat with AI'),
            subtitle: const Text('Ask questions about your notes'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/session/$sessionId/chat'),
          ),
        ],
      ),
    );
  }
}

class _QuizSection extends StatelessWidget {
  final int sessionId;
  final List<Quiz> quizzes;
  final bool hasMaterials;

  const _QuizSection({
    required this.sessionId,
    required this.quizzes,
    required this.hasMaterials,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (quizzes.isNotEmpty) ...[
          Text(
            'Recent Quizzes',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          ...quizzes.map(
            (quiz) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                elevation: 0,
                color: scheme.surfaceContainerLow,
                child: ListTile(
                  leading: Icon(
                    quiz.isCompleted ? Icons.check_circle : Icons.pending,
                    color: quiz.isCompleted
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                  ),
                  title: Text(
                    quiz.isCompleted
                        ? 'Score ${quiz.score}/${quiz.questionCount}'
                        : 'In progress',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      context.go('/session/$sessionId/quiz/${quiz.id}'),
                ),
              ),
            ),
          ),
          Center(
            child: TextButton.icon(
              onPressed: () => context.go('/session/$sessionId/processing'),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Generate another quiz'),
            ),
          ),
        ] else if (hasMaterials) ...[
          _QuizEmptyState(
            onGenerate: () => context.go('/session/$sessionId/processing'),
          ),
        ] else ...[
          Text(
            'Add study materials first, then generate a quiz.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _QuizEmptyState extends StatefulWidget {
  final VoidCallback onGenerate;

  const _QuizEmptyState({required this.onGenerate});

  @override
  State<_QuizEmptyState> createState() => _QuizEmptyStateState();
}

class _QuizEmptyStateState extends State<_QuizEmptyState> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Ready to make a quiz?',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: widget.onGenerate,
                icon: const Icon(Icons.auto_fix_high),
                label: const Text('Generate quiz'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditSessionBottomSheet extends StatefulWidget {
  final Session session;
  final Future<void> Function(String title, String emoji) onSave;

  const _EditSessionBottomSheet({
    required this.session,
    required this.onSave,
  });

  @override
  State<_EditSessionBottomSheet> createState() =>
      _EditSessionBottomSheetState();
}

class _EditSessionBottomSheetState extends State<_EditSessionBottomSheet> {
  static const _emojiOptions = [
    '📘',
    '📚',
    '🔢',
    '🧪',
    '🌍',
    '🎨',
    '⚡',
    '🌱',
    '🧠',
    '🎯',
    '🪐',
    '💡',
  ];

  late final TextEditingController _titleController;
  late String _emoji;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.session.title);
    _emoji = widget.session.emoji;
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(title, _emoji);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.fromLTRB(
          Sp.md,
          Sp.sm,
          Sp.md,
          Sp.xl +
              MediaQuery.of(context).viewInsets.bottom +
              MediaQuery.of(context).padding.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: Sp.lg),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Text(
              'Edit Session',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: Sp.xl),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Session title'),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: Sp.lg),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Pick an emoji',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: Sp.sm),
            SizedBox(
              height: 60,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _emojiOptions.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final e = _emojiOptions[i];
                  final selected = _emoji == e;
                  return GestureDetector(
                    onTap: () => setState(() => _emoji = e),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      curve: Curves.easeOutCubic,
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: selected
                            ? scheme.primaryContainer
                            : scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16),
                        border: selected
                            ? Border.all(color: scheme.primary, width: 2)
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Text(e, style: const TextStyle(fontSize: 24)),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: Sp.xl),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: Sp.md),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : _handleSave,
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
