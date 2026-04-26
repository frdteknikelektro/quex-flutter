import 'dart:io';

import 'package:flutter/material.dart';
import '../../widgets/math_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as pathlib;

import '../../app/theme.dart';
import '../../core/db/daos.dart';
import '../../core/models/models.dart';
import '../../core/state/app_state.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../widgets/quex_ui.dart';
import 'material_actions.dart';

/// Detail view for a single [StudyMaterial]. Branches on kind:
///  - `text`     → scrollable reader with selectable text.
///  - `photo`    → immersive gallery with pinch-zoom and paging.
///  - `document` → metadata card + handoff to the system viewer via open_filex.
class MaterialDetailScreen extends ConsumerWidget {
  final int sessionId;
  final int materialId;

  const MaterialDetailScreen({
    super.key,
    required this.sessionId,
    required this.materialId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final materialsAsync = ref.watch(materialsProvider(sessionId));

    return materialsAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(l10n.materialDetailCouldNotLoad(e.toString()))),
      ),
      data: (materials) {
        StudyMaterial? material;
        for (final m in materials) {
          if (m.id == materialId) {
            material = m;
            break;
          }
        }

        if (material == null) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(child: Text(l10n.materialDetailNotFound)),
          );
        }

        return switch (material.kind) {
          MaterialKind.text => _TextView(material: material),
          MaterialKind.photo => _PhotoView(material: material),
          MaterialKind.document => _DocumentView(material: material),
        };
      },
    );
  }
}

// ─── Shared AppBar actions ────────────────────────────────────────────────────

class _MaterialMenu extends ConsumerWidget {
  final StudyMaterial material;
  final Color? iconColor;

  const _MaterialMenu({required this.material, this.iconColor});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, color: iconColor),
      itemBuilder: (_) => [
        PopupMenuItem(value: 'rename', child: Text(l10n.edit)),
        PopupMenuItem(value: 'delete', child: Text(l10n.delete)),
      ],
      onSelected: (value) async {
        if (value == 'rename') {
          await renameMaterial(context, ref, material);
        } else if (value == 'delete') {
          final deleted = await deleteMaterial(context, ref, material);
          if (deleted && context.mounted) {
            context.pop();
          }
        }
      },
    );
  }
}

// ─── Text reader / editor ─────────────────────────────────────────────────────

class _TextView extends ConsumerStatefulWidget {
  final StudyMaterial material;

  const _TextView({required this.material});

  @override
  ConsumerState<_TextView> createState() => _TextViewState();
}

class _TextViewState extends ConsumerState<_TextView> {
  bool _isEditing = false;
  bool _saving = false;
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.material.content);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _enterEditMode() {
    setState(() => _isEditing = true);
    // Request focus after the frame — avoids cursor reset on rebuild.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  Future<void> _handleSave() async {
    final newContent = _controller.text.trim();
    setState(() => _saving = true);
    try {
      await MaterialDAO().update(
        widget.material.copyWith(content: newContent),
      );
      ref.invalidate(materialsProvider(widget.material.sessionId));
      if (mounted) setState(() => _isEditing = false);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _handleCancel() {
    _controller.text = widget.material.content;
    setState(() => _isEditing = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final appBar = _isEditing
        ? AppBar(
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: _saving ? null : _handleCancel,
            ),
            title: Text(
              l10n.materialDetailEditing,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            actions: [
              if (_saving)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: Sp.md),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                TextButton(
                  onPressed: _handleSave,
                  child: Text(
                    l10n.save,
                    style: TextStyle(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          )
        : AppBar(
            title: Text(
              widget.material.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: l10n.edit,
                onPressed: _enterEditMode,
              ),
              _MaterialMenu(material: widget.material),
            ],
          );

    final body = _isEditing
        ? Padding(
            padding: const EdgeInsets.fromLTRB(Sp.md, Sp.md, Sp.md, Sp.md),
            child: Column(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.sentences,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: scheme.onSurface,
                      height: 1.6,
                    ),
                    decoration: InputDecoration(
                      hintText: l10n.materialDetailStartWriting,
                      hintStyle: theme.textTheme.bodyLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.6,
                      ),
                      border: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      isCollapsed: true,
                      filled: false,
                    ),
                  ),
                ),
              ],
            ),
          )
        : SingleChildScrollView(
            padding: Sp.page,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MetaRow(material: widget.material),
                const SizedBox(height: Sp.md),
                MathMarkdownBody(
                  data: widget.material.content.isEmpty
                      ? l10n.materialDetailNoContent
                      : widget.material.content,
                  textStyle: theme.textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurface),
                ),
              ],
            ),
          );

    return Scaffold(
      appBar: appBar,
      body: body,
    );
  }
}

// ─── Photo gallery ────────────────────────────────────────────────────────────

class _PhotoView extends StatefulWidget {
  final StudyMaterial material;

  const _PhotoView({required this.material});

  @override
  State<_PhotoView> createState() => _PhotoViewState();
}

