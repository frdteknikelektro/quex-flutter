import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:quex/generated/l10n/app_localizations.dart';

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
  static const _topAccentsAsset =
      'assets/images/profile_selection/profile_selection_top_accents.png';
  static const _bottomLandscapeAsset =
      'assets/images/profile_selection/profile_selection_bottom_landscape.png';
  static const _topAccentsDarkAsset =
      'assets/images/profile_selection/profile_selection_top_accents-dark.png';
  static const _bottomLandscapeDarkAsset =
      'assets/images/profile_selection/profile_selection_bottom_landscape-dark.png';

  late final AnimationController _headerController;
  late final AnimationController _cardsController;
  late final Animation<double> _headerFade;
  late final Animation<Offset> _headerSlide;

  @override
  void initState() {
    super.initState();

    _headerController = AnimationController(
      duration: const Duration(milliseconds: 560),
      vsync: this,
    );
    _cardsController = AnimationController(
      duration: const Duration(milliseconds: 760),
      vsync: this,
    );

    _headerFade = CurvedAnimation(
      parent: _headerController,
      curve: Curves.easeOut,
    );
    _headerSlide = Tween<Offset>(
      begin: const Offset(0, 0.16),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _headerController,
      curve: Curves.easeOutCubic,
    ));

    Future.delayed(const Duration(milliseconds: 80), () {
      if (mounted) _headerController.forward();
    });
    Future.delayed(const Duration(milliseconds: 220), () {
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
    final emoji = profile?.emoji ?? '🧒';
    final grade = profile?.grade ?? 3;

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
    nameController.dispose();
  }

  @override
  Widget build(BuildContext context) {
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

          return _ProfileSelectionShell(
            headerFade: _headerFade,
            headerSlide: _headerSlide,
            cardsController: _cardsController,
            profiles: profiles,
            onAddProfile: () => _showProfileDialog(),
            onSelectProfile: _selectProfile,
          );
        },
      ),
    );
  }
}

class _ProfileSelectionShell extends StatelessWidget {
  final Animation<double> headerFade;
  final Animation<Offset> headerSlide;
  final Animation<double> cardsController;
  final List<Profile> profiles;
  final VoidCallback onAddProfile;
  final ValueChanged<Profile> onSelectProfile;

