import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/breakpoints.dart';
import '../../app/router.dart';
import '../../core/db/daos.dart';
import '../../core/models/models.dart';
import '../../core/state/app_state.dart';
import '../../widgets/quex_ui.dart';

class AddMaterialScreen extends ConsumerStatefulWidget {
  final int sessionId;

  const AddMaterialScreen({super.key, required this.sessionId});

  @override
  ConsumerState<AddMaterialScreen> createState() => _AddMaterialScreenState();
}

class _AddMaterialScreenState extends ConsumerState<AddMaterialScreen> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  MaterialKind _kind = MaterialKind.text;
  bool _saving = false;

  Future<void> _addMaterial({bool continueToProcessing = false}) async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    if (title.isEmpty || content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a title and some content first.')),
      );
      return;
    }

    setState(() => _saving = true);
    final pageIndex = await MaterialDAO().countBySession(widget.sessionId);
    await MaterialDAO().insert(
      StudyMaterial(
        sessionId: widget.sessionId,
        kind: _kind,
        title: title,
        content: content,
        pageIndex: pageIndex,
        createdAt: DateTime.now(),
      ),
    );
    if (!mounted) return;

    ref.invalidate(materialsProvider(widget.sessionId));
    ref.invalidate(sessionBundleProvider(widget.sessionId));
    setState(() {
      _saving = false;
      _titleController.clear();
      _contentController.clear();
    });

    if (continueToProcessing) {
      context.go('/session/${widget.sessionId}/processing');
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < QuexBreakpoints.tablet;
    final sessionAsync = ref.watch(sessionProvider(widget.sessionId));
    final materialsAsync = ref.watch(materialsProvider(widget.sessionId));

    return sessionAsync.when(
      data: (session) {
        if (session == null) {
          return const Scaffold(
            body: Center(child: Text('Session not found')),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(session.title),
            actions: [
              TextButton(
                onPressed: () => context.go(Routes.home),
                child: const Text('Home'),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _saving
                ? null
                : () => _addMaterial(continueToProcessing: true),
            icon: const Icon(Icons.auto_fix_high),
            label: const Text('Process'),
          ),
          body: materialsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(child: Text('Failed to load materials: $error')),
            data: (materials) {
              final layout = compact
                  ? Column(
                      children: [
                        _MaterialForm(
                          titleController: _titleController,
                          contentController: _contentController,
                          kind: _kind,
                          onKindChanged: (kind) => setState(() => _kind = kind),
                          onSave: _saving ? null : () => _addMaterial(),
                          onSaveAndContinue:
                              _saving ? null : () => _addMaterial(continueToProcessing: true),
                        ),
                        const SizedBox(height: 16),
                        _MaterialList(
                          sessionId: widget.sessionId,
                          materials: materials,
                        ),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _MaterialForm(
                            titleController: _titleController,
                            contentController: _contentController,
                            kind: _kind,
                            onKindChanged: (kind) => setState(() => _kind = kind),
                            onSave: _saving ? null : () => _addMaterial(),
                            onSaveAndContinue:
                                _saving ? null : () => _addMaterial(continueToProcessing: true),
                          ),
                        ),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 420,
                          child: _MaterialList(
                            sessionId: widget.sessionId,
                            materials: materials,
                          ),
                        ),
                      ],
                    );

              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                child: layout,
              );
            },
          ),
        );
      },
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        body: Center(child: Text('Failed to load session: $error')),
      ),
    );
  }
}

class _MaterialForm extends StatelessWidget {
  final TextEditingController titleController;
  final TextEditingController contentController;
  final MaterialKind kind;
  final ValueChanged<MaterialKind> onKindChanged;
  final VoidCallback? onSave;
  final VoidCallback? onSaveAndContinue;

  const _MaterialForm({
    required this.titleController,
    required this.contentController,
    required this.kind,
    required this.onKindChanged,
    required this.onSave,
    required this.onSaveAndContinue,
  });

  @override
  Widget build(BuildContext context) {
    return QuexPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const QuexSectionHeader(
            title: 'Add material',
            subtitle: 'Use short, specific notes. These will drive the quiz generator.',
          ),
          const SizedBox(height: 18),
          TextField(
            controller: titleController,
            decoration: const InputDecoration(
              labelText: 'Material title',
              hintText: 'e.g. Multiplying fractions',
            ),
          ),
          const SizedBox(height: 14),
          SegmentedButton<MaterialKind>(
            segments: const [
              ButtonSegment(
                value: MaterialKind.text,
                label: Text('Text'),
                icon: Icon(Icons.notes),
              ),
              ButtonSegment(
                value: MaterialKind.document,
                label: Text('Document'),
                icon: Icon(Icons.description_outlined),
              ),
              ButtonSegment(
                value: MaterialKind.photo,
                label: Text('Photo'),
                icon: Icon(Icons.photo_outlined),
              ),
            ],
            selected: {kind},
            onSelectionChanged: (values) => onKindChanged(values.first),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: contentController,
            maxLines: 8,
            minLines: 5,
            decoration: const InputDecoration(
              labelText: 'Content',
              hintText: 'Paste notes, typed text, or a photo/document description here.',
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: onSave,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save material'),
              ),
              FilledButton.tonalIcon(
                onPressed: onSaveAndContinue,
                icon: const Icon(Icons.auto_fix_high),
                label: const Text('Save & process'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MaterialList extends StatelessWidget {
  final int sessionId;
  final List<StudyMaterial> materials;

  const _MaterialList({
    required this.sessionId,
    required this.materials,
  });

  @override
  Widget build(BuildContext context) {
    return QuexPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const QuexSectionHeader(
            title: 'Session pages',
            subtitle: 'Each note becomes a page in the study set.',
          ),
          const SizedBox(height: 16),
          if (materials.isEmpty)
            const QuexEmptyState(
              icon: Icons.layers_outlined,
              title: 'No materials yet',
              message: 'Add a few notes before moving to processing.',
            )
          else
            ...materials.map(
              (material) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: QuexTonePill(label: '${material.pageIndex + 1}'),
                  title: Text(material.title),
                  subtitle: Text(material.preview),
                ),
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => context.go('/session/$sessionId/processing'),
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Continue to processing'),
          ),
        ],
      ),
    );
  }
}
