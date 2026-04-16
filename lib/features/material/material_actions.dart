import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/daos.dart';
import '../../core/models/models.dart';
import '../../core/state/app_state.dart';

/// Shared material action helpers used by both the list screen
/// (`material_screen.dart`) and the detail screen (`material_detail_screen.dart`).
///
/// Keeps rename / delete behavior consistent and invalidates the same
/// providers in both places.

/// Shows the rename dialog and persists the new title.
/// Returns the new title on success, `null` if cancelled or unchanged.
Future<String?> renameMaterial(
  BuildContext context,
  WidgetRef ref,
  StudyMaterial material,
) async {
  final newTitle = await showDialog<String>(
    context: context,
    builder: (ctx) => _RenameDialog(initialTitle: material.title),
  );
  if (newTitle == null || newTitle.isEmpty || newTitle == material.title) {
    return null;
  }
  await MaterialDAO().update(material.copyWith(title: newTitle));
  ref.invalidate(materialsProvider(material.sessionId));
  return newTitle;
}

/// Confirms, then deletes the material — including any copied files on disk
/// for photo/document kinds. Returns `true` when deletion succeeded.
Future<bool> deleteMaterial(
  BuildContext context,
  WidgetRef ref,
  StudyMaterial material, {
  bool skipConfirm = false,
}) async {
  if (!skipConfirm) {
    final ok = await _confirmDelete(context);
    if (ok != true) return false;
  }

  // Clean up physical files
  if (material.kind == MaterialKind.photo) {
    for (final p in material.content.split('\n').where((p) => p.isNotEmpty)) {
      try {
        final f = File(p);
        if (await f.exists()) await f.delete();
      } catch (_) {
        // Non-fatal — row removal still proceeds.
      }
    }
  } else if (material.kind == MaterialKind.document) {
    if (material.content.isNotEmpty) {
      try {
        final f = File(material.content);
        if (await f.exists()) await f.delete();
      } catch (_) {
        // Non-fatal.
      }
    }
  }

  await MaterialDAO().delete(material.id!);
  ref.invalidate(materialsProvider(material.sessionId));
  ref.invalidate(sessionBundleProvider(material.sessionId));
  return true;
}

Future<bool?> _confirmDelete(BuildContext ctx) {
  return showDialog<bool>(
    context: ctx,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Delete material?'),
      content: const Text('This note will be permanently removed.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(dialogContext).colorScheme.error,
            foregroundColor: Theme.of(dialogContext).colorScheme.onError,
          ),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
}

class _RenameDialog extends StatefulWidget {
  final String initialTitle;

  const _RenameDialog({required this.initialTitle});

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialTitle);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(labelText: 'Title'),
        onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
