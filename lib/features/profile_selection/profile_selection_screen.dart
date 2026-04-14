import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
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
    context.go(Routes.home);
  }

  Future<void> _showProfileDialog({Profile? profile}) async {
    final nameController = TextEditingController(text: profile?.name ?? '');
    String emoji = profile?.emoji ?? '🧒';
    int grade = profile?.grade ?? 3;
    int questions = profile?.defaultQuestionCount ?? 20;

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final scheme = Theme.of(dialogContext).colorScheme;
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            title: Text(
              profile == null ? 'Add New Profile' : 'Edit Profile',
              textAlign: TextAlign.center,
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Large emoji preview
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      emoji,
                      style: const TextStyle(fontSize: 48),
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      hintText: 'What should we call you?',
                    ),
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 20),
                  // Sticker-style emoji picker
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Pick a character',
                      style: Theme.of(dialogContext)
                          .textTheme
                          .labelMedium
                          ?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _emojiOptions
                        .map(
                          (value) => _StickerEmoji(
                            emoji: value,
                            isSelected: emoji == value,
                            onTap: () => setDialogState(() => emoji = value),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<int>(
                    initialValue: grade,
                    decoration: const InputDecoration(labelText: 'Grade Level'),
                    items: List.generate(
                      12,
                      (index) => DropdownMenuItem(
                        value: index + 1,
                        child: Text('Grade ${index + 1}'),
                      ),
                    ),
                    onChanged: (value) =>
                        setDialogState(() => grade = value ?? grade),
                  ),
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'How many questions?',
                      style: Theme.of(dialogContext)
                          .textTheme
                          .labelMedium
                          ?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 10, label: Text('Quick 10')),
                      ButtonSegment(value: 20, label: Text('Standard 20')),
                      ButtonSegment(value: 30, label: Text('Challenge 30')),
                    ],
                    selected: {questions},
                    onSelectionChanged: (values) =>
                        setDialogState(() => questions = values.first),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  nameController.dispose();
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  final name = nameController.text.trim();
                  if (name.isEmpty) return;
                  final dao = ProfileDAO();
                  if (profile == null) {
                    await dao.insert(Profile(
                      name: name,
                      emoji: emoji,
                      grade: grade,
                      defaultQuestionCount: questions,
                      createdAt: DateTime.now(),
                    ));
                  } else {
                    await dao.update(profile.copyWith(
                      name: name,
                      emoji: emoji,
                      grade: grade,
                      defaultQuestionCount: questions,
                    ));
                  }
                  if (!mounted) return;
                  ref.invalidate(profilesProvider);
                  nameController.dispose();
                  if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final profilesAsync = ref.watch(profilesProvider);

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
                          'Who\'s studying?',
                          style: theme.textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: scheme.primary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Pick your profile to start learning! 🚀',
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
    final bgColors = [
      scheme.primaryContainer,
      scheme.secondaryContainer,
      scheme.tertiaryContainer,
      const Color(0xFFFFE4B5), // Warm peach
      const Color(0xFFE0F2FE), // Light blue
      const Color(0xFFDCFCE7), // Light green
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
                    'Add New Profile',
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
