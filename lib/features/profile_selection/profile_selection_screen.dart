import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quex/generated/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/db/daos.dart';
import '../../core/models/models.dart';
import '../../core/state/app_state.dart';

class ProfileSelectionScreen extends ConsumerStatefulWidget {
  const ProfileSelectionScreen({super.key});

  @override
  ConsumerState<ProfileSelectionScreen> createState() =>
      _ProfileSelectionScreenState();
}

class _ProfileSelectionScreenState extends ConsumerState<ProfileSelectionScreen>
    with TickerProviderStateMixin {
  static const _emojiOptions = [
    '👧',
    '👦',
    '🧒',
    '👶',
    '🎓',
    '🌟',
    '⭐',
    '🦁',
    '🐯',
    '🦊',
    '🐼',
    '🐨',
    '🦆',
    '🐤',
    '🦄',
    '🐙',
  ];

  late final AnimationController _headerController;
  late final AnimationController _cardsController;
  late final Animation<double> _headerFade;
  late final Animation<Offset> _headerSlide;

  @override
  void initState() {
    super.initState();

    _headerController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _cardsController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _headerFade = CurvedAnimation(
      parent: _headerController,
      curve: Curves.easeOut,
    );

    _headerSlide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _headerController,
      curve: Curves.easeOutCubic,
    ));

    // Staggered entry
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _headerController.forward();
    });
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _cardsController.forward();
    });
  }

  @override
  void dispose() {
    _headerController.dispose();
    _cardsController.dispose();
    super.dispose();
  }

  Future<void> _selectProfile(Profile profile) async {
    await saveActiveProfileId(profile.id!);
    if (!mounted) return;
    ref.read(activeProfileProvider.notifier).state = profile.id;
    ref.read(sessionProfileSetProvider.notifier).state = true;
    if (!mounted) return;
    context.push(Routes.home);
  }

  Future<void> _showProfileDialog({Profile? profile}) async {
    final nameController = TextEditingController(text: profile?.name ?? '');
    String emoji = profile?.emoji ?? '🧒';
    int grade = profile?.grade ?? 3;

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (dialogContext) => _ProfileBottomSheet(
        profile: profile,
        nameController: nameController,
        initialEmoji: emoji,
        initialGrade: grade,
        onSave: (name, selectedEmoji, selectedGrade) async {
          final dao = ProfileDAO();
          if (profile == null) {
            await dao.insert(Profile(
              name: name,
              emoji: selectedEmoji,
              grade: selectedGrade,
              defaultQuestionCount: 20,
              createdAt: DateTime.now(),
            ));
          } else {
            await dao.update(profile.copyWith(
              name: name,
              emoji: selectedEmoji,
              grade: selectedGrade,
            ));
          }
          if (!mounted) return;
          ref.invalidate(profilesProvider);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final profilesAsync = ref.watch(profilesProvider);
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      body: profilesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
        data: (profiles) {
          if (profiles.isEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) context.go(Routes.createFirstProfile);
            });
            return const Center(child: CircularProgressIndicator());
          }

          return SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 48),
                // Animated header
                FadeTransition(
                  opacity: _headerFade,
                  child: SlideTransition(
                    position: _headerSlide,
                    child: Column(
                      children: [
                        Text(
                          l10n.whoStudying,
                          style: theme.textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: scheme.primary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.pickProfile,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final crossAxisCount =
                          constraints.maxWidth >= 600 ? 3 : 2;
                      return GridView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                        physics: const ClampingScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          crossAxisSpacing: 20,
                          mainAxisSpacing: 20,
                          childAspectRatio: 0.75,
                        ),
                        itemCount: profiles.length + 1,
                        itemBuilder: (context, index) {
                          // Staggered animation delay
                          final delay = index * 0.08;
                          final start = delay.clamp(0.0, 0.6);

                          if (index == profiles.length) {
                            return _AnimatedCardEntry(
                              animation: _cardsController,
                              delay: start,
                              child: _AddProfileCard(
                                onTap: () => _showProfileDialog(),
                              ),
                            );
                          }
                          final profile = profiles[index];
                          return _AnimatedCardEntry(
                            animation: _cardsController,
                            delay: start,
                            child: _ProfileCard(
                              profile: profile,
                              onTap: () => _selectProfile(profile),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _AnimatedCardEntry extends StatelessWidget {
  final Animation<double> animation;
  final double delay;
  final Widget child;

  const _AnimatedCardEntry({
    required this.animation,
    required this.delay,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final delayedAnimation = CurvedAnimation(
      parent: animation,
      curve: Interval(
        delay.clamp(0.0, 0.6),
        (delay + 0.4).clamp(0.4, 1.0),
        curve: Curves.elasticOut,
      ),
    );

    return AnimatedBuilder(
      animation: delayedAnimation,
      builder: (context, child) {
        final value = delayedAnimation.value;
        return Transform.scale(
          scale: 0.8 + (value * 0.2),
          child: Opacity(
            opacity: value.clamp(0.0, 1.0),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class _ProfileCard extends StatefulWidget {
  final Profile profile;
  final VoidCallback onTap;

  const _ProfileCard({
    required this.profile,
    required this.onTap,
  });

  @override
  State<_ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends State<_ProfileCard> {
  double _scale = 1.0;

  void _onTapDown(TapDownDetails details) {
    setState(() => _scale = 0.96);
  }

  void _onTapUp(TapUpDetails details) {
    setState(() => _scale = 1.0);
  }

  void _onTapCancel() {
    setState(() => _scale = 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // Dynamic background color based on emoji
    final quexColors = theme.extension<QuexColors>();
    final bgColors = [
      scheme.primaryContainer,
      quexColors?.warmRed ?? scheme.secondaryContainer,
      quexColors?.amber ?? scheme.tertiaryContainer,
      scheme.primaryContainer.withValues(alpha: 0.7),
      scheme.secondaryContainer.withValues(alpha: 0.7),
    ];
    final bgColor = bgColors[widget.profile.name.length % bgColors.length];

    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOutCubic,
        child: Card(
          clipBehavior: Clip.antiAlias,
          elevation: 0,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Large avatar with dynamic background
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: bgColor,
                          borderRadius: BorderRadius.circular(28),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          widget.profile.emoji,
                          style: const TextStyle(fontSize: 48),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        widget.profile.name,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      // Grade badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Grade ${widget.profile.grade}',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddProfileCard extends StatefulWidget {
  final VoidCallback onTap;

  const _AddProfileCard({required this.onTap});

  @override
  State<_AddProfileCard> createState() => _AddProfileCardState();
}

class _AddProfileCardState extends State<_AddProfileCard> {
  double _scale = 1.0;

  void _onTapDown(TapDownDetails details) {
    setState(() => _scale = 0.96);
  }

  void _onTapUp(TapUpDetails details) {
    setState(() => _scale = 1.0);
  }

  void _onTapCancel() {
    setState(() => _scale = 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOutCubic,
        child: Card(
          clipBehavior: Clip.antiAlias,
          elevation: 0,
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.add,
                      size: 48,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.addNewProfile,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
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

// Sticker-style emoji picker widget
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
          border:
              isSelected ? Border.all(color: scheme.primary, width: 2) : null,
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

class _ProfileBottomSheet extends StatefulWidget {
  final Profile? profile;
  final TextEditingController nameController;
  final String initialEmoji;
  final int initialGrade;
  final Future<void> Function(String name, String emoji, int grade) onSave;

  const _ProfileBottomSheet({
    required this.profile,
    required this.nameController,
    required this.initialEmoji,
    required this.initialGrade,
    required this.onSave,
  });

  @override
  State<_ProfileBottomSheet> createState() => _ProfileBottomSheetState();
}

class _ProfileBottomSheetState extends State<_ProfileBottomSheet>
    with TickerProviderStateMixin {
  static const _emojiOptions = [
    '👧',
    '👦',
    '🧒',
    '👶',
    '🎓',
    '🌟',
    '⭐',
    '🦁',
    '🐯',
    '🦊',
    '🐼',
    '🐨',
    '🦆',
    '🐤',
    '🦄',
    '🐙',
  ];

  late final AnimationController _slideController;
  late final AnimationController _scaleController;
  late final AnimationController _staggerController;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _scaleAnimation;
  late final List<Animation<double>> _staggerAnimations;

  late String _emoji;
  late int _grade;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _emoji = widget.initialEmoji;
    _grade = widget.initialGrade;

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _staggerController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));

    _scaleAnimation = Tween<double>(
      begin: 0.95,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _scaleController,
      curve: Curves.easeOutCubic,
    ));

    // Staggered animations for fields (5 fields: title, emoji, name, picker, grade, buttons)
    _staggerAnimations = List.generate(6, (index) {
      final start = (index * 0.1).clamp(0.0, 0.5);
      final end = (start + 0.2).clamp(0.2, 1.0);
      return Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _staggerController,
          curve: Interval(start, end, curve: Curves.easeOutCubic),
        ),
      );
    });

    _slideController.forward();
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _staggerController.forward();
    });
  }

  @override
  void dispose() {
    _slideController.dispose();
    _scaleController.dispose();
    _staggerController.dispose();
    super.dispose();
  }

  void _handleEmojiSelection(String newEmoji) {
    setState(() => _emoji = newEmoji);
    _scaleController.forward(from: 0);
  }

  void _onEmojiTap(String emoji) {
    _handleEmojiSelection(emoji);
  }

  Future<void> _handleSave() async {
    final name = widget.nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _saving = true);
    try {
      await widget.onSave(name, _emoji, _grade);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    // Dynamic background color based on emoji
    final quexColors = theme.extension<QuexColors>();
    final bgColors = [
      scheme.primaryContainer,
      quexColors?.warmRed ?? scheme.secondaryContainer,
      quexColors?.amber ?? scheme.tertiaryContainer,
      scheme.primaryContainer.withValues(alpha: 0.7),
      scheme.secondaryContainer.withValues(alpha: 0.7),
    ];
    final bgColor = bgColors[_emoji.length % bgColors.length];

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: SlideTransition(
        position: _slideAnimation,
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: Br.full,
                ),
              ),
              const SizedBox(height: Sp.lg),
              // Title
              AnimatedBuilder(
                animation: _staggerAnimations[0],
                builder: (context, child) {
                  return Opacity(
                    opacity: _staggerAnimations[0].value,
                    child: Transform.translate(
                      offset: Offset(0, 20 * (1 - _staggerAnimations[0].value)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Sp.md),
                        child: Text(
                          widget.profile == null ? l10n.addNewProfile : l10n.editProfile,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: Sp.xl),
              // Emoji preview
              AnimatedBuilder(
                animation: _staggerAnimations[1],
                builder: (context, child) {
                  return Opacity(
                    opacity: _staggerAnimations[1].value,
                    child: Transform.translate(
                      offset: Offset(0, 20 * (1 - _staggerAnimations[1].value)),
                      child: Center(
                        child: AnimatedScale(
                          scale: _scaleAnimation.value,
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutCubic,
                          child: Container(
                            width: 96,
                            height: 96,
                            decoration: BoxDecoration(
                              color: bgColor,
                              borderRadius: Br.full,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              _emoji,
                              style: const TextStyle(fontSize: 44),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: Sp.lg),
              // Name field
              AnimatedBuilder(
                animation: _staggerAnimations[2],
                builder: (context, child) {
                  return Opacity(
                    opacity: _staggerAnimations[2].value,
                    child: Transform.translate(
                      offset: Offset(0, 20 * (1 - _staggerAnimations[2].value)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Sp.md),
                        child: TextField(
                          controller: widget.nameController,
                          decoration: InputDecoration(
                            labelText: l10n.name,
                            hintText: l10n.whatCallYou,
                          ),
                          textCapitalization: TextCapitalization.words,
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: Sp.lg),
              // Emoji picker
              AnimatedBuilder(
                animation: _staggerAnimations[3],
                builder: (context, child) {
                  return Opacity(
                    opacity: _staggerAnimations[3].value,
                    child: Transform.translate(
                      offset: Offset(0, 20 * (1 - _staggerAnimations[3].value)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Sp.md),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.pickCharacter,
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
                                separatorBuilder: (_, __) => const SizedBox(width: 8),
                                itemBuilder: (context, index) {
                                  final value = _emojiOptions[index];
                                  return _StickerEmoji(
                                    emoji: value,
                                    isSelected: _emoji == value,
                                    onTap: () => _onEmojiTap(value),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: Sp.lg),
              // Grade dropdown
              AnimatedBuilder(
                animation: _staggerAnimations[4],
                builder: (context, child) {
                  return Opacity(
                    opacity: _staggerAnimations[4].value,
                    child: Transform.translate(
                      offset: Offset(0, 20 * (1 - _staggerAnimations[4].value)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Sp.md),
                        child: DropdownButtonFormField<int>(
                          value: _grade,
                          decoration: InputDecoration(labelText: l10n.gradeLevel),
                          items: List.generate(
                            12,
                            (index) => DropdownMenuItem(
                              value: index + 1,
                              child: Text('${l10n.grade} ${index + 1}'),
                            ),
                          ),
                          onChanged: (value) =>
                              setState(() => _grade = value ?? _grade),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: Sp.xl),
              // Buttons
              AnimatedBuilder(
                animation: _staggerAnimations[5],
                builder: (context, child) {
                  return Opacity(
                    opacity: _staggerAnimations[5].value,
                    child: Transform.translate(
                      offset: Offset(0, 20 * (1 - _staggerAnimations[5].value)),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(Sp.md, 0, Sp.md, Sp.xl),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () {
                                  widget.nameController.dispose();
                                  Navigator.of(context).pop();
                                },
                                child: Text(l10n.cancel),
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
                                    : Text(l10n.save),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              // Bottom padding for safe area (keyboard + system navigation bar)
              SizedBox(
                height: MediaQuery.of(context).viewInsets.bottom +
                    MediaQuery.of(context).padding.bottom,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
