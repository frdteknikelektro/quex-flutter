import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as pathlib;
import 'package:uuid/uuid.dart';

class NormalizedImage {
  final Uint8List bytes;
  final File? file;

  const NormalizedImage({
    required this.bytes,
    this.file,
  });
}

/// Normalizes image files before persistence.
///
/// The normalized output is JPEG, capped at [maxDimension] on the longest
/// side, and never upscales smaller inputs.
class ImageNormalizer {
  static const int maxDimension = 896;
  static const int jpegQuality = 85;

  static Future<NormalizedImage?> normalizeFile(
    File source, {
    Directory? outputDirectory,
    String? fileStem,
    int maxDimension = ImageNormalizer.maxDimension,
    int quality = jpegQuality,
  }) async {
    final bytes = await normalizeBytesFromFile(
      source,
      maxDimension: maxDimension,
      quality: quality,
    );
    if (bytes == null) return null;

    final targetDir = outputDirectory;
    if (targetDir == null) {
      return NormalizedImage(bytes: bytes);
    }

    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final normalizedStem = _sanitizeStem(
      fileStem ?? pathlib.basenameWithoutExtension(source.path),
    );
    final dest = File(
      '${targetDir.path}/${const Uuid().v4()}_$normalizedStem.jpg',
    );
    await dest.writeAsBytes(bytes, flush: true);
    return NormalizedImage(bytes: bytes, file: dest);
  }

  static Future<Uint8List?> normalizeBytesFromFile(
    File source, {
    int maxDimension = ImageNormalizer.maxDimension,
    int quality = jpegQuality,
  }) async {
    if (!await source.exists()) return null;

    final raw = await source.readAsBytes();
    final decoded = img.decodeImage(raw);
    if (decoded != null) {
      return _encodeNormalized(decoded,
          maxDimension: maxDimension, quality: quality);
    }

    final compressed = await _compressNative(
      source.path,
      maxDimension: maxDimension,
      quality: quality,
    );
    if (compressed == null || compressed.isEmpty) return null;

    final compressedDecoded = img.decodeImage(compressed);
    if (compressedDecoded == null) return compressed;

    return _encodeNormalized(
      compressedDecoded,
      maxDimension: maxDimension,
      quality: quality,
    );
  }

  static Uint8List _encodeNormalized(
    img.Image source, {
    required int maxDimension,
    required int quality,
  }) {
    final oriented = img.bakeOrientation(source);
    final resized = _needsResize(oriented, maxDimension)
        ? _resizeToLongestSide(oriented, maxDimension)
        : oriented;

    return Uint8List.fromList(img.encodeJpg(resized, quality: quality));
  }

  static Future<Uint8List?> _compressNative(
    String path, {
    required int maxDimension,
    required int quality,
  }) async {
    try {
      final compressed = await FlutterImageCompress.compressWithFile(
        path,
        minWidth: maxDimension,
        minHeight: maxDimension,
        quality: quality,
        format: CompressFormat.jpeg,
      );
      if (compressed == null || compressed.isEmpty) return null;
      return compressed;
    } catch (_) {
      return null;
    }
  }

  static img.Image _resizeToLongestSide(img.Image source, int maxDimension) {
    if (source.width >= source.height) {
      return img.copyResize(
        source,
        width: maxDimension,
        interpolation: img.Interpolation.linear,
      );
    }

    return img.copyResize(
      source,
      height: maxDimension,
      interpolation: img.Interpolation.linear,
    );
  }

  static bool _needsResize(img.Image source, int maxDimension) {
    return source.width > maxDimension || source.height > maxDimension;
  }

  static String _sanitizeStem(String stem) {
    final cleaned = stem.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    return cleaned.isEmpty ? 'image' : cleaned;
  }
}
