import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:quex/core/ai/material_preprocessor.dart';
import 'package:quex/core/models/models.dart';

void main() {
  test('photo materials are passed through without re-encoding', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('material_preprocessor_test_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final original = img.Image(width: 1200, height: 900);
    final sourceBytes =
        Uint8List.fromList(img.encodeJpg(original, quality: 90));
    final sourceFile = File('${tempDir.path}/photo.jpg');
    await sourceFile.writeAsBytes(sourceBytes, flush: true);

    final materials = [
      StudyMaterial(
        sessionId: 1,
        kind: MaterialKind.photo,
        title: 'Photo',
        content: sourceFile.path,
        pageIndex: 0,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      ),
    ];

    final prepared = await MaterialPreprocessor.prepare(materials);

    expect(prepared, hasLength(1));
    expect(prepared.single.textChunk, 'Photo');
    expect(prepared.single.images, hasLength(1));
    expect(prepared.single.images.single, sourceBytes);
  });
}
