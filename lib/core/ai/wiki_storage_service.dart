import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// Wiki models — kept here to avoid a separate file for now
enum WikiNodeType { file, directory }

enum WikiActionStatus { idle, loadingModel, running, success, error }

enum WikiRunType { ingest, lint }

@immutable
class WikiHeading {
  final int level;
  final String title;
  final String anchor;

  const WikiHeading({
    required this.level,
    required this.title,
    required this.anchor,
  });
}

@immutable
class WikiEntry {
  final String relativePath;
  final String title;
  final String category;
  final String slug;
  final String rawContent;
  final String body;
  final List<int> materialIds;
  final DateTime updatedAt;
  final Map<String, Object?> frontmatter;

  const WikiEntry({
    required this.relativePath,
    required this.title,
    required this.category,
    required this.slug,
    required this.rawContent,
    required this.body,
    required this.materialIds,
    required this.updatedAt,
    required this.frontmatter,
  });
}

@immutable
class WikiTreeNode {
  final String name;
  final String relativePath;
  final String displayTitle;
  final WikiNodeType type;
  final List<WikiTreeNode> children;

  const WikiTreeNode({
    required this.name,
    required this.relativePath,
    required this.displayTitle,
    required this.type,
    this.children = const [],
  });

  bool get isDirectory => type == WikiNodeType.directory;
  bool get isFile => type == WikiNodeType.file;
}

@immutable
class WikiActionState {
  final WikiActionStatus status;
  final WikiRunType? runType;
  final List<String> lines;
  final String? error;
  final List<String> touchedPaths;
  final DateTime? startedAt;
  final DateTime? completedAt;

  const WikiActionState({
    required this.status,
    this.runType,
    this.lines = const [],
    this.error,
    this.touchedPaths = const [],
    this.startedAt,
    this.completedAt,
  });

  const WikiActionState.idle()
      : status = WikiActionStatus.idle,
        runType = null,
        lines = const [],
        error = null,
        touchedPaths = const [],
        startedAt = null,
        completedAt = null;

  bool get isBusy =>
      status == WikiActionStatus.loadingModel ||
      status == WikiActionStatus.running;

  bool get isSuccess => status == WikiActionStatus.success;
  bool get hasError => status == WikiActionStatus.error;

