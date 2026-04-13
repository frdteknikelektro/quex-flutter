import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ai/model_manager.dart';
import '../../core/db/daos.dart';
import '../../core/models/models.dart';
import '../../core/state/app_state.dart';
import '../../widgets/quex_ui.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  static const _emojiOptions = ['👧', '👦', '🧒', '🎓', '🌟', '🦁', '🐯', '🦊'];

  Future<void> _switchProfile(Profile profile) async {
    await saveActiveProfileId(profile.id!);
    if (!mounted) return;
    ref.read(activeProfileProvider.notifier).state = profile.id;
  }

  Future<void> _deleteProfile(Profile profile, List<Profile> profiles) async {
    await ProfileDAO().delete(profile.id!);
    if (!mounted) return;

    final remaining = profiles.where((item) => item.id != profile.id).toList();
    if (remaining.isNotEmpty) {
      await _switchProfile(remaining.first);
    } else {
      ref.read(activeProfileProvider.notifier).state = null;
    }
    ref.invalidate(profilesProvider);
  }

  Future<void> _showProfileDialog({Profile? profile}) async {
    final nameController = TextEditingController(text: profile?.name ?? '');
    String emoji = profile?.emoji ?? '🧒';
    int grade = profile?.grade ?? 3;
    int questions = profile?.defaultQuestionCount ?? 20;

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
                            onSelected: (_) => setDialogState(() => emoji = value),
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
                    onChanged: (value) => setDialogState(() => grade = value ?? grade),
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
                    await dao.insert(
                      Profile(
                        name: name,
                        emoji: emoji,
                        grade: grade,
                        defaultQuestionCount: questions,
                        createdAt: DateTime.now(),
                      ),
                    );
                  } else {
                    await dao.update(
                      profile.copyWith(
                        name: name,
                        emoji: emoji,
                        grade: grade,
                        defaultQuestionCount: questions,
                      ),
                    );
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

  @override
  Widget build(BuildContext context) {
    final profilesAsync = ref.watch(profilesProvider);
    final activeId = ref.watch(activeProfileProvider);

    return profilesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Failed to load settings: $error')),
        data: (profiles) {
          final activeProfile = profiles.where((profile) => profile.id == activeId).firstOrNull ?? profiles.firstOrNull;
          final profilesPanel = _ProfilesPanel(
            profiles: profiles,
            activeId: activeProfile?.id,
            onSwitchProfile: _switchProfile,
            onEditProfile: (profile) => _showProfileDialog(profile: profile),
            onDeleteProfile: (profile) => _deleteProfile(profile, profiles),
            onAddProfile: () => _showProfileDialog(),
          );
          final activePanel = activeProfile == null
              ? const SizedBox.shrink()
              : _ActiveProfilePanel(
                  profile: activeProfile,
                  onUpdate: (updated) async {
                    await ProfileDAO().update(updated);
                    if (!mounted) return;
                    ref.invalidate(profilesProvider);
                  },
                );
          final modelPanel = _ModelPanel(
            onOpenModel: () => context.go('/model-download'),
          );

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 1000;
                if (wide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            profilesPanel,
                            const SizedBox(height: 16),
                            activePanel,
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      SizedBox(width: 360, child: modelPanel),
                    ],
                  );
                }

                return Column(
                  children: [
                    profilesPanel,
                    const SizedBox(height: 16),
                    activePanel,
                    const SizedBox(height: 16),
                    modelPanel,
                  ],
                );
              },
            ),
        );
      },
    );
  }
}

class _ProfilesPanel extends StatelessWidget {
  final List<Profile> profiles;
  final int? activeId;
  final ValueChanged<Profile> onSwitchProfile;
  final ValueChanged<Profile> onEditProfile;
  final ValueChanged<Profile> onDeleteProfile;
  final VoidCallback onAddProfile;

  const _ProfilesPanel({
    required this.profiles,
    required this.activeId,
    required this.onSwitchProfile,
    required this.onEditProfile,
    required this.onDeleteProfile,
    required this.onAddProfile,
  });

  @override
  Widget build(BuildContext context) {
    return QuexPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          QuexSectionHeader(
            title: 'Profiles',
            subtitle: 'Switch between learners without losing the session history.',
            trailing: TextButton(
              onPressed: onAddProfile,
              child: const Text('Add'),
            ),
          ),
          const SizedBox(height: 14),
          ...profiles.map(
            (profile) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                selected: profile.id == activeId,
                leading: QuexAvatar(emoji: profile.emoji),
                title: Text(profile.name),
                subtitle: Text('Grade ${profile.grade} • ${profile.defaultQuestionCount} questions'),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) {
                    switch (value) {
                      case 'switch':
                        onSwitchProfile(profile);
                        return;
                      case 'edit':
                        onEditProfile(profile);
                        return;
                      case 'delete':
                        onDeleteProfile(profile);
                        return;
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'switch', child: Text('Switch')),
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
                onTap: () => onSwitchProfile(profile),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveProfilePanel extends StatelessWidget {
  final Profile profile;
  final Future<void> Function(Profile updated) onUpdate;

  const _ActiveProfilePanel({
    required this.profile,
    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final nameController = TextEditingController(text: profile.name);
    int grade = profile.grade;
    int count = profile.defaultQuestionCount;
    String emoji = profile.emoji;

    return QuexPanel(
      child: StatefulBuilder(
        builder: (context, setState) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const QuexSectionHeader(
                title: 'Active profile',
                subtitle: 'Tune the defaults for the currently selected learner.',
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  QuexAvatar(emoji: emoji, size: 60),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                          controller: nameController,
                          decoration: const InputDecoration(labelText: 'Name'),
                        ),
                        const SizedBox(height: 10),
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
                              setState(() => grade = value ?? grade),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ['👧', '👦', '🧒', '🎓', '🌟'].map((value) {
                  return ChoiceChip(
                    label: Text(value),
                    selected: emoji == value,
                    onSelected: (_) => setState(() => emoji = value),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 10, label: Text('10')),
                  ButtonSegment(value: 20, label: Text('20')),
                  ButtonSegment(value: 30, label: Text('30')),
                ],
                selected: {count},
                onSelectionChanged: (values) =>
                    setState(() => count = values.first),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () async {
                  await onUpdate(
                    profile.copyWith(
                      name: nameController.text.trim().isEmpty
                          ? profile.name
                          : nameController.text.trim(),
                      emoji: emoji,
                      grade: grade,
                      defaultQuestionCount: count,
                    ),
                  );
                },
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save changes'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ModelPanel extends StatelessWidget {
  final VoidCallback onOpenModel;

  const _ModelPanel({required this.onOpenModel});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: ModelManager.isReady(),
      builder: (context, snapshot) {
        final ready = snapshot.data ?? false;
        return QuexPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const QuexSectionHeader(
                title: 'Study engine',
                subtitle: 'Keep the local model status visible from settings.',
              ),
              const SizedBox(height: 14),
              Text(ready ? 'Ready' : 'Not downloaded'),
              const SizedBox(height: 8),
              Text(ModelManager.sizeLabel(ready)),
              const SizedBox(height: 14),
              FilledButton.tonalIcon(
                onPressed: onOpenModel,
                icon: const Icon(Icons.cloud_download_outlined),
                label: const Text('Open model screen'),
              ),
            ],
          ),
        );
      },
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
