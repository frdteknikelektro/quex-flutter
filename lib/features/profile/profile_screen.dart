import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/ai/model_manager.dart';
import '../../core/db/daos.dart';
import '../../core/models/models.dart';
import '../../core/state/app_state.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen>
    with TickerProviderStateMixin {
  late final AnimationController _headerController;
  late final AnimationController _cardController;
  late final Animation<double> _headerFade;
  late final Animation<Offset> _headerSlide;

  @override
  void initState() {
    super.initState();

    _headerController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _cardController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );

    _headerFade = CurvedAnimation(
      parent: _headerController,
      curve: Curves.easeOut,
    );

    _headerSlide = Tween<Offset>(
      begin: const Offset(0, 0.2),
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
      if (mounted) _cardController.forward();
    });
  }

  @override
  void dispose() {
    _headerController.dispose();
    _cardController.dispose();
    super.dispose();
  }

  Future<void> _showEditBottomSheet(Profile profile) async {
    final nameController = TextEditingController(text: profile.name);
    String emoji = profile.emoji;
    int grade = profile.grade;

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (dialogContext) => _EditProfileBottomSheet(
        nameController: nameController,
        initialEmoji: emoji,
        initialGrade: grade,
        onSave: (name, selectedEmoji, selectedGrade) async {
          await ProfileDAO().update(profile.copyWith(
            name: name,
            emoji: selectedEmoji,
            grade: selectedGrade,
          ));
          if (!mounted) return;
          ref.invalidate(profilesProvider);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profilesAsync = ref.watch(profilesProvider);
    final activeId = ref.watch(activeProfileProvider);

    return profilesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Error: $error')),
      data: (profiles) {
        final activeProfile = profiles.where((p) => p.id == activeId).firstOrNull ??
            profiles.firstOrNull;

        if (activeProfile == null) {
          return const Center(child: Text('No profile found'));
        }

        return SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              // Animated header
              FadeTransition(
                opacity: _headerFade,
                child: SlideTransition(
                  position: _headerSlide,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your Profile',
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Manage your learning settings',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
                  child: Column(
                    children: [
                      // Profile Hero Card
                      _AnimatedCardEntry(
                        animation: _cardController,
                        delay: 0.0,
                        child: _ProfileHeroCard(
                          profile: activeProfile,
                          onEdit: () => _showEditBottomSheet(activeProfile),
                          onSwitchProfile: () => context.go(Routes.profileSelection),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Model Status Row
                      _AnimatedCardEntry(
                        animation: _cardController,
                        delay: 0.15,
                        child: _ModelStatusRow(),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
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
        curve: Curves.easeOutCubic,
      ),
    );

    return AnimatedBuilder(
      animation: delayedAnimation,
      builder: (context, child) {
        final value = delayedAnimation.value;
        return Transform.translate(
          offset: Offset(0, 30 * (1 - value)),
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

class _ProfileHeroCard extends StatelessWidget {
  final Profile profile;
  final VoidCallback onEdit;
  final VoidCallback onSwitchProfile;

  const _ProfileHeroCard({
    required this.profile,
    required this.onEdit,
    required this.onSwitchProfile,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final quexColors = theme.extension<QuexColors>();

    // Dynamic background color based on emoji
    final bgColors = [
      scheme.primaryContainer,
      quexColors?.warmRed ?? scheme.secondaryContainer,
      quexColors?.amber ?? scheme.tertiaryContainer,
    ];
    final bgColor = bgColors[profile.name.length % bgColors.length];

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Large Avatar
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(28),
              ),
              alignment: Alignment.center,
              child: Text(
                profile.emoji,
                style: const TextStyle(fontSize: 48),
              ),
            ),
            const SizedBox(height: 20),
            // Name
            Text(
              profile.name,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            // Grade and question count badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'Grade ${profile.grade}  •  ${profile.defaultQuestionCount} questions',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Action buttons
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Edit'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onSwitchProfile,
                    icon: const Icon(Icons.switch_account_outlined, size: 18),
                    label: const Text('Switch'),
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

class _ModelStatusRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return FutureBuilder<bool>(
      future: ModelManager.isReady(),
      builder: (context, snapshot) {
        final ready = snapshot.data ?? false;
        return Card(
          elevation: 0,
          color: scheme.surfaceContainerLow,
          child: ListTile(
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: ready
                    ? scheme.primaryContainer
                    : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                ready ? Icons.check_circle_outline : Icons.cloud_off_outlined,
                color: ready ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
            title: Text(
              'Study Engine',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Text(
              ready ? 'Ready to use' : 'Not downloaded',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go(Routes.modelDownload),
          ),
        );
      },
    );
  }
}

class _EditProfileBottomSheet extends StatefulWidget {
  final TextEditingController nameController;
  final String initialEmoji;
  final int initialGrade;
  final Future<void> Function(String name, String emoji, int grade) onSave;

  const _EditProfileBottomSheet({
    required this.nameController,
    required this.initialEmoji,
    required this.initialGrade,
    required this.onSave,
  });

  @override
  State<_EditProfileBottomSheet> createState() => _EditProfileBottomSheetState();
}

class _EditProfileBottomSheetState extends State<_EditProfileBottomSheet>
    with TickerProviderStateMixin {
  static const _emojiOptions = [
    '👧', '👦', '🧒', '👶', '🎓', '🌟', '⭐',
    '🦁', '🐯', '🦊', '🐼', '🐨', '🦆', '🐤',
    '🦄', '🐙',
  ];

  late final AnimationController _slideController;
  late final AnimationController _scaleController;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _scaleAnimation;

  late String _emoji;
  late int _grade;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _emoji = widget.initialEmoji;
    _grade = widget.initialGrade;

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 200),
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

    _slideController.forward();
    _scaleController.forward();
  }

  @override
  void dispose() {
    _slideController.dispose();
    _scaleController.dispose();
    super.dispose();
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
    final quexColors = theme.extension<QuexColors>();

    // Dynamic background color based on emoji
    final bgColors = [
      scheme.primaryContainer,
      quexColors?.warmRed ?? scheme.secondaryContainer,
      quexColors?.amber ?? scheme.tertiaryContainer,
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
              const SizedBox(height: 24),
              // Title
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Edit Profile',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Emoji preview
              AnimatedScale(
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
              const SizedBox(height: 24),
              // Name field
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  controller: widget.nameController,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    hintText: 'What should we call you?',
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
              ),
              const SizedBox(height: 20),
              // Emoji picker
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pick a character',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 56,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _emojiOptions.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final value = _emojiOptions[index];
                          return _StickerEmoji(
                            emoji: value,
                            isSelected: _emoji == value,
                            onTap: () {
                              setState(() => _emoji = value);
                              _scaleController.forward(from: 0);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Grade dropdown
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: DropdownButtonFormField<int>(
                  initialValue: _grade,
                  decoration: const InputDecoration(labelText: 'Grade Level'),
                  items: List.generate(
                    12,
                    (index) => DropdownMenuItem(
                      value: index + 1,
                      child: Text('Grade ${index + 1}'),
                    ),
                  ),
                  onChanged: (value) => setState(() => _grade = value ?? _grade),
                ),
              ),
              const SizedBox(height: 24),
              // Buttons
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 16),
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
              ),
              // Bottom padding for keyboard
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
          border: isSelected
              ? Border.all(color: scheme.primary, width: 2)
              : null,
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

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