  WikiActionState copyWith({
    WikiActionStatus? status,
    WikiRunType? runType,
    List<String>? lines,
    String? error,
    List<String>? touchedPaths,
    DateTime? startedAt,
    DateTime? completedAt,
  }) {
    return WikiActionState(
      status: status ?? this.status,
      runType: runType ?? this.runType,
      lines: lines ?? this.lines,
      error: error ?? this.error,
      touchedPaths: touchedPaths ?? this.touchedPaths,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}

@immutable
class WikiPageRequest {
  final int sessionId;
  final String relativePath;

  const WikiPageRequest({
    required this.sessionId,
    required this.relativePath,
  });

  @override
  bool operator ==(Object other) {
    return other is WikiPageRequest &&
        other.sessionId == sessionId &&
        other.relativePath == relativePath;
  }

  @override
  int get hashCode => Object.hash(sessionId, relativePath);
}

// MARK: - Markdown parser

String stripWikiFrontmatter(String content) {
  final normalized = content.replaceAll('\r\n', '\n');
  if (!normalized.startsWith('---\n')) return normalized;
  final endIndex = normalized.indexOf('\n---\n', 4);
  if (endIndex == -1) return normalized;
  return normalized.substring(endIndex + 5);
}

List<WikiHeading> extractWikiHeadings(String content) {
  final headings = <WikiHeading>[];
  final seenAnchors = <String, int>{};

  for (final line in stripWikiFrontmatter(content).split('\n')) {
    final match = RegExp(r'^(#{1,3})\s+(.+?)\s*$').firstMatch(line);
    if (match == null) continue;
    final title = match.group(2)!.trim();
    final baseAnchor = _slugify(title);
    final seen =
        seenAnchors.update(baseAnchor, (value) => value + 1, ifAbsent: () => 0);
    final anchor = seen == 0 ? baseAnchor : '$baseAnchor-$seen';
    headings.add(
      WikiHeading(
        level: match.group(1)!.length,
        title: title,
        anchor: anchor,
      ),
    );
  }

  return headings;
}

String prepareWikiMarkdown(String content) {
  final stripped = stripWikiFrontmatter(content);
  final lines = stripped.split('\n');
  final buffer = StringBuffer();
  final blockPattern = RegExp(r'^\s*([-*+]|\d+\.|>|```|#{1,6}\s)');

  for (var i = 0; i < lines.length; i++) {
    buffer.write(lines[i]);
    if (i < lines.length - 1) {
      final current = lines[i];
      final next = lines[i + 1];
      final currentIsBlock = current.isEmpty || blockPattern.hasMatch(current);
      final nextIsBlock = next.isEmpty || blockPattern.hasMatch(next);
      buffer.write(currentIsBlock || nextIsBlock ? '\n' : '\n\n');
    }
  }

  return buffer.toString().trim();
}

List<WikiMarkdownSection> splitWikiSections(String content) {
  final stripped = stripWikiFrontmatter(content).trim();
  if (stripped.isEmpty) return const [];

  final lines = stripped.split('\n');
  final sections = <WikiMarkdownSection>[];
  final buffer = <String>[];
  String? currentTitle;
  int? currentLevel;
  var currentId = 'overview';
  var introCount = 0;

  void flush() {
    if (buffer.isEmpty) return;
    sections.add(
      WikiMarkdownSection(
        id: currentId,
        title: currentTitle,
        level: currentLevel,
        markdown: buffer.join('\n').trim(),
      ),
    );
    buffer.clear();
  }

  for (final line in lines) {
    final match = RegExp(r'^(#{1,3})\s+(.+?)\s*$').firstMatch(line);
    if (match != null) {
      flush();
      currentLevel = match.group(1)!.length;
      currentTitle = match.group(2)!.trim();
      currentId = _slugify(currentTitle);
      buffer.add(line);
      continue;
    }

    if (currentTitle == null && buffer.isEmpty && line.trim().isNotEmpty) {
      currentId = introCount == 0 ? 'overview' : 'overview-$introCount';
      introCount++;
    }
    buffer.add(line);
  }

  flush();
  return sections;
}

class WikiMarkdownSection {
  final String id;
  final String? title;
  final int? level;
  final String markdown;

  const WikiMarkdownSection({
    required this.id,
    required this.markdown,
    this.title,
    this.level,
  });
}

String _slugify(String input) {
  final lower = input.toLowerCase().trim();
  final sanitized = lower.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  return sanitized.replaceAll(RegExp(r'^-+|-+$'), '').isEmpty
      ? 'section'
      : sanitized.replaceAll(RegExp(r'^-+|-+$'), '');
}

typedef DocumentsDirectoryProvider = Future<Directory> Function();

class WikiStorageService {
  WikiStorageService({
    DocumentsDirectoryProvider? documentsDirectoryProvider,
  }) : _documentsDirectoryProvider =
            documentsDirectoryProvider ?? getApplicationDocumentsDirectory;

  final DocumentsDirectoryProvider _documentsDirectoryProvider;

  static const List<String> orderedDirectories = [
    'sources',
    'concepts',
    'entities',
    'syntheses',
    'reviews',
  ];

  static const List<String> rootFiles = ['index.md', 'log.md'];

  Future<Directory> documentsDirectory() => _documentsDirectoryProvider();

  Future<Directory> wikiRootDirectory() async {
    final docs = await documentsDirectory();
    return Directory(p.join(docs.path, 'wiki'));
  }

  Future<Directory> sessionRootDirectory(int sessionId) async {
    final wikiRoot = await wikiRootDirectory();
    return Directory(p.join(wikiRoot.path, 'session_$sessionId'));
  }

  Future<List<String>> listMarkdownPaths(int sessionId) async {
    final root = await sessionRootDirectory(sessionId);
    if (!await root.exists()) return const [];

    final files = <String>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.md')) continue;
      files.add(_relativePath(root.path, entity.path));
    }
    files.sort(_compareRelativePaths);
    return files;
  }

  Future<bool> hasWiki(int sessionId) async {
    final paths = await listMarkdownPaths(sessionId);
    return paths.isNotEmpty;
  }

  Future<List<WikiEntry>> readAllEntries(int sessionId) async {
    final paths = await listMarkdownPaths(sessionId);
    final entries = <WikiEntry>[];
    for (final relativePath in paths) {
      final entry = await readEntry(sessionId, relativePath);
      if (entry != null) entries.add(entry);
    }
    return entries;
  }

  Future<WikiEntry?> readEntry(int sessionId, String relativePath) async {
    final root = await sessionRootDirectory(sessionId);
    final normalized = normalizeRelativePath(relativePath);
    final file = _resolveAllowedFile(root, normalized);
    if (!await file.exists()) return null;
    final content = await file.readAsString();
    final stat = await file.stat();
    return _parseEntry(
      sessionId: sessionId,
      relativePath: normalized,
      content: content,
      updatedAt: stat.modified,
    );
  }

  Future<List<WikiTreeNode>> buildTree(int sessionId) async {
    final entries = await readAllEntries(sessionId);
    if (entries.isEmpty) return const [];

    final root = <_MutableTreeNode>[];
    for (final entry in entries) {
      final parts = p.posix.split(entry.relativePath);
      var currentLevel = root;
      var accumulated = '';

      for (var index = 0; index < parts.length; index++) {
        final part = parts[index];
        accumulated = accumulated.isEmpty ? part : '$accumulated/$part';
        final isDirectory = index < parts.length - 1;
        _MutableTreeNode? node;
        for (final existing in currentLevel) {
          if (existing.name == part && existing.isDirectory == isDirectory) {
            node = existing;
            break;
          }
        }
        node ??= _MutableTreeNode(
          name: part,
          relativePath: accumulated,
          displayTitle: isDirectory ? _titleCase(part) : entry.title,
          isDirectory: isDirectory,
        );
        if (!currentLevel.contains(node)) currentLevel.add(node);
        if (!isDirectory) {
          node.displayTitle = entry.title;
        }
        currentLevel = node.children;
      }
    }

    _sortNodes(root, isRoot: true);
    return root.map((node) => node.toImmutable()).toList(growable: false);
  }

  Future<WikiEntry> writeMarkdownFile({
    required int sessionId,
    required String relativePath,
    required String content,
  }) async {
    final root = await sessionRootDirectory(sessionId);
    await root.create(recursive: true);
    final normalized = normalizeRelativePath(relativePath);
    final file = _resolveAllowedFile(root, normalized);
    await file.parent.create(recursive: true);
    final withFrontmatter = _ensureFrontmatter(
      sessionId: sessionId,
      relativePath: normalized,
      content: content,
    );
    await file.writeAsString(withFrontmatter);
    final stat = await file.stat();
    return _parseEntry(
      sessionId: sessionId,
      relativePath: normalized,
      content: withFrontmatter,
      updatedAt: stat.modified,
    );
  }

  Future<void> deleteMarkdownFile({
    required int sessionId,
    required String relativePath,
  }) async {
    final root = await sessionRootDirectory(sessionId);
    final normalized = normalizeRelativePath(relativePath);
    final file = _resolveAllowedFile(root, normalized);
    if (await file.exists()) {
      await file.delete();
    }
  }

  String normalizeRelativePath(String rawPath) {
    var normalized = rawPath.trim().replaceAll('\\', '/');
    if (normalized.isEmpty) {
      throw const FormatException('Path is required.');
    }
    if (!normalized.endsWith('.md')) {
      normalized = '$normalized.md';
    }
    normalized = p.posix.normalize(normalized);
    normalized = normalized.replaceFirst(RegExp(r'^/+'), '');
    if (normalized == '.' ||
        normalized == '..' ||
        normalized.startsWith('../')) {
      throw FormatException('Path escapes wiki root: $rawPath');
    }

    final parts = p.posix.split(normalized);
    if (parts.any((part) => part == '..' || part.isEmpty)) {
      throw FormatException('Invalid wiki path: $rawPath');
    }

    if (parts.length == 1) {
      if (!rootFiles.contains(parts.first)) {
        throw FormatException('Unsupported wiki root file: $rawPath');
      }
      return normalized;
    }

    if (!orderedDirectories.contains(parts.first)) {
      throw FormatException('Unsupported wiki directory: ${parts.first}');
    }
    return normalized;
  }

  WikiEntry _parseEntry({
    required int sessionId,
    required String relativePath,
    required String content,
    required DateTime updatedAt,
  }) {
    final split = _splitFrontmatter(content);
    final frontmatter = _parseFrontmatter(split.frontmatter);
    final title = (frontmatter['title'] as String?) ??
        _inferTitle(relativePath, split.body);
    final category =
        (frontmatter['category'] as String?) ?? _inferCategory(relativePath);
    final slug = (frontmatter['slug'] as String?) ??
        p.basenameWithoutExtension(relativePath);
    final materialIds = _parseMaterialIds(frontmatter['materialIds']);

    return WikiEntry(
      relativePath: relativePath,
      title: title,
      category: category,
      slug: slug,
      rawContent: content,
      body: split.body.trim(),
      materialIds: materialIds,
      updatedAt: updatedAt,
      frontmatter: frontmatter,
    );
  }

  File _resolveAllowedFile(Directory root, String relativePath) {
    final absolutePath = p.normalize(p.join(root.path, relativePath));
    final relativeToRoot = p.relative(absolutePath, from: root.path);
    if (relativeToRoot == '..' || relativeToRoot.startsWith('../')) {
      throw FormatException('Path escapes wiki root: $relativePath');
    }
    return File(absolutePath);
  }

  String _ensureFrontmatter({
    required int sessionId,
    required String relativePath,
    required String content,
  }) {
    final split = _splitFrontmatter(content);
    if (split.frontmatter.isNotEmpty) return content;

    final inferredTitle = _inferTitle(relativePath, split.body);
    final inferredCategory = _inferCategory(relativePath);
    final slug = p.basenameWithoutExtension(relativePath);

    final metadata = <String, Object?>{
      'title': inferredTitle,
      'category': inferredCategory,
      'slug': slug,
      'sessionId': sessionId,
      'materialIds': const <int>[],
      'updatedAt': DateTime.now().toIso8601String(),
    };

    return '${_stringifyFrontmatter(metadata)}\n${split.body.trim()}';
  }

  _FrontmatterSplit _splitFrontmatter(String content) {
    final normalized = content.replaceAll('\r\n', '\n');
    if (!normalized.startsWith('---\n')) {
      return _FrontmatterSplit(frontmatter: '', body: normalized);
    }
    final end = normalized.indexOf('\n---\n', 4);
    if (end == -1) {
      return _FrontmatterSplit(frontmatter: '', body: normalized);
    }
    return _FrontmatterSplit(
      frontmatter: normalized.substring(4, end),
      body: normalized.substring(end + 5),
    );
  }

  Map<String, Object?> _parseFrontmatter(String frontmatter) {
    final map = <String, Object?>{};
    if (frontmatter.trim().isEmpty) return map;

    for (final rawLine in frontmatter.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || !line.contains(':')) continue;
      final separator = line.indexOf(':');
      final key = line.substring(0, separator).trim();
      final rawValue = line.substring(separator + 1).trim();
      map[key] = _parseFrontmatterValue(rawValue);
    }
    return map;
  }

