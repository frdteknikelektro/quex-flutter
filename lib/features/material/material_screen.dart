import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as pathlib;
import 'package:path_provider/path_provider.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/db/daos.dart';
import '../../core/models/models.dart';
import '../../core/state/app_state.dart';
import '../../core/utils/image_normalizer.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../features/processing/quiz_generation_modal.dart';
import 'material_actions.dart';
import 'pdf_page_picker.dart';

// ─── File storage helper ──────────────────────────────────────────────────────

Future<String?> _copyToMaterialsDir(String srcPath, String originalName) async {
  final appDir = await getApplicationDocumentsDirectory();
  final dir = Directory('${appDir.path}/materials');
  final normalized = await ImageNormalizer.normalizeFile(
    File(srcPath),
    outputDirectory: dir,
    fileStem: originalName,
  );
  return normalized?.file?.path;
}

// ─── Kind metadata helper ─────────────────────────────────────────────────────

({String emoji, Color color}) _kindMeta(
        MaterialKind kind, ColorScheme scheme) =>
    switch (kind) {
      MaterialKind.text => (emoji: '📝', color: scheme.primaryContainer),
      MaterialKind.document => (emoji: '📄', color: scheme.secondaryContainer),
      MaterialKind.photo => (emoji: '🖼️', color: scheme.tertiaryContainer),
    };

// ─── Screen ──────────────────────────────────────────────────────────────────

class MaterialScreen extends ConsumerStatefulWidget {
  final int sessionId;

  const MaterialScreen({super.key, required this.sessionId});

  @override
  ConsumerState<MaterialScreen> createState() => _MaterialScreenState();
}

