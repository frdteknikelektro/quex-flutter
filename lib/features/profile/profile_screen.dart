import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quex/generated/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/ai/model_download_notifier.dart';
import '../../core/db/daos.dart';
import '../../core/models/models.dart';
import '../../core/state/app_state.dart';
import '../../core/state/language_state.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen>
    with TickerProviderStateMixin {
  late final AnimationController _headerController;
  late final AnimationController _cardController;

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
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Profile Hero
                _AnimatedCardEntry(
                  animation: _cardController,
                  delay: 0.0,
                  child: _ProfileHeroCard(
                    profile: activeProfile,
                    onEdit: () => _showEditBottomSheet(activeProfile),
                    onSwitchProfile: () => context.go(Routes.profileSelection),
                  ),
                ),
                const SizedBox(height: 24),
                // Stats + Settings merged into single card
                _AnimatedCardEntry(
                  animation: _cardController,
                  delay: 0.1,
                  child: _SettingsListCard(profile: activeProfile),
                ),
              ],
            ),
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
    final l10n = AppLocalizations.of(context)!;

    // Dynamic background color based on emoji (matches profile_selection_screen.dart)
    final bgColors = [
      scheme.primaryContainer,
      quexColors?.warmRed ?? scheme.secondaryContainer,
      quexColors?.amber ?? scheme.tertiaryContainer,
      scheme.primaryContainer.withValues(alpha: 0.7),
      scheme.secondaryContainer.withValues(alpha: 0.7),
    ];
    final bgColor = bgColors[profile.name.length % bgColors.length];

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar left, name + grade right
            Row(
              children: [
                // Avatar
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    profile.emoji,
                    style: const TextStyle(fontSize: 40),
                  ),
                ),
                const SizedBox(width: 20),
                // Name and grade
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.name,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Grade ${profile.grade}',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Action buttons
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: Text(l10n.edit),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onSwitchProfile,
                    icon: const Icon(Icons.switch_account_outlined, size: 18),
                    label: Text(l10n.switchButton),
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

class _SettingsListCard extends ConsumerStatefulWidget {
  final Profile profile;

  const _SettingsListCard({required this.profile});

  @override
  ConsumerState<_SettingsListCard> createState() => _SettingsListCardState();
}

class _SettingsListCardState extends ConsumerState<_SettingsListCard> {
  bool _clearingSessions = false;
  bool _deleting = false;
  bool _deletingModel = false;
  String? _selectedLanguage;

  @override
  void initState() {
    super.initState();
    _selectedLanguage = ref.read(languageNotifierProvider);
  }

  Future<void> _clearAllSessions() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.clearAllSessionsQuestion),
        content: Text(l10n.clearAllSessionsConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(l10n.clear),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _clearingSessions = true);
    try {
      await SessionDAO().deleteAllByProfile(widget.profile.id!);
      if (mounted) {
        ref.invalidate(recentSessionsProvider(widget.profile.id!));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.allSessionsCleared)),
        );
      }
    } finally {
      if (mounted) setState(() => _clearingSessions = false);
    }
  }

  Future<void> _deleteProfile() async {
    final l10n = AppLocalizations.of(context)!;
    final profileName = widget.profile.name;
    final controller = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_rounded, color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 8),
            Text(l10n.deleteProfileQuestion),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.deleteProfileConfirm(profileName),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.typeProfileName,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: profileName,
                filled: true,
                fillColor: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.3),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, child) {
              final canDelete = value.text.trim() == profileName;
              return FilledButton(
                onPressed: canDelete ? () => Navigator.pop(context, true) : null,
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                child: Text(l10n.delete),
              );
            },
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _deleting = true);
    try {
      await ProfileDAO().deleteCascade(widget.profile.id!);
      if (mounted) {
        ref.invalidate(profilesProvider);
        ref.read(activeProfileProvider.notifier).state = null;
        ref.read(sessionProfileSetProvider.notifier).state = false;
        context.go(Routes.profileSelection);
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _deleteAIModel() async {
    final l10n = AppLocalizations.of(context)!;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_rounded, color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 8),
            Text(l10n.deleteAIModelQuestion),
          ],
        ),
        content: Text(l10n.deleteAIModelConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _deletingModel = true);
    try {
      await ref.read(modelDownloadProvider.notifier).reset();
      if (mounted) {
        context.go(Routes.splash);
      }
    } finally {
      if (mounted) setState(() => _deletingModel = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Column(
      children: [
        // Metric card
        Card(
          elevation: 0,
          color: scheme.surfaceContainerLow,
          child: FutureBuilder<int>(
            future: SessionDAO().countByProfile(widget.profile.id!),
            builder: (context, snapshot) {
              final count = snapshot.data ?? 0;
              return ListTile(
                leading: Icon(Icons.auto_stories_outlined, color: scheme.primary),
                title: Text(l10n.totalSessions),
                trailing: Text(
                  '$count',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        // Language card
        Card(
          elevation: 0,
          color: scheme.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.language_outlined, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 12),
                    Text(
                      l10n.language,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _selectedLanguage ?? 'en',
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: scheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'en',
                      child: Text('English'),
                    ),
                    DropdownMenuItem(
                      value: 'id',
                      child: Text('Indonesian'),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() => _selectedLanguage = value);
                    ref.read(languageNotifierProvider.notifier).setLanguage(value);
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Actions card
        Card(
          elevation: 0,
          color: scheme.surfaceContainerLow,
          child: Column(
            children: [
              // Clear sessions (neutral)
              ListTile(
                leading: Icon(Icons.folder_delete_outlined, color: scheme.onSurfaceVariant),
                title: Text(l10n.clearAllSessions),
                subtitle: Text(l10n.removeStudyData),
                trailing: _clearingSessions
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.chevron_right),
                onTap: _clearingSessions ? null : _clearAllSessions,
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              // Delete profile (danger)
              ListTile(
                leading: Icon(Icons.delete_forever, color: scheme.error),
                title: Text(
                  l10n.deleteProfile,
                  style: TextStyle(color: scheme.error),
                ),
                subtitle: Text(
                  l10n.removeProfileData(widget.profile.name),
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                trailing: _deleting
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.error,
                        ),
                      )
                    : Icon(Icons.chevron_right, color: scheme.error),
                onTap: _deleting ? null : _deleteProfile,
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              // Delete AI Model (danger)
              ListTile(
                leading: Icon(Icons.psychology_outlined, color: scheme.error),
                title: Text(
                  l10n.deleteAIModel,
                  style: TextStyle(color: scheme.error),
                ),
                subtitle: Text(
                  l10n.deleteAIModelSubtitle,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                trailing: _deletingModel
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.error,
                        ),
                      )
                    : Icon(Icons.chevron_right, color: scheme.error),
                onTap: _deletingModel ? null : _deleteAIModel,
              ),
            ],
          ),
        ),
      ],
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
    final l10n = AppLocalizations.of(context)!;

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
                  l10n.editProfile,
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
                  decoration: InputDecoration(
                    labelText: l10n.name,
                    hintText: l10n.whatCallYou,
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
                      l10n.pickCharacter,
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
                  decoration: InputDecoration(labelText: l10n.gradeLevel),
                  items: List.generate(
                    12,
                    (index) => DropdownMenuItem(
                      value: index + 1,
                      child: Text('${l10n.grade} ${index + 1}'),
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
                        child: Text(l10n.cancel),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _saving ? null : _handleSave,
                        child: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(l10n.save),
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
