import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/ai/model_manager.dart';
import '../../core/db/daos.dart';
import '../../core/models/models.dart';
import '../../core/state/app_state.dart';
import '../../widgets/quex_ui.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  static const _emojiOptions = [
    '👧', '👦', '🧒', '🎓', '🌟', '🦁', '🐯', '🦊',
  ];

  Future<void> _showEditDialog(Profile profile) async {
    final nameController = TextEditingController(text: profile.name);
    String emoji = profile.emoji;
    int grade = profile.grade;
    int questions = profile.defaultQuestionCount;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            title: const Text('Edit profile'),
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
                  await ProfileDAO().update(profile.copyWith(
                    name: name,
                    emoji: emoji,
                    grade: grade,
                    defaultQuestionCount: questions,
                  ));
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
      error: (error, _) =>
          Center(child: Text('Failed to load profile: $error')),
      data: (profiles) {
        final activeProfile =
            profiles.where((p) => p.id == activeId).firstOrNull ??
                profiles.firstOrNull;

        final activePanel = activeProfile == null
            ? const SizedBox.shrink()
            : _ActiveProfileCard(
                profile: activeProfile,
                onEdit: () => _showEditDialog(activeProfile),
              );

        final modelPanel = _ModelPanel(
          onOpenModel: () => context.go(Routes.modelDownload),
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
                    Expanded(child: activePanel),
                    const SizedBox(width: 16),
                    SizedBox(width: 360, child: modelPanel),
                  ],
                );
              }
              return Column(
                children: [
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

class _ActiveProfileCard extends StatelessWidget {
  final Profile profile;
  final VoidCallback onEdit;

  const _ActiveProfileCard({
    required this.profile,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return QuexPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const QuexSectionHeader(
            title: 'Active profile',
            subtitle: 'Your current learner profile.',
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              QuexAvatar(emoji: profile.emoji, size: 64),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.name,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Grade ${profile.grade} • ${profile.defaultQuestionCount} questions',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Edit profile'),
          ),
        ],
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
                subtitle: 'Keep the local model status visible from here.',
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