class _MaterialScreenState extends ConsumerState<MaterialScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _staggerController;
  List<Animation<double>> _staggerAnimations = [];
  int _lastKnownCount = -1;

  @override
  void initState() {
    super.initState();
    _staggerController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _staggerController.dispose();
    super.dispose();
  }

  void _buildStaggerAnimations(int count) {
    _staggerAnimations = List.generate(count.clamp(1, 12), (i) {
      final start = (i * 0.10).clamp(0.0, 0.6);
      final end = (start + 0.40).clamp(0.40, 1.0);
      return Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _staggerController,
          curve: Interval(start, end, curve: Curves.easeOutCubic),
        ),
      );
    });
  }

  Widget _staggerWrap(int index, Widget child) {
    final clamped = index.clamp(0, _staggerAnimations.length - 1);
    return AnimatedBuilder(
      animation: _staggerAnimations[clamped],
      builder: (context, ch) {
        final v = _staggerAnimations[clamped].value;
        return Opacity(
          opacity: v.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - v)),
            child: ch,
          ),
        );
      },
      child: child,
    );
  }

  Future<void> _saveMaterial(
      MaterialKind kind, String title, String content) async {
    final pageIndex = await MaterialDAO().countBySession(widget.sessionId);
    await MaterialDAO().insert(
      StudyMaterial(
        sessionId: widget.sessionId,
        kind: kind,
        title: title,
        content: content,
        pageIndex: pageIndex,
        createdAt: DateTime.now(),
      ),
    );
    if (!mounted) return;
    ref.invalidate(materialsProvider(widget.sessionId));
    ref.invalidate(sessionBundleProvider(widget.sessionId));
  }

  Future<bool?> _confirmDelete(BuildContext ctx) {
    final l10n = AppLocalizations.of(ctx)!;
    return showDialog<bool>(
      context: ctx,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.materialDeleteQuestion),
        content: Text(l10n.materialDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }

  void _openAddSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddMaterialBottomSheet(
        onSaved: (kind, title, content) => _saveMaterial(kind, title, content),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sessionAsync = ref.watch(sessionProvider(widget.sessionId));
    final materialsAsync = ref.watch(materialsProvider(widget.sessionId));

    return sessionAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
          body: Center(
              child: Text(l10n.materialFailedToLoadSession(e.toString())))),
      data: (session) {
        if (session == null) {
          return Scaffold(
              body: Center(child: Text(l10n.materialSessionNotFound)));
        }

        return materialsAsync.when(
          loading: () => _buildScaffold(
            session: session,
            hasMaterials: false,
            body: const Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => _buildScaffold(
            session: session,
            hasMaterials: false,
            body: Center(
                child: Text(l10n.materialCouldNotLoadFiles(e.toString()))),
          ),
          data: (materials) {
            if (_lastKnownCount != materials.length) {
              _buildStaggerAnimations(materials.length);
              _lastKnownCount = materials.length;
              if (materials.isNotEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _staggerController.forward(from: 0);
                });
              } else {
                _staggerController.reset();
              }
            }

            final hasMaterials = materials.isNotEmpty;

            return _buildScaffold(
              session: session,
              hasMaterials: hasMaterials,
              body: hasMaterials
                  ? ListView.builder(
                      padding: const EdgeInsets.only(bottom: Sp.xl),
                      itemCount: materials.length,
                      itemBuilder: (context, index) {
                        final material = materials[index];
                        return _staggerWrap(
                          index,
                          Dismissible(
                            key: ValueKey(material.id),
                            direction: DismissDirection.endToStart,
                            background: const _DismissBackground(),
                            confirmDismiss: (_) => _confirmDelete(context),
                            onDismissed: (_) => deleteMaterial(
                              context,
                              ref,
                              material,
                              skipConfirm: true,
                            ),
                            child: _MaterialFileTile(
                              material: material,
                              sessionId: widget.sessionId,
                              onMenuRename: () =>
                                  renameMaterial(context, ref, material),
                              onMenuDelete: () =>
                                  deleteMaterial(context, ref, material),
                            ),
                          ),
                        );
                      },
                    )
                  : const Center(child: _MaterialEmptyState()),
            );
          },
        );
      },
    );
  }

  Widget _buildScaffold({
    required Session session,
    required bool hasMaterials,
    required Widget body,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(Routes.home),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.sessionDetailStudyMaterials,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              session.title,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      body: body,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddSheet,
        icon: const Icon(Icons.add),
        label: Text(l10n.materialAddMaterial),
      ),
      bottomNavigationBar: hasMaterials
          ? _GenerateQuizBar(
              onPressed: () => showDialog(
                context: context,
                barrierDismissible: false,
                builder: (_) =>
                    QuizGenerationModal(sessionId: widget.sessionId),
              ),
            )
          : null,
    );
  }
}

// ─── Material file tile ───────────────────────────────────────────────────────

class _MaterialFileTile extends StatelessWidget {
  final StudyMaterial material;
  final int sessionId;
  final VoidCallback onMenuDelete;
  final VoidCallback onMenuRename;

  const _MaterialFileTile({
    required this.material,
    required this.sessionId,
    required this.onMenuDelete,
    required this.onMenuRename,
  });

  Widget _buildLeading(ColorScheme scheme) {
    final meta = _kindMeta(material.kind, scheme);

    if (material.kind == MaterialKind.photo && material.content.isNotEmpty) {
      final firstPath = material.content.split('\n').first;
      return Hero(
        tag: 'material-${material.id}-0',
        child: ClipRRect(
          borderRadius: Br.sm,
          child: Image.file(
            File(firstPath),
            width: 44,
            height: 44,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _emojiAvatar(meta, scheme),
          ),
        ),
      );
    }
    return _emojiAvatar(meta, scheme);
  }

