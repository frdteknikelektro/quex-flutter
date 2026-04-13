import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/db/daos.dart';
import '../../core/models/models.dart';
import '../../core/state/app_state.dart';

class CreateFirstProfileScreen extends ConsumerStatefulWidget {
  const CreateFirstProfileScreen({super.key});

  @override
  ConsumerState<CreateFirstProfileScreen> createState() =>
      _CreateFirstProfileScreenState();
}

class _CreateFirstProfileScreenState
    extends ConsumerState<CreateFirstProfileScreen> {
  static const _emojiOptions = [
    '👧', '👦', '🧒', '🎓', '🌟', '🦁', '🐯', '🦊',
  ];

  final _nameController = TextEditingController();
  String _emoji = '🧒';
  int _grade = 3;
  int _questions = 20;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _createProfile() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _saving = true);
    try {
      final profileId = await ProfileDAO().insert(Profile(
        name: name,
        emoji: _emoji,
        grade: _grade,
        defaultQuestionCount: _questions,
        createdAt: DateTime.now(),
      ));
      if (!mounted) return;
      await saveActiveProfileId(profileId);
      if (!mounted) return;
      ref.read(activeProfileProvider.notifier).state = profileId;
      ref.read(sessionProfileSetProvider.notifier).state = true;
      ref.invalidate(profilesProvider);
      if (!mounted) return;
      context.go(Routes.home);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: Sp.edge,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: Sp.xl),
                  Text(
                    'Create your profile',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Sp.xs),
                  Text(
                    'Set up your first learner profile to begin.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Sp.xl),
                  Center(
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: Br.full,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _emoji,
                        style: const TextStyle(fontSize: 44),
                      ),
                    ),
                  ),
                  const SizedBox(height: Sp.md),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: _emojiOptions
                        .map(
                          (value) => ChoiceChip(
                            label: Text(value),
                            selected: _emoji == value,
                            onSelected: (_) =>
                                setState(() => _emoji = value),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: Sp.lg),
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      hintText: 'e.g. Alice',
                    ),
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: Sp.md),
                  DropdownButtonFormField<int>(
                    initialValue: _grade,
                    decoration: const InputDecoration(labelText: 'Grade'),
                    items: List.generate(
                      12,
                      (index) => DropdownMenuItem(
                        value: index + 1,
                        child: Text('Grade ${index + 1}'),
                      ),
                    ),
                    onChanged: (value) =>
                        setState(() => _grade = value ?? _grade),
                  ),
                  const SizedBox(height: Sp.md),
                  Text(
                    'Default questions per quiz',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: Sp.sm),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 10, label: Text('10')),
                      ButtonSegment(value: 20, label: Text('20')),
                      ButtonSegment(value: 30, label: Text('30')),
                    ],
                    selected: {_questions},
                    onSelectionChanged: (values) =>
                        setState(() => _questions = values.first),
                  ),
                  const SizedBox(height: Sp.xl),
                  FilledButton.icon(
                    onPressed: _saving ? null : _createProfile,
                    icon: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.arrow_forward),
                    label: const Text('Create & Start Studying'),
                  ),
                  const SizedBox(height: Sp.xl),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
