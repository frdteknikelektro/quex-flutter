import 'wiki_models.dart';

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

String stripWikiFrontmatter(String content) {
  final normalized = content.replaceAll('\r\n', '\n');
  if (!normalized.startsWith('---\n')) return normalized;
  final endIndex = normalized.indexOf('\n---\n', 4);
  if (endIndex == -1) return normalized;
  return normalized.substring(endIndex + 5);
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

String _slugify(String input) {
  final lower = input.toLowerCase().trim();
  final sanitized = lower.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  return sanitized.replaceAll(RegExp(r'^-+|-+$'), '').isEmpty
      ? 'section'
      : sanitized.replaceAll(RegExp(r'^-+|-+$'), '');
}
