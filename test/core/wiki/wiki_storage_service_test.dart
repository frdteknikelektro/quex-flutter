import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quex/core/ai/wiki_storage_service.dart';

void main() {
  group('WikiStorageService', () {
    late Directory tempDir;
    late WikiStorageService service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('quex-wiki-test-');
      service =
          WikiStorageService(documentsDirectoryProvider: () async => tempDir);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('writes markdown with inferred frontmatter and reads it back',
        () async {
      final entry = await service.writeMarkdownFile(
        sessionId: 7,
        relativePath: 'concepts/water-cycle',
        content: '# Water Cycle\n\nEvaporation and condensation.',
      );

      expect(entry.relativePath, 'concepts/water-cycle.md');
      expect(entry.category, 'concepts');
      expect(entry.title, 'Water Cycle');
      expect(entry.frontmatter['sessionId'], 7);

      final reread = await service.readEntry(7, 'concepts/water-cycle.md');
      expect(reread, isNotNull);
      expect(reread!.body, contains('Evaporation and condensation.'));
    });

    test('buildTree keeps root order index, log, then categories', () async {
      await service.writeMarkdownFile(
        sessionId: 9,
        relativePath: 'index.md',
        content: '# Index',
      );
      await service.writeMarkdownFile(
        sessionId: 9,
        relativePath: 'log.md',
        content: '# Log',
      );
      await service.writeMarkdownFile(
        sessionId: 9,
        relativePath: 'sources/alpha.md',
        content: '# Alpha',
      );
      await service.writeMarkdownFile(
        sessionId: 9,
        relativePath: 'reviews/lint.md',
        content: '# Review',
      );

      final tree = await service.buildTree(9);

      expect(tree.map((node) => node.relativePath).toList(), [
        'index.md',
        'log.md',
        'sources',
        'reviews',
      ]);
      expect(tree[2].children.single.relativePath, 'sources/alpha.md');
      expect(tree[3].children.single.relativePath, 'reviews/lint.md');
    });

    test('clearSessionWiki removes all existing markdown files', () async {
      await service.writeMarkdownFile(
        sessionId: 11,
        relativePath: 'index.md',
        content: '# Index',
      );
      await service.writeMarkdownFile(
        sessionId: 11,
        relativePath: 'concepts/force.md',
        content: '# Force',
      );

      expect(await service.hasWiki(11), isTrue);

      await service.clearSessionWiki(11);

      expect(await service.hasWiki(11), isFalse);
      final root = await service.sessionRootDirectory(11);
      expect(await root.exists(), isTrue);
    });

    test('rejects paths outside wiki root', () {
      expect(
        () => service.normalizeRelativePath('../evil.md'),
        throwsFormatException,
      );
      expect(
        () => service.normalizeRelativePath('random/evil.md'),
        throwsFormatException,
      );
    });
  });

  group('wiki markdown parser', () {
    test('extracts headings and strips frontmatter', () {
      const markdown = '''---
title: "Index"
---
# Home

## Sources

### Photos
''';

      final headings = extractWikiHeadings(markdown);
      expect(headings.map((item) => item.title).toList(), [
        'Home',
        'Sources',
        'Photos',
      ]);
      expect(stripWikiFrontmatter(markdown).trimLeft(), startsWith('# Home'));
    });
  });
}