  Object? _parseFrontmatterValue(String rawValue) {
    if (rawValue.isEmpty) return '';
    if (rawValue.startsWith('[') && rawValue.endsWith(']')) {
      final body = rawValue.substring(1, rawValue.length - 1).trim();
      if (body.isEmpty) return const <Object?>[];
      return body
          .split(',')
          .map((item) => _parseFrontmatterValue(item.trim()))
          .toList(growable: false);
    }
    if ((rawValue.startsWith('"') && rawValue.endsWith('"')) ||
        (rawValue.startsWith("'") && rawValue.endsWith("'"))) {
      return rawValue.substring(1, rawValue.length - 1);
    }
    final intValue = int.tryParse(rawValue);
    if (intValue != null) return intValue;
    final boolValue = switch (rawValue.toLowerCase()) {
      'true' => true,
      'false' => false,
      _ => null,
    };
    return boolValue ?? rawValue;
  }

  List<int> _parseMaterialIds(Object? rawValue) {
    if (rawValue is List) {
      return rawValue
          .map((item) => switch (item) {
                int value => value,
                String value => int.tryParse(value),
                _ => null,
              })
          .whereType<int>()
          .toList(growable: false);
    }
    return const [];
  }

  String _stringifyFrontmatter(Map<String, Object?> metadata) {
    final lines = <String>['---'];
    metadata.forEach((key, value) {
      lines.add('$key: ${_formatFrontmatterValue(value)}');
    });
    lines.add('---');
    return lines.join('\n');
  }

