import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:quex/core/utils/image_normalizer.dart';

Future<File> _writeJpegImage(
  Directory dir,
  String name, {
  required int width,
  required int height,
}) async {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(220, 40, 40));

  final file = File('${dir.path}/$name');
  await file.writeAsBytes(img.encodeJpg(image, quality: 95));
  return file;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flutter_image_compress');

  group('ImageNormalizer', () {
    test('normalizes large images to a 896px longest side', () async {
      final tempDir =
          Directory.systemTemp.createTempSync('image-normalizer-large-');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final source = await _writeJpegImage(
        tempDir,
        'large.jpg',
        width: 1600,
        height: 800,
      );

      final normalized = await ImageNormalizer.normalizeFile(
        source,
        outputDirectory: tempDir,
        fileStem: 'large_photo',
      );

      expect(normalized, isNotNull);
      expect(normalized!.file, isNotNull);
      expect(normalized.file!.existsSync(), isTrue);
      expect(normalized.file!.path, endsWith('.png'));

      final decoded = img.decodeImage(await normalized.file!.readAsBytes());
      expect(decoded, isNotNull);
      expect(decoded!.width, 896);
      expect(decoded.height, 448);
    });

    test('does not upscale smaller images', () async {
      final tempDir =
          Directory.systemTemp.createTempSync('image-normalizer-small-');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final source = await _writeJpegImage(
        tempDir,
        'small.jpg',
        width: 400,
        height: 200,
      );

      final normalized = await ImageNormalizer.normalizeFile(
        source,
        outputDirectory: tempDir,
        fileStem: 'small_photo',
      );

      expect(normalized, isNotNull);
      expect(normalized!.file, isNotNull);

      final decoded = img.decodeImage(await normalized.file!.readAsBytes());
      expect(decoded, isNotNull);
      expect(decoded!.width, 400);
      expect(decoded.height, 200);
    });

    test('falls back to native compression for unsupported source formats',
        () async {
      final tempDir =
          Directory.systemTemp.createTempSync('image-normalizer-heic-');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final source = File('${tempDir.path}/source.heic');
      await source.writeAsBytes(Uint8List.fromList([1, 2, 3, 4, 5]));

      final fallbackBytes = img.encodeJpg(
        img.fill(
          img.Image(width: 1600, height: 800),
          color: img.ColorRgb8(60, 90, 220),
        ),
        quality: 95,
      );

      int calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls++;
        expect(call.method, 'compressWithFile');
        final args = call.arguments as List<dynamic>;
        expect(args[0], source.path);
        expect(args[1], ImageNormalizer.maxDimension);
        expect(args[2], ImageNormalizer.maxDimension);
        return fallbackBytes;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final normalized = await ImageNormalizer.normalizeFile(
        source,
        outputDirectory: tempDir,
        fileStem: 'heic_source',
      );

      expect(normalized, isNotNull);
      expect(calls, 1);
      expect(normalized!.file, isNotNull);
      expect(normalized.file!.existsSync(), isTrue);
      expect(normalized.file!.path, endsWith('.png'));

      final decoded = img.decodeImage(await normalized.file!.readAsBytes());
      expect(decoded, isNotNull);
      expect(decoded!.width, 896);
      expect(decoded.height, 448);
    });
  });
}
