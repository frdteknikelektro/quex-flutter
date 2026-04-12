import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_shell.dart';
import '../../app/breakpoints.dart';
import '../../app/router.dart';
import '../../core/db/daos.dart';
import '../../core/models/models.dart';
import '../../core/state/app_state.dart';
import '../../widgets/quex_ui.dart';

class NewSessionScreen extends ConsumerStatefulWidget {
  const NewSessionScreen({super.key});

  @override
  ConsumerState<NewSessionScreen> createState() => _NewSessionScreenState();
}

class _NewSessionScreenState extends ConsumerState<NewSessionScreen> {
  final _titleController = TextEditingController();
  String _emoji = '📘';
  int _grade = 3;
  int _questionCount = 20;
  bool _saving = false;

  static const _emojiOptions = [
    '📘', '📚', '🔢', '🧪', '🌍', '🎨', '⚡', '🌱', '🧠', '🎯', '🪐', '💡',
  ];

  @override
  void initState() {
    super.initState();
    _seedFromProfile();
  }

  Future<void> _seedFromProfile() async {
    final savedId = await readActiveProfileId();
    final profiles = await ProfileDAO().getAll();
    final active = profiles.firstWhere(
      (profile) => profile.id == savedId,
      orElse: () => profiles.first,
    );
    if (!mounted) return;
    setState(() {
      _grade = active.grade;
      _questionCount = active.defaultQuestionCount;
      _emoji = active.emoji == '🧒' ? '📘' : active.emoji;
    });
    ref.read(activeProfileProvider.notifier).state = active.id;
  }

  Future<void> _createSession() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a session title first.')),
      );
      return;
    }

    final activeId = ref.read(activeProfileProvider);
    final profiles = await ProfileDAO().getAll();
    final active = profiles.firstWhere(
      (profile) => profile.id == activeId,
      orElse: () => profiles.first,
    );

    setState(() => _saving = true);
    final sessionId = await SessionDAO().insert(
      Session(
        profileId: active.id!,
        title: title,
        emoji: _emoji,
        gradeOverride: _grade,
        questionCount: _questionCount,
        createdAt: DateTime.now(),
      ),
    );
    if (!mounted) return;

    ref.invalidate(recentSessionsProvider(active.id!));
    setState(() => _saving = false);
    context.go('/session/$sessionId/material');
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < QuexBreakpoints.tablet;
    final preview = _SessionPreview(
      title: _titleController.text.trim().isEmpty ? 'New session' : _titleController.text.trim(),
      emoji: _emoji,
      grade: _grade,
      questionCount: _questionCount,
    );

    return QuexAppShell(
      destination: QuexDestination.newSession,
      title: 'New session',
      actions: [
        TextButton(
          onPressed: _saving ? null : () => context.go(Routes.home),
          child: const Text('Cancel'),
        ),
      ],
      showNavigation: true,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        child: compact
            ? Column(
                children: [
                  _buildForm(context),
                  const SizedBox(height: 16),
                  preview,
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildForm(context)),
                  const SizedBox(width: 16),
                  SizedBox(width: 360, child: preview),
                ],
              ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return QuexPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const QuexSectionHeader(
            title: 'Start a focused study session',
            subtitle: 'Name the session, pick a grade, and choose how many questions you want.',
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _titleController,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Session title',
              hintText: 'e.g. Fractions practice',
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Emoji',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _emojiOptions.map((emoji) {
              final selected = emoji == _emoji;
              return ChoiceChip(
                label: Text(emoji, style: const TextStyle(fontSize: 18)),
                selected: selected,
                onSelected: (_) => setState(() => _emoji = emoji),
              );
            }).toList(),
          ),
          const SizedBox(height: 18),
          Text(
            'Grade',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(12, (index) {
              final grade = index + 1;
              return ChoiceChip(
                label: Text('Grade $grade'),
                selected: _grade == grade,
                onSelected: (_) => setState(() => _grade = grade),
              );
            }),
          ),
          const SizedBox(height: 18),
          Text(
            'Questions',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 10, label: Text('10')),
              ButtonSegment(value: 20, label: Text('20')),
              ButtonSegment(value: 30, label: Text('30')),
            ],
            selected: {_questionCount},
            onSelectionChanged: (value) {
              setState(() => _questionCount = value.first);
            },
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saving ? null : _createSession,
                  icon: _saving
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: scheme.onPrimary,
                          ),
                        )
                      : const Icon(Icons.arrow_forward),
                  label: Text(_saving ? 'Creating...' : 'Continue'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SessionPreview extends StatelessWidget {
  final String title;
  final String emoji;
  final int grade;
  final int questionCount;

  const _SessionPreview({
    required this.title,
    required this.emoji,
    required this.grade,
    required this.questionCount,
  });

  @override
  Widget build(BuildContext context) {
    return QuexPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const QuexSectionHeader(
            title: 'Preview',
            subtitle: 'This is how the session will appear in the dashboard.',
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              QuexAvatar(emoji: emoji, size: 58),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text('Grade $grade • $questionCount questions'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Divider(),
          const SizedBox(height: 12),
          Text(
            'Best practice',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Keep the title short and choose a grade that matches the material, not just the learner age.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}