  String _formatFrontmatterValue(Object? value) {
    if (value is List) {
      return '[${value.map(_formatFrontmatterValue).join(', ')}]';
    }
    if (value is String) {
      final escaped = value.replaceAll('"', '\\"');
      return '"$escaped"';
    }
    return '$value';
  }

  String _inferTitle(String relativePath, String body) {
    for (final line in body.split('\n')) {
      final match = RegExp(r'^#\s+(.+?)\s*$').firstMatch(line.trim());
      if (match != null) return match.group(1)!.trim();
    }
    return _titleCase(
      p.basenameWithoutExtension(relativePath).replaceAll('-', ' '),
    );
  }

  String _inferCategory(String relativePath) {
    final parts = p.posix.split(relativePath);
    if (parts.length == 1) return 'meta';
    return parts.first;
  }

  void _sortNodes(List<_MutableTreeNode> nodes, {required bool isRoot}) {
    for (final node in nodes) {
      if (node.isDirectory) {
        _sortNodes(node.children, isRoot: false);
      }
    }

    nodes.sort((a, b) {
      if (isRoot) {
        final aRank = _rootRank(a);
        final bRank = _rootRank(b);
        if (aRank != bRank) return aRank.compareTo(bRank);
      } else if (a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }

      return a.displayTitle
          .toLowerCase()
          .compareTo(b.displayTitle.toLowerCase());
    });
  }

