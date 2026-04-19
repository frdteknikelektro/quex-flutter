import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/db/daos.dart';
import '../../core/models/models.dart';
import '../../core/state/app_state.dart';
import '../../core/state/wiki_state.dart';
import '../../widgets/quex_ui.dart';
import '../processing/quiz_generation_modal.dart';

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

  Future<void> _deleteQuiz(int quizId) async {
    await QuizDAO().delete(quizId);
    ref.invalidate(sessionBundleProvider(widget.sessionId));
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
    final wikiHasContentAsync =
        ref.watch(wikiHasContentProvider(widget.sessionId));

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

        final hasWiki = wikiHasContentAsync.maybeWhen(
          data: (value) => value,
          orElse: () => false,
        );

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
          floatingActionButton: bundle.quizzes.isNotEmpty
              ? const FloatingActionButton.extended(
                  onPressed: null,
                  icon: Icon(Icons.auto_fix_high),
                  label: Text('Generate quiz (Coming Soon)'),
                )
              : null,
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
                    materials: bundle.materials,
                    hasWiki: hasWiki,
                  ),
                ),
                const SizedBox(height: 32),
                _staggerWrap(
                  2,
                  _QuizSection(
                    sessionId: widget.sessionId,
                    quizzes: bundle.quizzes,
                    hasMaterials: bundle.materials.isNotEmpty,
                    onDelete: _deleteQuiz,
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

class _NavigationCard extends StatefulWidget {
  final int sessionId;
  final int materialCount;
  final List<StudyMaterial> materials;
  final bool hasWiki;

  const _NavigationCard({
    required this.sessionId,
    required this.materialCount,
    required this.materials,
    required this.hasWiki,
  });

  @override
  State<_NavigationCard> createState() => _NavigationCardState();
}

class _NavigationCardState extends State<_NavigationCard> {
  Future<void> _onChatTap() async {
    if (widget.materials.isEmpty) {
      context.push('/session/${widget.sessionId}/chat');
      return;
    }
    final selectedIds = await showModalBottomSheet<List<int>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ChatMaterialPickerSheet(
        materials: widget.materials,
        sessionId: widget.sessionId,
      ),
    );
    if (!mounted || selectedIds == null) return;
    context.push('/session/${widget.sessionId}/chat', extra: selectedIds);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final subtitle = widget.materialCount == 0
        ? 'Add notes and references'
        : widget.materialCount == 1
            ? '1 study material'
            : '${widget.materialCount} study materials';

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
            onTap: () => context.push('/session/${widget.sessionId}/material'),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            leading: Icon(Icons.auto_stories_outlined, color: scheme.primary),
            title: const Text('Wiki'),
            subtitle: Text(
              widget.hasWiki
                  ? 'Browse index, pages, and reviews'
                  : 'Build a knowledge wiki',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(
              Routes.sessionWiki.replaceFirst(
                ':sessionId',
                '${widget.sessionId}',
              ),
            ),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            leading: Icon(Icons.chat_bubble_outline, color: scheme.primary),
            title: const Text('Chat with AI'),
            subtitle: const Text('Ask questions about your notes'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _onChatTap,
          ),
        ],
      ),
    );
  }
}

class _ChatMaterialPickerSheet extends StatefulWidget {
  final List<StudyMaterial> materials;
  final int sessionId;

  const _ChatMaterialPickerSheet({
    required this.materials,
    required this.sessionId,
  });

  @override
  State<_ChatMaterialPickerSheet> createState() =>
      _ChatMaterialPickerSheetState();
}

class _ChatMaterialPickerSheetState extends State<_ChatMaterialPickerSheet> {
  late Set<int> _selectedIds;

  @override
  void initState() {
    super.initState();
    _selectedIds = widget.materials.map((m) => m.id!).toSet();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: Sp.sm, bottom: Sp.md),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Sp.md, 0, Sp.md, Sp.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Which materials to chat about?',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Quex will use only these in the conversation.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.4,
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: widget.materials.length,
              itemBuilder: (context, index) {
                final m = widget.materials[index];
                final selected = _selectedIds.contains(m.id);
                final emoji = switch (m.kind) {
                  MaterialKind.text => '📝',
                  MaterialKind.document => '📄',
                  MaterialKind.photo => '🖼️',
                };
                final kindLabel = switch (m.kind) {
                  MaterialKind.text => 'Text',
                  MaterialKind.document => 'Document',
                  MaterialKind.photo => 'Photo',
                };
                return CheckboxListTile(
                  controlAffinity: ListTileControlAffinity.leading,
                  value: selected,
                  onChanged: (val) {
                    setState(() {
                      if (val == true) {
                        _selectedIds.add(m.id!);
                      } else {
                        _selectedIds.remove(m.id);
                      }
                    });
                  },
                  title: Text(
                    m.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '$emoji $kindLabel',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(Sp.md),
            child: FilledButton(
              onPressed: _selectedIds.isEmpty
                  ? null
                  : () => Navigator.of(context).pop(_selectedIds.toList()),
              child: Text(
                _selectedIds.isEmpty
                    ? 'Select at least one material'
                    : 'Start chat (${_selectedIds.length})',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuizSection extends StatefulWidget {
  final int sessionId;
  final List<Quiz> quizzes;
  final bool hasMaterials;
  final Future<void> Function(int quizId) onDelete;

  const _QuizSection({
    required this.sessionId,
    required this.quizzes,
    required this.hasMaterials,
    required this.onDelete,
  });

  @override
  State<_QuizSection> createState() => _QuizSectionState();
}

class _QuizSectionState extends State<_QuizSection> {
  final _deletedIds = <int>{};

  @override
  void didUpdateWidget(_QuizSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Clear deleted IDs that no longer exist in the refreshed list.
    final currentIds = widget.quizzes.map((q) => q.id!).toSet();
    _deletedIds.removeWhere((id) => !currentIds.contains(id));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final visible =
        widget.quizzes.where((q) => !_deletedIds.contains(q.id)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (visible.isNotEmpty) ...[
          Text(
            'Recent Quizzes',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          ...visible.map(
            (quiz) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Dismissible(
                key: ValueKey(quiz.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Icon(Icons.delete_outline,
                      color: scheme.onErrorContainer),
                ),
                onDismissed: (_) {
                  setState(() => _deletedIds.add(quiz.id!));
                  widget.onDelete(quiz.id!);
                },
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
                    onTap: () => context
                        .go('/session/${widget.sessionId}/quiz/${quiz.id}'),
                  ),
                ),
              ),
            ),
          ),
        ] else if (widget.hasMaterials) ...[
          _QuizEmptyState(
            onGenerate: () => showDialog(
              context: context,
              barrierDismissible: false,
              builder: (_) => QuizGenerationModal(sessionId: widget.sessionId),
            ),
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
                onPressed: null,
                icon: const Icon(Icons.auto_fix_high),
                label: const Text('Generate quiz (Coming Soon)'),
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
