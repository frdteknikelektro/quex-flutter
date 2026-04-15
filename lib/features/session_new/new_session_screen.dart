import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/db/daos.dart';
import '../../core/models/models.dart';
import '../../core/state/app_state.dart';

class NewSessionScreen extends ConsumerStatefulWidget {
  const NewSessionScreen({super.key});

  @override
  ConsumerState<NewSessionScreen> createState() => _NewSessionScreenState();
}

class _NewSessionScreenState extends ConsumerState<NewSessionScreen>
    with TickerProviderStateMixin {
  final _titleController = TextEditingController();
  String _emoji = '📘';
  int _grade = 3;
  int _questionCount = 20;
  bool _saving = false;

  late final AnimationController _staggerController;
  late final AnimationController _scaleController;
  late final List<Animation<double>> _staggerAnimations;
  late final Animation<double> _scaleAnimation;

  static const _emojiOptions = [
    '📘', '📚', '🔢', '🧪', '🌍', '🎨', '⚡', '🌱', '🧠', '🎯', '🪐', '💡',
  ];

  @override
  void initState() {
    super.initState();

    _staggerController = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );

    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _staggerAnimations = List.generate(6, (i) {
      final start = (i * 0.1).clamp(0.0, 0.5);
      final end = (start + 0.25).clamp(0.25, 1.0);
      return Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _staggerController,
          curve: Interval(start, end, curve: Curves.easeOutCubic),
        ),
      );
    });

    _scaleAnimation = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeOutCubic),
    );

    _seedFromProfile();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _staggerController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  Future<void> _seedFromProfile() async {
    final savedId = await readActiveProfileId();
    final profiles = await ProfileDAO().getAll();
    if (profiles.isEmpty) return;
    final active = profiles.firstWhere(
      (p) => p.id == savedId,
      orElse: () => profiles.first,
    );
    if (!mounted) return;
    setState(() {
      _grade = active.grade;
      _questionCount = active.defaultQuestionCount;
      _emoji = '📘';
    });
    ref.read(activeProfileProvider.notifier).state = active.id;
    _staggerController.forward();
    _scaleController.forward();
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
      (p) => p.id == activeId,
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

  Color _heroBgColor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final quexColors = Theme.of(context).extension<QuexColors>();
    final bgColors = [
      scheme.primaryContainer,
      quexColors?.warmRed ?? scheme.secondaryContainer,
      quexColors?.amber ?? scheme.tertiaryContainer,
      scheme.primaryContainer.withValues(alpha: 0.7),
      scheme.secondaryContainer.withValues(alpha: 0.7),
    ];
    return bgColors[_emoji.length % bgColors.length];
  }

  Widget _staggerWrap(int index, Widget child) {
    return AnimatedBuilder(
      animation: _staggerAnimations[index],
      builder: (context, ch) {
        final v = _staggerAnimations[index].value;
        return Opacity(
          opacity: v.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - v)),
            child: ch,
          ),
        );
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final title = _titleController.text.trim();

    return Scaffold(
      appBar: AppBar(title: const Text('New Session')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: Sp.page,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── [0] Hero: emoji preview + live title ────────
                  _staggerWrap(
                    0,
                    Column(
                      children: [
                        AnimatedBuilder(
                          animation: _scaleController,
                          builder: (context, _) => Center(
                            child: AnimatedScale(
                              scale: _scaleAnimation.value,
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeOutCubic,
                              child: Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  color: _heroBgColor(context),
                                  borderRadius: Br.lg,
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  _emoji,
                                  style: const TextStyle(fontSize: 48, height: 1),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: Sp.md),
                        Text(
                          title.isEmpty ? 'Session title' : title,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: title.isEmpty
                                ? scheme.onSurfaceVariant
                                : scheme.onSurface,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Grade $_grade  •  $_questionCount questions',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Sp.xl),

                  // ── [1] Session title field ──────────────────────
                  _staggerWrap(
                    1,
                    TextField(
                      controller: _titleController,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Session title',
                        hintText: 'e.g. Fractions practice',
                      ),
                      textCapitalization: TextCapitalization.sentences,
                    ),
                  ),
                  const SizedBox(height: Sp.lg),

                  // ── [2] Emoji picker ─────────────────────────────
                  _staggerWrap(
                    2,
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pick an emoji',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: Sp.sm),
                        SizedBox(
                          height: 60,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _emojiOptions.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 8),
                            itemBuilder: (_, i) {
                              final e = _emojiOptions[i];
                              return _StickerEmoji(
                                emoji: e,
                                isSelected: _emoji == e,
                                onTap: () {
                                  setState(() => _emoji = e);
                                  _scaleController.forward(from: 0);
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Sp.lg),

                  // ── [3] Grade dropdown ───────────────────────────
                  _staggerWrap(
                    3,
                    DropdownButtonFormField<int>(
                      // ignore: deprecated_member_use
                      value: _grade,
                      decoration: const InputDecoration(labelText: 'Grade Level'),
                      items: List.generate(
                        12,
                        (i) => DropdownMenuItem(
                          value: i + 1,
                          child: Text('Grade ${i + 1}'),
                        ),
                      ),
                      onChanged: (value) =>
                          setState(() => _grade = value ?? _grade),
                    ),
                  ),
                  const SizedBox(height: Sp.lg),

                  // ── [4] Question count ───────────────────────────
                  _staggerWrap(
                    4,
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Number of questions',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: Sp.sm),
                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<int>(
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
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Sp.xl),

                  // ── [5] Continue button ──────────────────────────
                  _staggerWrap(
                    5,
                    SizedBox(
                      width: double.infinity,
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
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StickerEmoji extends StatelessWidget {
  final String emoji;
  final bool isSelected;
  final VoidCallback onTap;

  const _StickerEmoji({
    required this.emoji,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: isSelected
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: isSelected ? Border.all(color: scheme.primary, width: 2) : null,
        ),
        alignment: Alignment.center,
        child: Text(
          emoji,
          style: const TextStyle(fontSize: 24),
        ),
      ),
    );
  }
}