  const _ProfileSelectionShell({
    required this.headerFade,
    required this.headerSlide,
    required this.cardsController,
    required this.profiles,
    required this.onAddProfile,
    required this.onSelectProfile,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final topInset = MediaQuery.paddingOf(context).top;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: theme.brightness == Brightness.dark
              ? [
                  const Color(0xFF0D1B2A), // Midnight blue
                  const Color(0xFF1B263B), // Dark blue
                  const Color(0xFF2C3E50), // Slate blue
                ]
              : [
                  const Color(0xFFEAF8FF), // Light blue
                  const Color(0xFFF9FDFF), // Very light blue
                  const Color(0xFFFFFBF4), // Warm yellow
                ],
          stops: const [0.0, 0.56, 1.0],
        ),
      ),
      child: Stack(
        children: [
          _DecorativeBackdrop(
            topInset: topInset,
            bottomInset: bottomInset,
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: topInset + Sp.xl + Sp.md),
              FadeTransition(
                opacity: headerFade,
                child: SlideTransition(
                  position: headerSlide,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
                    child: Column(
                      children: [
                        Text(
                          l10n.whoStudying,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            color: theme.colorScheme.onSurface,
                            fontWeight: FontWeight.w900,
                            height: 1.08,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: Sp.sm),
                        Text(
                          l10n.pickProfile,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: Sp.xl),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, gridConstraints) {
                    final wide = gridConstraints.maxWidth >= 600;
                    final crossAxisCount = wide ? 3 : 2;
                    final sidePadding = wide ? Sp.xl + Sp.sm : Sp.lg + Sp.xs;
                    const rowHeight = 184.0;

                    return GridView.builder(
                      padding: EdgeInsets.fromLTRB(
                        sidePadding,
                        0,
                        sidePadding,
                        128 + bottomInset,
                      ),
                      physics: const BouncingScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: Sp.lg - Sp.xs,
                        mainAxisSpacing: Sp.lg - Sp.xs,
                        mainAxisExtent: rowHeight,
                      ),
                      itemCount: profiles.length + 1,
                      itemBuilder: (context, index) {
                        final delay = (index * 0.075).clamp(0.0, 0.52);

                        if (index == profiles.length) {
                          return _AnimatedCardEntry(
                            animation: cardsController,
                            delay: delay,
                            child: _AddProfileCard(onTap: onAddProfile),
                          );
                        }

                        final profile = profiles[index];
                        return _AnimatedCardEntry(
                          animation: cardsController,
                          delay: delay,
                          child: _ProfileCard(
                            profile: profile,
                            toneIndex: index,
                            onTap: () => onSelectProfile(profile),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DecorativeBackdrop extends StatelessWidget {
  final double topInset;
  final double bottomInset;

  const _DecorativeBackdrop({
    required this.topInset,
    required this.bottomInset,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Positioned.fill(
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;
            final bottomHeight = size.height * 0.5;

            return Stack(
              children: [
                Positioned(
                  top: topInset + 14,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: size.width > 600 ? size.width * 0.75 : double.infinity,
                      ),
                      child: Image.asset(
                        isDark 
                            ? _ProfileSelectionScreenState._topAccentsDarkAsset
                            : _ProfileSelectionScreenState._topAccentsAsset,
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: -2,
                  right: -2,
                  bottom: bottomInset, // Offset by navigation bar height
                  height: bottomHeight,
                  child: Image.asset(
                    isDark 
                        ? _ProfileSelectionScreenState._bottomLandscapeDarkAsset
                        : _ProfileSelectionScreenState._bottomLandscapeAsset,
                    fit: BoxFit.cover,
                    alignment: Alignment.bottomCenter,
                  ),
                ),
              ],
            );
          },
        ),
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
        (delay + 0.36).clamp(0.36, 1.0),
        curve: Curves.easeOutBack,
      ),
    );

    return AnimatedBuilder(
      animation: delayedAnimation,
      builder: (context, child) {
        final value = delayedAnimation.value;
        return Transform.translate(
          offset: Offset(0, 18 * (1 - value)),
          child: Transform.scale(
            scale: 0.94 + (value * 0.06),
            child: Opacity(
              opacity: value.clamp(0.0, 1.0),
              child: child,
            ),
          ),
        );
      },
      child: child,
    );
  }
}

class _ProfileCard extends StatefulWidget {
  final Profile profile;
  final int toneIndex;
  final VoidCallback onTap;

  const _ProfileCard({
    required this.profile,
    required this.toneIndex,
    required this.onTap,
  });

  @override
  State<_ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends State<_ProfileCard> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bgColor = _avatarColor(context, widget.profile.name);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.965 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: 0.94),
            borderRadius: Br.lg,
            border: Border.all(
              color: _pressed ? scheme.primary : scheme.outlineVariant,
              width: _pressed ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: scheme.shadow.withValues(alpha: _pressed ? 0.12 : 0.08),
                blurRadius: _pressed ? 14 : 10,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: Sp.sm + Sp.xs / 2),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Container(
                            width: 68,
                            height: 68,
                            decoration: BoxDecoration(
                              color: bgColor,
                              borderRadius: Br.md,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              widget.profile.emoji,
                              style: theme.textTheme.headlineMedium,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: Sp.sm + Sp.xs / 2),
                      Text(
                        widget.profile.name,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w900,
                          height: 1.1,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: Sp.sm + Sp.xs / 2),
                      _GradePill(
                        grade: widget.profile.grade,
                        toneIndex: widget.toneIndex,
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 10,
                right: 10,
                child: AnimatedOpacity(
                  opacity: _pressed ? 1 : 0,
                  duration: const Duration(milliseconds: 120),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: Br.full,
                      boxShadow: [
                        BoxShadow(
                          color: scheme.primary.withValues(alpha: 0.24),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.check_rounded,
                      color: scheme.onPrimary,
                      size: 17,
                    ),
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
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.965 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: CustomPaint(
          painter: _DashedRRectPainter(
            color: scheme.primaryContainer.withValues(
              alpha: _pressed ? 0.92 : 0.58,
            ),
            radius: 24,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surface.withValues(alpha: 0.34),
              borderRadius: Br.lg,
            ),
            child: Padding(
              padding: const EdgeInsets.all(Sp.sm + Sp.xs / 2),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: Br.md,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.add_rounded,
                      size: 28,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(height: Sp.sm + Sp.xs + 2),
                  Text(
                    l10n.addNewProfile,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w700,
                      height: 1.16,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
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

class _GradePill extends StatelessWidget {
  final int grade;
  final int toneIndex;

  const _GradePill({
    required this.grade,
    required this.toneIndex,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tones = [
      (scheme.primaryContainer, scheme.primary),
      (scheme.secondaryContainer, scheme.secondary),
    ];
    final tone = tones[toneIndex % tones.length];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.sm + 2, vertical: 5),
      decoration: BoxDecoration(
        color: tone.$1,
        borderRadius: Br.full,
      ),
      child: Text(
        'Grade $grade',
        style: theme.textTheme.labelSmall?.copyWith(
          color: tone.$2,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  final Color color;
  final double radius;

  const _DashedRRectPainter({
    required this.color,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final path = Path()..addRRect(rrect.deflate(1));
    final metrics = path.computeMetrics();
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.45
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (final metric in metrics) {
      var distance = 0.0;
      const dash = 9.0;
      const gap = 7.0;
      while (distance < metric.length) {
        final next = (distance + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.radius != radius;
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
    final theme = Theme.of(context);
    final scheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: isSelected
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest.withValues(alpha: 0.58),
          borderRadius: Br.lg,
          border: Border.all(
            color: isSelected ? scheme.primary : scheme.outlineVariant,
            width: isSelected ? 2 : 1,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          emoji,
          style: theme.textTheme.titleLarge,
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
      duration: const Duration(milliseconds: 420),
      vsync: this,
    );
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _staggerController = AnimationController(
      duration: const Duration(milliseconds: 760),
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
      begin: 0.92,
      end: 1,
    ).animate(CurvedAnimation(
      parent: _scaleController,
      curve: Curves.easeOutBack,
    ));
    _staggerAnimations = List.generate(6, (index) {
      final start = (index * 0.075).clamp(0.0, 0.42);
      final end = (start + 0.26).clamp(0.26, 1.0);
      return CurvedAnimation(
        parent: _staggerController,
        curve: Interval(start, end, curve: Curves.easeOutCubic),
      );
    });

    _slideController.forward();
    _scaleController.forward();
    Future.delayed(const Duration(milliseconds: 80), () {
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

  void _onEmojiTap(String emoji) {
    setState(() => _emoji = emoji);
    _scaleController.forward(from: 0);
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
    final bgColor = _avatarColor(context, _emoji);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: SlideTransition(
        position: _slideAnimation,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Container(
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.only(
                  topLeft: Br.lg.topLeft,
                  topRight: Br.lg.topRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: scheme.shadow.withValues(alpha: 0.14),
                    blurRadius: 30,
                    offset: const Offset(0, -12),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  Sp.lg - Sp.xs,
                  Sp.sm + Sp.xs / 2,
                  Sp.lg - Sp.xs,
                  MediaQuery.of(context).viewInsets.bottom +
                      MediaQuery.of(context).padding.bottom +
                      (Sp.lg - Sp.xs),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: scheme.outlineVariant,
                          borderRadius: Br.full,
                        ),
                      ),
                    ),
                    const SizedBox(height: Sp.lg - Sp.xs),
                    _StaggeredSheetItem(
                      animation: _staggerAnimations[0],
                      child: Text(
                        widget.profile == null
                            ? l10n.addNewProfile
                            : l10n.editProfile,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w900,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: Sp.lg - Sp.xs / 2),
                    _StaggeredSheetItem(
                      animation: _staggerAnimations[1],
                      child: Center(
                        child: AnimatedBuilder(
                          animation: _scaleAnimation,
                          builder: (context, child) {
                            return Transform.scale(
                              scale: _scaleAnimation.value,
                              child: child,
                            );
                          },
                          child: Container(
                            width: 108,
                            height: 108,
                            decoration: BoxDecoration(
                              color: bgColor,
                              borderRadius: Br.lg,
                              boxShadow: [
                                BoxShadow(
                                  color: scheme.shadow.withValues(alpha: 0.1),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              _emoji,
                              style: theme.textTheme.displaySmall,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: Sp.lg),
                    _StaggeredSheetItem(
                      animation: _staggerAnimations[2],
                      child: TextField(
                        controller: widget.nameController,
                        decoration: InputDecoration(
                          labelText: l10n.name,
                          hintText: l10n.whatCallYou,
                        ),
                        textCapitalization: TextCapitalization.words,
                      ),
                    ),
                    const SizedBox(height: Sp.lg - Sp.xs / 2),
                    _StaggeredSheetItem(
                      animation: _staggerAnimations[3],
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.pickCharacter,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: Sp.sm + Sp.xs / 2),
                          SizedBox(
                            height: 58,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: _emojiOptions.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: Sp.sm + 2),
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
                    const SizedBox(height: Sp.lg - Sp.xs / 2),
                    _StaggeredSheetItem(
                      animation: _staggerAnimations[4],
                      child: DropdownButtonFormField<int>(
                        initialValue: _grade,
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
                    const SizedBox(height: Sp.lg),
                    _StaggeredSheetItem(
                      animation: _staggerAnimations[5],
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _saving
                                  ? null
                                  : () => Navigator.of(context).pop(),
                              child: Text(l10n.cancel),
                            ),
                          ),
                          const SizedBox(width: Sp.sm + Sp.xs + 2),
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
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StaggeredSheetItem extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;

  const _StaggeredSheetItem({
    required this.animation,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final value = animation.value;
        return Transform.translate(
          offset: Offset(0, 14 * (1 - value)),
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

Color _avatarColor(BuildContext context, String seed) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  final quexColors = theme.extension<QuexColors>();
  final colors = [
    scheme.primaryContainer,
    scheme.secondaryContainer,
    scheme.tertiaryContainer,
    (quexColors?.warmRed ?? scheme.secondary).withValues(alpha: 0.18),
    (quexColors?.amber ?? scheme.tertiary).withValues(alpha: 0.22),
  ];

  return colors[
      seed.runes.fold<int>(0, (sum, rune) => sum + rune) % colors.length];
}
