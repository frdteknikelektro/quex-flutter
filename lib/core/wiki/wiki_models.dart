import 'package:flutter/foundation.dart';

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
