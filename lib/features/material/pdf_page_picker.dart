import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:uuid/uuid.dart';

import '../../app/theme.dart';

/// Full-screen modal that lets users pick pages from a PDF file.
///
/// Opens [pdfPath], renders thumbnail previews for all pages (none selected by
/// default), and lets users tap to select the pages they want.
///
/// On confirm, renders selected pages at up to [_fullResMaxPx] pixels on the
/// longest side, saves them as JPEG files in the app's materials directory,
/// and returns the list of written paths.
///
/// Returns `null` if the user cancels or no pages are selected.
class PdfPagePickerModal extends StatefulWidget {
  final String pdfPath;
  final String suggestedTitle;

  const PdfPagePickerModal({
    super.key,
    required this.pdfPath,
    required this.suggestedTitle,
  });

  @override
  State<PdfPagePickerModal> createState() => _PdfPagePickerModalState();
}

class _PdfPagePickerModalState extends State<PdfPagePickerModal> {
  static const int _thumbPx = 200;
  static const int _fullResMaxPx = 896;

  PdfDocument? _document;
  final List<Uint8List?> _thumbnails = [];
  final Set<int> _selected = {};
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDocument();
  }

  @override
  void dispose() {
    _document?.close();
    super.dispose();
  }

  Future<void> _loadDocument() async {
    try {
      final doc = await PdfDocument.openFile(widget.pdfPath);
      _document = doc;

      final thumbs = List<Uint8List?>.filled(doc.pagesCount, null);

      // Render thumbnails sequentially (Android doesn't allow parallel rendering)
      for (var i = 0; i < doc.pagesCount; i++) {
        final page = await doc.getPage(i + 1);
        final ratio = page.height / page.width;
        final thumbW = _thumbPx.toDouble();
        final thumbH = thumbW * ratio;
        final image = await page.render(
          width: thumbW,
          height: thumbH,
          format: PdfPageImageFormat.jpeg,
          quality: 70,
          backgroundColor: '#FFFFFF',
        );
        await page.close();
        if (image != null) thumbs[i] = image.bytes;
      }

      if (mounted) {
        setState(() {
          _thumbnails
            ..clear()
            ..addAll(thumbs);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not open PDF: $e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _confirm() async {
    if (_selected.isEmpty) return;

    setState(() => _saving = true);
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final dir = Directory('${appDir.path}/materials');
      if (!await dir.exists()) await dir.create(recursive: true);

      final paths = <String>[];
      final doc = _document!;
      final sortedPages = _selected.toList()..sort();

      for (final pageIndex in sortedPages) {
        final page = await doc.getPage(pageIndex + 1);
        final ratio = page.height / page.width;

        double renderW, renderH;
        if (page.width >= page.height) {
          renderW = _fullResMaxPx.toDouble();
          renderH = renderW * ratio;
        } else {
          renderH = _fullResMaxPx.toDouble();
          renderW = renderH / ratio;
        }

        final image = await page.render(
          width: renderW,
          height: renderH,
          format: PdfPageImageFormat.jpeg,
          quality: 85,
          backgroundColor: '#FFFFFF',
        );
        await page.close();

        if (image != null) {
          final filename = '${const Uuid().v4()}_page_${pageIndex + 1}.jpg';
          final dest = '${dir.path}/$filename';
          await File(dest).writeAsBytes(image.bytes);
          paths.add(dest);
        }
      }

      if (mounted) Navigator.of(context).pop(paths);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to save pages: $e';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.suggestedTitle,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis,
            ),
            if (_document != null && !_loading)
              Text(
                '${_document!.pagesCount} pages — tap to select',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _saving ? null : () => Navigator.of(context).pop(null),
        ),
      ),
      body: _buildBody(scheme, theme),
      bottomNavigationBar: _buildBottomBar(scheme, theme),
    );
  }

  Widget _buildBody(ColorScheme scheme, ThemeData theme) {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: Sp.md),
            Text('Loading pages...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: Sp.page,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: scheme.error),
              const SizedBox(height: Sp.md),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.error),
              ),
            ],
          ),
        ),
      );
    }

    return GridView.builder(
      padding: Sp.page,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: Sp.sm,
        mainAxisSpacing: Sp.sm,
        childAspectRatio: 0.75,
      ),
      itemCount: _thumbnails.length,
      itemBuilder: (context, i) => _PageTile(
        pageNumber: i + 1,
        thumbnailBytes: _thumbnails[i],
        isSelected: _selected.contains(i),
        onTap: () {
          setState(() {
            if (_selected.contains(i)) {
              _selected.remove(i);
            } else {
              _selected.add(i);
            }
          });
        },
        scheme: scheme,
        theme: theme,
      ),
    );
  }

  Widget _buildBottomBar(ColorScheme scheme, ThemeData theme) {
    final count = _selected.length;
    return SafeArea(
      child: Padding(
        padding: Sp.edge,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null && _saving == false)
              Padding(
                padding: const EdgeInsets.only(bottom: Sp.sm),
                child: Text(
                  _error!,
                  style: theme.textTheme.labelSmall?.copyWith(color: scheme.error),
                  textAlign: TextAlign.center,
                ),
              ),
            FilledButton(
              onPressed: (!_saving && count > 0) ? _confirm : null,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(count == 0 ? 'Select pages to continue' : 'Add $count page${count == 1 ? '' : 's'}'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Page thumbnail tile ──────────────────────────────────────────────────────

class _PageTile extends StatelessWidget {
  final int pageNumber;
  final Uint8List? thumbnailBytes;
  final bool isSelected;
  final VoidCallback onTap;
  final ColorScheme scheme;
  final ThemeData theme;

  const _PageTile({
    required this.pageNumber,
    required this.thumbnailBytes,
    required this.isSelected,
    required this.onTap,
    required this.scheme,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: Br.md,
          border: Border.all(
            color: isSelected ? scheme.primary : scheme.outlineVariant,
            width: isSelected ? 2.5 : 1,
          ),
          color: isSelected ? scheme.primaryContainer.withValues(alpha: 0.2) : scheme.surfaceContainerHighest,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Thumbnail image or placeholder
              if (thumbnailBytes != null)
                Image.memory(thumbnailBytes!, fit: BoxFit.cover)
              else
                Center(
                  child: Icon(
                    Icons.picture_as_pdf_outlined,
                    size: 32,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              // Page number label at bottom
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  color: Colors.black54,
                  child: Text(
                    'Page $pageNumber',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              // Checkmark overlay when selected
              if (isSelected)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check,
                      size: 14,
                      color: scheme.onPrimary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