  int _rootRank(_MutableTreeNode node) {
    if (!node.isDirectory) {
      final fileRank = rootFiles.indexOf(node.name);
      if (fileRank != -1) return fileRank;
      return 100;
    }
    final dirRank = orderedDirectories.indexOf(node.name);
    return dirRank == -1 ? 100 : dirRank + 10;
  }

  String _relativePath(String from, String to) {
    return p.relative(to, from: from).split(Platform.pathSeparator).join('/');
  }

  static int _compareRelativePaths(String a, String b) {
    int rank(String path) {
      if (path == 'index.md') return 0;
      if (path == 'log.md') return 1;
      final segment = p.posix.split(path).first;
      final dirRank = orderedDirectories.indexOf(segment);
      return dirRank == -1 ? 100 : dirRank + 10;
    }

    final aRank = rank(a);
    final bRank = rank(b);
    if (aRank != bRank) return aRank.compareTo(bRank);
    return a.compareTo(b);
  }

  String _titleCase(String value) {
    return value
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .map((part) =>
            '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}')
        .join(' ');
  }
}

class _FrontmatterSplit {
  final String frontmatter;
  final String body;

  const _FrontmatterSplit({
    required this.frontmatter,
    required this.body,
  });
}

class _MutableTreeNode {
  _MutableTreeNode({
    required this.name,
    required this.relativePath,
    required this.displayTitle,
    required this.isDirectory,
  });

  final String name;
  final String relativePath;
  String displayTitle;
  final bool isDirectory;
  final List<_MutableTreeNode> children = [];

  WikiTreeNode toImmutable() {
    return WikiTreeNode(
      name: name,
      relativePath: relativePath,
      displayTitle: displayTitle,
      type: isDirectory ? WikiNodeType.directory : WikiNodeType.file,
      children:
          children.map((child) => child.toImmutable()).toList(growable: false),
    );
  }
}
