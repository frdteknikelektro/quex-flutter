import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../models/models.dart';

/// A material prepared for LLM consumption: text chunk + preloaded image bytes.
class PreparedMaterial {
  /// "[title]:\n[content]" for text, "[title]" for image-only, empty if skipped.
  final String textChunk;

  /// Preprocessed image bytes (JPEG, max 896×896). Empty for text materials.
  final List<Uint8List> images;

  const PreparedMaterial({required this.textChunk, required this.images});

  static const PreparedMaterial empty = PreparedMaterial(textChunk: '', images: []);
}

/// Prepares study materials for Gemma multimodal inference.
///
/// - [MaterialKind.text] → text chunk only
/// - [MaterialKind.photo] → images resized to ≤896px, JPEG @85%
/// - [MaterialKind.document] → skipped (legacy; not created after PDF-picker flow)
///
/// Total image cap: [totalImageCap] images across all materials (first-N).
class MaterialPreprocessor {
  static const int _maxDimension = 896;
  static const int totalImageCap = 32;

  /// Prepare all materials. Never throws; bad files yield empty PreparedMaterial.
  static Future<List<PreparedMaterial>> prepare(
    List<StudyMaterial> materials,
  ) async {
    final results = <PreparedMaterial>[];
    int imageCount = 0;

    for (final material in materials) {
      switch (material.kind) {
        case MaterialKind.text:
          results.add(await _prepareText(material));

        case MaterialKind.photo:
          final prepared = await _preparePhoto(material, remaining: totalImageCap - imageCount);
          imageCount += prepared.images.length;
          results.add(prepared);

        case MaterialKind.document:
          // Legacy document (pre-PDF-picker). Skip silently.
          results.add(PreparedMaterial.empty);
      }
    }

    return results;
  }

  static Future<PreparedMaterial> _prepareText(StudyMaterial m) async {
    final chunk = '${m.title}:\n${m.content}';
    return PreparedMaterial(textChunk: chunk, images: const []);
  }

  static Future<PreparedMaterial> _preparePhoto(
    StudyMaterial m, {
    required int remaining,
  }) async {
    if (remaining <= 0) {
      return PreparedMaterial(textChunk: m.title, images: const []);
    }

    final paths = m.content.split('\n').where((p) => p.isNotEmpty).toList();
    final images = <Uint8List>[];

    for (final path in paths) {
      if (images.length >= remaining) break;
      try {
        final bytes = await _loadAndResize(path);
        if (bytes != null) images.add(bytes);
      } catch (_) {
        // Skip unreadable file — do not abort generation.
      }
    }

    return PreparedMaterial(textChunk: m.title, images: images);
  }

  /// Load image from [path], resize to max [_maxDimension]px on longest side,
  /// re-encode as JPEG at 85% quality. Returns null if file missing or corrupt.
  static Future<Uint8List?> _loadAndResize(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;

    final raw = await file.readAsBytes();
    final decoded = img.decodeImage(raw);
    if (decoded == null) return null;

    final resized = _needsResize(decoded)
        ? img.copyResize(
            decoded,
            width: decoded.width > decoded.height ? _maxDimension : -1,
            height: decoded.height >= decoded.width ? _maxDimension : -1,
            interpolation: img.Interpolation.linear,
          )
        : decoded;

    return Uint8List.fromList(img.encodeJpg(resized, quality: 85));
  }

  static bool _needsResize(img.Image image) {
    return image.width > _maxDimension || image.height > _maxDimension;
  }
}