class _PhotoViewState extends State<_PhotoView> {
  late final PageController _controller;
  late final List<String> _paths;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
    _paths = widget.material.content
        .split('\n')
        .where((p) => p.isNotEmpty)
        .toList();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (_paths.isEmpty) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(l10n.materialDetailNoImages)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.35),
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          widget.material.title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          _MaterialMenu(
            material: widget.material,
            iconColor: Colors.white,
          ),
        ],
      ),
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: _paths.length,
            onPageChanged: (i) => setState(() => _currentIndex = i),
            itemBuilder: (_, i) {
              return InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: Hero(
                    tag: 'material-${widget.material.id}-$i',
                    child: Image.file(
                      File(_paths[i]),
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white54,
                        size: 64,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          if (_paths.length > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: Sp.md),
                  child: _PageDots(
                    count: _paths.length,
                    current: _currentIndex,
                  ),
                ),
              ),
            ),
          Positioned(
            right: Sp.md,
            bottom: Sp.md + MediaQuery.of(context).padding.bottom + 32,
            child: _PageCounter(
              current: _currentIndex + 1,
              total: _paths.length,
            ),
          ),
        ],
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  final int count;
  final int current;

  const _PageDots({required this.count, required this.current});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final isActive = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: isActive ? 22 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: isActive
                ? Colors.white
                : Colors.white.withValues(alpha: 0.45),
            borderRadius: Br.full,
          ),
        );
      }),
    );
  }
}

class _PageCounter extends StatelessWidget {
  final int current;
  final int total;

  const _PageCounter({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    if (total <= 1) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: Br.full,
      ),
      child: Text(
        '$current / $total',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ─── Document handoff card ────────────────────────────────────────────────────

class _DocumentView extends StatefulWidget {
  final StudyMaterial material;

  const _DocumentView({required this.material});

  @override
  State<_DocumentView> createState() => _DocumentViewState();
}

class _DocumentViewState extends State<_DocumentView> {
  bool _opening = false;

  String get _path => widget.material.content;
  String get _filename => pathlib.basename(_path);
  String get _extension =>
      pathlib.extension(_path).replaceFirst('.', '').toUpperCase();

  IconData get _icon {
    switch (_extension) {
      case 'PDF':
        return Icons.picture_as_pdf_outlined;
      case 'PPT':
      case 'PPTX':
        return Icons.slideshow_outlined;
      case 'DOC':
      case 'DOCX':
        return Icons.description_outlined;
      case 'TXT':
        return Icons.article_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Future<void> _openExternally() async {
    final l10n = AppLocalizations.of(context)!;
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final result = await OpenFilex.open(_path);
      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.materialDetailCouldNotOpenFile(result.message))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.materialDetailCouldNotOpenFile(e.toString()))),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final file = File(_path);
    final exists = file.existsSync();
    final size = exists ? _formatBytes(file.lengthSync()) : '—';
    final createdOn =
        DateFormat.yMMMMd().add_jm().format(widget.material.createdAt);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.material.title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [_MaterialMenu(material: widget.material)],
      ),
      body: SingleChildScrollView(
        padding: Sp.page,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            QuexPanel(
              padding: const EdgeInsets.symmetric(
                horizontal: Sp.lg,
                vertical: Sp.xl,
              ),
              child: Column(
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: Br.full,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      _icon,
                      size: 44,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: Sp.md),
                  Text(
                    _filename,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: Sp.xs),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: Sp.sm,
                    runSpacing: 4,
                    children: [
                      if (_extension.isNotEmpty) QuexTonePill(label: _extension),
                      QuexTonePill(
                        label: size,
                        color: scheme.tertiary,
                      ),
                    ],
                  ),
                  const SizedBox(height: Sp.lg),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: exists && !_opening ? _openExternally : null,
                      icon: _opening
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.open_in_new),
                      label: Text(
                        _opening ? l10n.materialDetailOpening : l10n.materialDetailOpenExternal,
                      ),
                    ),
                  ),
                  if (!exists) ...[
                    const SizedBox(height: Sp.sm),
                    Text(
                      l10n.materialDetailFileMissing,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: Sp.md),
            _DetailRow(
              icon: Icons.calendar_today_outlined,
              label: l10n.materialDetailAdded,
              value: createdOn,
            ),
            _DetailRow(
              icon: Icons.folder_outlined,
              label: l10n.materialDetailLocation,
              value: _path,
              mono: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool mono;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.mono = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Sp.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: mono ? 'monospace' : null,
                    color: scheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Meta row (text view header) ──────────────────────────────────────────────

class _MetaRow extends StatelessWidget {
  final StudyMaterial material;

  const _MetaRow({required this.material});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final dateLabel = DateFormat.yMMMMd().format(material.createdAt);
    final wordCount = material.content
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .length;

    return Row(
      children: [
        Icon(Icons.edit_note, size: 18, color: scheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(
          '${l10n.materialDetailWords(wordCount)}  ·  $dateLabel',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }
}
