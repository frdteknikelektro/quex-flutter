import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

class _ProfileSelectionScreenState
    extends ConsumerState<ProfileSelectionScreen> {
  static const _emojiOptions = [
    '👧', '👦', '🧒', '🎓', '🌟', '🦁', '🐯', '🦊',
  ];

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
          return AlertDialog(
            title: Text(profile == null ? 'Add profile' : 'Edit profile'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Name'),
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _emojiOptions
                        .map(
                          (value) => ChoiceChip(
                            label: Text(value),
                            selected: emoji == value,
                            onSelected: (_) =>
                                setDialogState(() => emoji = value),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<int>(
                    initialValue: grade,
                    decoration: const InputDecoration(labelText: 'Grade'),
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
                  const SizedBox(height: 14),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 10, label: Text('10')),
                      ButtonSegment(value: 20, label: Text('20')),
                      ButtonSegment(value: 30, label: Text('30')),
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
                onPressed: () => Navigator.of(dialogContext).pop(),
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

  Future<void> _deleteProfile(Profile profile, List<Profile> profiles) async {
    if (profiles.length <= 1) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot delete the only profile.')),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete profile'),
        content: Text(
          'Delete "${profile.name}"? All sessions and quizzes for this profile will be lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ProfileDAO().delete(profile.id!);
    if (!mounted) return;
    ref.invalidate(profilesProvider);
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
                const SizedBox(height: Sp.xl),
                Text(
                  'Who\'s studying?',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: Sp.xs),
                Text(
                  'Select your profile to continue',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: Sp.xl),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final crossAxisCount =
                          constraints.maxWidth >= 600 ? 4 : 2;
                      return GridView.builder(
                        padding: const EdgeInsets.fromLTRB(
                          Sp.md, 0, Sp.md, Sp.xl,
                        ),
                        gridDelegate:
                            SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          crossAxisSpacing: Sp.md,
                          mainAxisSpacing: Sp.md,
                          childAspectRatio: 0.85,
                        ),
                        itemCount: profiles.length + 1,
                        itemBuilder: (context, index) {
                          if (index == profiles.length) {
                            return _AddProfileCard(
                              onTap: () => _showProfileDialog(),
                            );
                          }
                          final profile = profiles[index];
                          return _ProfileCard(
                            profile: profile,
                            onTap: () => _selectProfile(profile),
                            onEdit: () =>
                                _showProfileDialog(profile: profile),
                            onDelete: () =>
                                _deleteProfile(profile, profiles),
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

class _ProfileCard extends StatelessWidget {
  final Profile profile;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ProfileCard({
    required this.profile,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Stack(
      children: [
        Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(Sp.md),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: Br.full,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      profile.emoji,
                      style: const TextStyle(fontSize: 36),
                    ),
                  ),
                  const SizedBox(height: Sp.md),
                  Text(
                    profile.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: PopupMenuButton<String>(
            icon: Icon(
              Icons.more_vert,
              size: 20,
              color: scheme.onSurfaceVariant,
            ),
            tooltip: 'Profile options',
            onSelected: (value) {
              if (value == 'edit') onEdit();
              if (value == 'delete') onDelete();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ),
      ],
    );
  }
}

class _AddProfileCard extends StatelessWidget {
  final VoidCallback onTap;

  const _AddProfileCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Sp.md),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: Br.full,
                  border: Border.all(
                    color: scheme.outline,
                    width: 2,
                  ),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.add,
                  size: 36,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: Sp.md),
              Text(
                'Add Profile',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