  Widget _emojiAvatar(({String emoji, Color color}) meta, ColorScheme scheme) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(color: meta.color, borderRadius: Br.sm),
      alignment: Alignment.center,
      child: Text(meta.emoji, style: const TextStyle(fontSize: 20)),
    );
  }

  String _subtitleText(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final date = DateFormat.MMMd().format(material.createdAt);
    return switch (material.kind) {
      MaterialKind.photo =>
        '${l10n.materialPhotosCount(material.content.split('\n').where((p) => p.isNotEmpty).length)}  ·  $date',
      MaterialKind.document =>
        '${pathlib.extension(material.content).replaceFirst('.', '').toUpperCase()}  ·  $date',
      MaterialKind.text => l10n.materialTextSubtitle(date),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ListTile(
      onTap: () async {
        if (material.kind == MaterialKind.document) {
          final result = await OpenFilex.open(material.content);
          if (result.type != ResultType.done && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(l10n.materialCouldNotOpen(result.message))),
            );
          }
        } else {
          context.push('/session/$sessionId/material/${material.id}');
        }
      },
      contentPadding:
          const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.xs),
      leading: _buildLeading(scheme),
      title: Text(
        material.title,
        style:
            theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        _subtitleText(context),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style:
            theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      ),
      trailing: PopupMenuButton<String>(
        icon: Icon(Icons.more_vert, size: 20, color: scheme.onSurfaceVariant),
        itemBuilder: (_) => [
          PopupMenuItem(value: 'rename', child: Text(l10n.edit)),
          PopupMenuItem(value: 'delete', child: Text(l10n.delete)),
        ],
        onSelected: (value) {
          if (value == 'rename') onMenuRename();
          if (value == 'delete') onMenuDelete();
        },
      ),
    );
  }
}

// ─── Dismiss background ───────────────────────────────────────────────────────

class _DismissBackground extends StatelessWidget {
  const _DismissBackground();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.error,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: Sp.lg),
      child: Icon(Icons.delete_outline, color: scheme.onError),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _MaterialEmptyState extends StatefulWidget {
  const _MaterialEmptyState();

  @override
  State<_MaterialEmptyState> createState() => _MaterialEmptyStateState();
}

class _MaterialEmptyStateState extends State<_MaterialEmptyState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bounceController;
  late final Animation<Offset> _bounceAnimation;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true);
    _bounceAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0, -0.08),
    ).animate(CurvedAnimation(
      parent: _bounceController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _bounceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SlideTransition(
          position: _bounceAnimation,
          child: const Text('📂', style: TextStyle(fontSize: 72)),
        ),
        const SizedBox(height: Sp.lg),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Sp.xl),
          child: Text(
            l10n.materialFolderEmpty,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: Sp.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Sp.xl),
          child: Text(
            l10n.materialFolderEmptySubtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 160),
      ],
    );
  }
}

// ─── Add material bottom sheet ────────────────────────────────────────────────

class _AddMaterialBottomSheet extends StatefulWidget {
  final Future<void> Function(MaterialKind kind, String title, String content)
      onSaved;

  const _AddMaterialBottomSheet({required this.onSaved});

  @override
  State<_AddMaterialBottomSheet> createState() =>
      _AddMaterialBottomSheetState();
}

class _AddMaterialBottomSheetState extends State<_AddMaterialBottomSheet> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  MaterialKind _kind = MaterialKind.photo;
  List<XFile> _selectedPhotos = [];
  List<({String path, String name})> _selectedFiles = [];
  bool _saving = false;
  bool _copying = false;

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pickFromCamera() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
    );
    if (picked != null) setState(() => _selectedPhotos.add(picked));
  }

  Future<void> _pickFromGallery() async {
    final picked = await ImagePicker().pickMultiImage();
    if (picked.isNotEmpty) setState(() => _selectedPhotos.addAll(picked));
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowMultiple: true,
      allowedExtensions: ['pdf'],
    );
    if (result != null) {
      final valid = result.files.where((f) => f.path != null).toList();
      setState(() {
        for (final f in valid) {
          _selectedFiles.add((path: f.path!, name: f.name));
        }
      });
    }
  }

  Future<void> _handleSave() async {
    final title = _titleController.text.trim();
    String content;

    switch (_kind) {
      case MaterialKind.photo:
        final l10n = AppLocalizations.of(context)!;
        if (_selectedPhotos.isEmpty) {
          _showSnack(l10n.materialAddAtLeastOnePhoto);
          return;
        }
        if (title.isEmpty) {
          _showSnack(l10n.materialAddTitle);
          return;
        }
        setState(() => _copying = true);
        final paths = <String>[];
        var failed = 0;
        for (final photo in _selectedPhotos) {
          final path = await _copyToMaterialsDir(
            photo.path,
            pathlib.basenameWithoutExtension(photo.path),
          );
          if (path == null) {
            failed++;
            continue;
          }
          paths.add(path);
        }
        if (paths.isEmpty) {
          if (mounted) setState(() => _copying = false);
          _showSnack('Could not process selected photos.');
          return;
        }
        if (failed > 0) {
          _showSnack(
              'Some photos were skipped because they could not be processed.');
        }
        content = paths.join('\n');

      case MaterialKind.document:
        final l10n = AppLocalizations.of(context)!;
        if (_selectedFiles.isEmpty) {
          _showSnack(l10n.materialPickAtLeastOnePdf);
          return;
        }
        setState(() => _copying = true);
        for (final file in _selectedFiles) {
          if (!mounted) break;
          final pagePaths = await Navigator.of(context).push<List<String>>(
            MaterialPageRoute(
              builder: (_) => PdfPagePickerModal(
                pdfPath: file.path,
                suggestedTitle: pathlib.withoutExtension(file.name),
              ),
            ),
          );
          if (pagePaths == null || pagePaths.isEmpty) continue;
          await widget.onSaved(
            MaterialKind.photo,
            pathlib.withoutExtension(file.name),
            pagePaths.join('\n'),
          );
        }
        if (mounted) Navigator.of(context).pop();
        return;

      case MaterialKind.text:
        final l10n = AppLocalizations.of(context)!;
        final text = _contentController.text.trim();
        if (title.isEmpty || text.isEmpty) {
          _showSnack(l10n.materialAddTitleAndContent);
          return;
        }
        content = text;
    }

    setState(() {
      _saving = true;
      _copying = false;
    });
    try {
      await widget.onSaved(_kind, title, content);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildPhotoView(ColorScheme scheme, BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_selectedPhotos.isNotEmpty) ...[
          SizedBox(
            height: 84,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _selectedPhotos.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final xfile = _selectedPhotos[i];
                return Stack(
                  children: [
                    ClipRRect(
                      borderRadius: Br.sm,
                      child: Image.file(
                        File(xfile.path),
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: GestureDetector(
                        onTap: () =>
                            setState(() => _selectedPhotos.removeAt(i)),
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: scheme.error,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.close,
                              size: 12, color: scheme.onError),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: Sp.sm),
        ],
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickFromCamera,
                icon: const Icon(Icons.camera_alt_outlined, size: 18),
                label: Text(l10n.materialCamera),
              ),
            ),
            const SizedBox(width: Sp.sm),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickFromGallery,
                icon: const Icon(Icons.photo_library_outlined, size: 18),
                label: Text(l10n.materialGallery),
              ),
            ),
          ],
        ),
        const SizedBox(height: Sp.sm),
        TextField(
          controller: _titleController,
          decoration: InputDecoration(labelText: l10n.materialTitle),
          textCapitalization: TextCapitalization.sentences,
        ),
      ],
    );
  }

  Widget _buildDocView(ColorScheme scheme, BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_selectedFiles.isNotEmpty) ...[
          ..._selectedFiles.asMap().entries.map((entry) {
            final i = entry.key;
            final file = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: Sp.xs),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: Sp.sm, vertical: Sp.xs),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: Br.sm,
                ),
                child: Row(
                  children: [
                    Icon(Icons.picture_as_pdf_outlined,
                        size: 20, color: scheme.primary),
                    const SizedBox(width: Sp.sm),
                    Expanded(
                      child: Text(
                        file.name,
                        style: Theme.of(context).textTheme.bodyMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      onPressed: () =>
                          setState(() => _selectedFiles.removeAt(i)),
                      icon: const Icon(Icons.close, size: 18),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: Sp.xs),
        ],
        OutlinedButton.icon(
          onPressed: _pickFiles,
          icon: const Icon(Icons.upload_file, size: 18),
          label: Text(_selectedFiles.isEmpty
              ? l10n.materialPickPdf
              : l10n.materialAddMore),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
          ),
        ),
      ],
    );
  }

  Widget _buildTextView(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _titleController,
          decoration: InputDecoration(
            labelText: l10n.materialTitle,
            hintText: 'e.g. Multiplying fractions',
          ),
          textCapitalization: TextCapitalization.sentences,
        ),
        const SizedBox(height: Sp.sm),
        TextField(
          controller: _contentController,
          maxLines: 6,
          minLines: 3,
          decoration: InputDecoration(
            labelText: l10n.materialNotesContent,
            hintText: l10n.materialNotesHint,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isBusy = _saving || _copying;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.fromLTRB(
          Sp.md,
          Sp.sm,
          Sp.md,
          Sp.xl +
              MediaQuery.of(context).viewInsets.bottom +
              MediaQuery.of(context).padding.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: Sp.lg),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: Br.full,
                ),
              ),
            ),
            Text(
              l10n.materialAddToFolder,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Sp.lg),
            // Kind selector
            _KindSelector(
              selected: _kind,
              onChanged: (kind) => setState(() {
                _kind = kind;
                _titleController.clear();
                _contentController.clear();
                _selectedPhotos = [];
                _selectedFiles = [];
              }),
              scheme: scheme,
            ),
            const SizedBox(height: Sp.md),
            // Per-kind form
            switch (_kind) {
              MaterialKind.photo => _buildPhotoView(scheme, context),
              MaterialKind.document => _buildDocView(scheme, context),
              MaterialKind.text => _buildTextView(context),
            },
            const SizedBox(height: Sp.lg),
            FilledButton(
              onPressed: isBusy ? null : _handleSave,
              child: isBusy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(l10n.materialSaveFile),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Kind selector ────────────────────────────────────────────────────────────

class _KindSelector extends StatelessWidget {
  final MaterialKind selected;
  final ValueChanged<MaterialKind> onChanged;
  final ColorScheme scheme;

  const _KindSelector({
    required this.selected,
    required this.onChanged,
    required this.scheme,
  });

  
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final kinds = [
      (kind: MaterialKind.photo, emoji: '📷', label: l10n.materialKindPhoto),
      (kind: MaterialKind.document, emoji: '📄', label: l10n.materialKindPdf),
      (kind: MaterialKind.text, emoji: '📝', label: l10n.materialKindText),
    ];
    return Row(
      children: kinds.map((entry) {
        final isSelected = selected == entry.kind;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: GestureDetector(
              onTap: () => onChanged(entry.kind),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOutCubic,
                height: 56,
                decoration: BoxDecoration(
                  color: isSelected
                      ? scheme.primaryContainer
                      : scheme.surfaceContainerHighest,
                  borderRadius: Br.sm,
                  border: isSelected
                      ? Border.all(color: scheme.primary, width: 2)
                      : null,
                ),
                alignment: Alignment.center,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(entry.emoji, style: const TextStyle(fontSize: 18)),
                    const SizedBox(height: 2),
                    Text(
                      entry.label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─── Generate quiz bar ────────────────────────────────────────────────────────

class _GenerateQuizBar extends StatelessWidget {
  final VoidCallback onPressed;

  const _GenerateQuizBar({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      padding: EdgeInsets.fromLTRB(
        Sp.md,
        Sp.sm,
        Sp.md,
        Sp.sm + MediaQuery.of(context).padding.bottom,
      ),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: onPressed,
          icon: const Icon(Icons.auto_fix_high),
          label: Text(l10n.sessionDetailGenerateQuiz),
        ),
      ),
    );
  }
}
