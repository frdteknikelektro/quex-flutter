import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/breakpoints.dart';
import '../../app/router.dart';
import '../../core/ai/gemma_inference_service.dart';
import '../../core/ai/quex_ai.dart';
import '../../core/state/app_state.dart';
import '../../core/state/wiki_state.dart';
import '../../core/wiki/wiki_markdown_parser.dart';
import '../../core/wiki/wiki_models.dart';

class SessionWikiScreen extends ConsumerStatefulWidget {
  final int sessionId;

  const SessionWikiScreen({super.key, required this.sessionId});

  @override
  ConsumerState<SessionWikiScreen> createState() => _SessionWikiScreenState();
}

class _SessionWikiScreenState extends ConsumerState<SessionWikiScreen>
    with SingleTickerProviderStateMixin {
  final Object _gemmaOwnerToken = Object();
  Future<GemmaInferenceService>? _modelFuture;
  String? _selectedPath;
  bool _modelLoading = false;
  String? _modelError;

  @override
  void initState() {
    super.initState();
    if (ref.read(wikiAutoLoadModelProvider)) {
      unawaited(_warmModel());
    }
  }

  @override
  void dispose() {
    unawaited(QuexAi.releaseGemmaService(_gemmaOwnerToken));
    super.dispose();
  }

  Future<GemmaInferenceService> _ensureModel() {
    final current = QuexAi.gemmaService;
    if (current != null &&
        current.isInitialized &&
        QuexAi.isCurrentGemmaOwner(_gemmaOwnerToken)) {
      return Future.value(current);
    }
    final existingFuture = _modelFuture;
    if (existingFuture != null) return existingFuture;

    final future = _bootstrapModel();
    _modelFuture = future;
    future.whenComplete(() {
      if (mounted) _modelFuture = null;
    });
    return future;
  }

  Future<void> _warmModel() async {
    try {
      await _ensureModel();
    } catch (_) {
      // Empty state already surfaces model availability.
    }
  }

  Future<GemmaInferenceService> _bootstrapModel() async {
    if (mounted) {
      setState(() {
        _modelLoading = true;
        _modelError = null;
      });
    }

    try {
      return await QuexAi.acquireGemmaService(_gemmaOwnerToken);
    } catch (error) {
      _modelError = error.toString();
      rethrow;
    } finally {
      if (mounted) {
        setState(() => _modelLoading = false);
      }
    }
  }

  Future<void> _runIngest() async {
    try {
      final service = await _ensureModel();
      await ref
          .read(wikiActionControllerProvider(widget.sessionId).notifier)
          .ingest(service);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load model: $error')),
      );
    }
  }

  Future<void> _runLint() async {
    try {
      final service = await _ensureModel();
      await ref
          .read(wikiActionControllerProvider(widget.sessionId).notifier)
          .lint(service);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load model: $error')),
      );
    }
  }

  void _syncSelection(List<WikiTreeNode> tree) {
    final files = _flattenFilePaths(tree);
    if (files.isEmpty) return;
    final preferred = files.contains('index.md') ? 'index.md' : files.first;
    final current = _selectedPath;
    if (current == null || !files.contains(current)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _selectedPath = preferred);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<WikiActionState>(
      wikiActionControllerProvider(widget.sessionId),
      (previous, next) {
        if (previous?.status == next.status) return;
        if (!mounted) return;

        if (next.isSuccess) {
          setState(() => _selectedPath = 'index.md');
          final label = next.runType == WikiRunType.lint
              ? 'Wiki lint finished'
              : 'Wiki updated';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(label)),
          );
        } else if (next.hasError && next.error != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(next.error!)),
          );
        }
      },
    );

    final compact = MediaQuery.sizeOf(context).width < QuexBreakpoints.tablet;
    final bundleAsync = ref.watch(sessionBundleProvider(widget.sessionId));
    final treeAsync = ref.watch(wikiTreeProvider(widget.sessionId));
    final actionState =
        ref.watch(wikiActionControllerProvider(widget.sessionId));

    return bundleAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Failed to load session: $error')),
      ),
      data: (bundle) {
        if (bundle == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Session not found')),
          );
        }

        final materials = bundle.materials;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Wiki'),
          ),
          body: SafeArea(
            child: treeAsync.when(
              loading: () => _WikiScaffoldBody(
                header: _WikiHeaderCard(
                  sessionTitle: bundle.session.title,
                  materialCount: materials.length,
                  modelLoading: _modelLoading,
                  modelError: _modelError,
                  hasWiki: false,
                  actionState: actionState,
                  onIngest: materials.isEmpty ? null : _runIngest,
                  onLint: null,
                ),
                content: const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
              error: (error, _) => _WikiScaffoldBody(
                header: _WikiHeaderCard(
                  sessionTitle: bundle.session.title,
                  materialCount: materials.length,
                  modelLoading: _modelLoading,
                  modelError: _modelError,
                  hasWiki: false,
                  actionState: actionState,
                  onIngest: materials.isEmpty ? null : _runIngest,
                  onLint: null,
                ),
                content: Expanded(
                  child: Center(
                    child: Text('Failed to load wiki: $error'),
                  ),
                ),
              ),
              data: (tree) {
                _syncSelection(tree);
                final hasWiki = tree.isNotEmpty;

                if (materials.isEmpty) {
                  return _WikiEmptyState(
                    title: 'Build a knowledge wiki',
                    subtitle:
                        'Add study materials first. Then turn them into linked pages.',
                    actionLabel: 'Open study materials',
                    emoji: '📚',
                    actionIcon: Icons.library_books_outlined,
                    modelLoading: _modelLoading,
                    modelError: _modelError,
                    onAction: () =>
                        context.push(Routes.addMaterial.replaceFirst(
                      ':sessionId',
                      '${widget.sessionId}',
                    )),
                  );
                }

                if (!hasWiki) {
                  return actionState.isBusy
                      ? Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 620),
                            child: _ActionProgressCard(state: actionState),
                          ),
                        )
                      : _WikiEmptyState(
                          title: 'Build a knowledge wiki',
                          subtitle:
                              'Ingest study materials into sources, concepts, entities, syntheses, index, and log.',
                          actionLabel: 'Build wiki',
                          emoji: '🗺️',
                          actionIcon: Icons.auto_awesome,
                          modelLoading: _modelLoading,
                          modelError: _modelError,
                          onAction: _runIngest,
                        );
                }

                final selectedPath = _selectedPath;
                final pageAsync = selectedPath == null
                    ? const AsyncValue<WikiEntry?>.data(null)
                    : ref.watch(
                        wikiPageProvider(
                          WikiPageRequest(
                            sessionId: widget.sessionId,
                            relativePath: selectedPath,
                          ),
                        ),
                      );

                return _WikiScaffoldBody(
                  header: _WikiHeaderCard(
                    sessionTitle: bundle.session.title,
                    materialCount: materials.length,
                    modelLoading: _modelLoading,
                    modelError: _modelError,
                    hasWiki: true,
                    actionState: actionState,
                    onIngest: actionState.isBusy ? null : _runIngest,
                    onLint: actionState.isBusy ? null : _runLint,
                  ),
                  content: Expanded(
                    child: compact
                        ? _CompactWikiLayout(
                            tree: tree,
                            selectedPath: selectedPath,
                            pageAsync: pageAsync,
                            actionState: actionState,
                            onOpenFiles: () => _showTreeSheet(tree),
                            onSelectFile: (path) {
                              Navigator.of(context).maybePop();
                              setState(() => _selectedPath = path);
                            },
                          )
                        : _WideWikiLayout(
                            tree: tree,
                            selectedPath: selectedPath,
                            pageAsync: pageAsync,
                            actionState: actionState,
                            onSelectFile: (path) {
                              setState(() => _selectedPath = path);
                            },
                          ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _showTreeSheet(List<WikiTreeNode> tree) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _WikiTreeSheet(
        tree: tree,
        selectedPath: _selectedPath,
        onSelectFile: (path) {
          setState(() => _selectedPath = path);
          Navigator.of(context).pop();
        },
      ),
    );
  }
}

class _WikiScaffoldBody extends StatelessWidget {
  final Widget header;
  final Widget content;

  const _WikiScaffoldBody({
    required this.header,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: 16),
          content,
        ],
      ),
    );
  }
}

class _WikiHeaderCard extends StatelessWidget {
  final String sessionTitle;
  final int materialCount;
  final bool modelLoading;
  final String? modelError;
  final bool hasWiki;
  final WikiActionState actionState;
  final VoidCallback? onIngest;
  final VoidCallback? onLint;

  const _WikiHeaderCard({
    required this.sessionTitle,
    required this.materialCount,
    required this.modelLoading,
    required this.modelError,
    required this.hasWiki,
    required this.actionState,
    required this.onIngest,
    required this.onLint,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Session wiki',
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              sessionTitle,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              hasWiki
                  ? 'Browse generated notes, index pages, and lint reviews.'
                  : 'Turn session materials into an interlinked markdown wiki.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _StatusChip(
                  icon: Icons.library_books_outlined,
                  label: materialCount == 1
                      ? '1 material'
                      : '$materialCount materials',
                ),
                _StatusChip(
                  icon: modelLoading
                      ? Icons.downloading_rounded
                      : modelError == null
                          ? Icons.memory_rounded
                          : Icons.error_outline,
                  label: modelLoading
                      ? 'Loading model'
                      : modelError == null
                          ? 'Model ready'
                          : 'Model unavailable',
                ),
                if (actionState.isBusy)
                  _StatusChip(
                    icon: Icons.auto_awesome,
                    label: actionState.runType == WikiRunType.lint
                        ? 'Lint running'
                        : 'Ingest running',
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: onIngest,
                  icon: Icon(hasWiki ? Icons.refresh : Icons.auto_awesome),
                  label: Text(hasWiki ? 'Re-ingest' : 'Ingest'),
                ),
                OutlinedButton.icon(
                  onPressed: hasWiki ? onLint : null,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Lint'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _StatusChip({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: scheme.primary),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _WikiEmptyState extends StatelessWidget {
  final String title;
  final String subtitle;
  final String actionLabel;
  final String emoji;
  final IconData actionIcon;
  final bool modelLoading;
  final String? modelError;
  final VoidCallback onAction;

  const _WikiEmptyState({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.emoji,
    required this.actionIcon,
    required this.modelLoading,
    required this.modelError,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 104,
                height: 104,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(30),
                ),
                alignment: Alignment.center,
                child: Text(
                  emoji,
                  style: const TextStyle(fontSize: 52, height: 1),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: scheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                subtitle,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              if (modelError != null) ...[
                const SizedBox(height: 18),
                Text(
                  modelError!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.error,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: modelLoading ? null : onAction,
                icon: modelLoading
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.onPrimary,
                        ),
                      )
                    : Icon(actionIcon),
                label: Text(modelLoading ? 'Loading model...' : actionLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionProgressCard extends StatelessWidget {
  final WikiActionState state;

  const _ActionProgressCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    state.runType == WikiRunType.lint
                        ? 'Linting wiki...'
                        : 'Building wiki...',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(18),
                ),
                padding: const EdgeInsets.all(14),
                child: ListView.separated(
                  itemCount: state.lines.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    return Text(
                      state.lines[index],
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactWikiLayout extends StatelessWidget {
  final List<WikiTreeNode> tree;
  final String? selectedPath;
  final AsyncValue<WikiEntry?> pageAsync;
  final WikiActionState actionState;
  final VoidCallback onOpenFiles;
  final ValueChanged<String> onSelectFile;

  const _CompactWikiLayout({
    required this.tree,
    required this.selectedPath,
    required this.pageAsync,
    required this.actionState,
    required this.onOpenFiles,
    required this.onSelectFile,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onOpenFiles,
                icon: const Icon(Icons.account_tree_outlined),
                label: const Text('Files'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (actionState.isBusy) ...[
          SizedBox(height: 280, child: _ActionProgressCard(state: actionState)),
          const SizedBox(height: 12),
        ],
        Expanded(
          child: _WikiPageCard(
            pageAsync: pageAsync,
            compact: true,
            onSelectFile: onSelectFile,
          ),
        ),
      ],
    );
  }
}

class _WideWikiLayout extends StatelessWidget {
  final List<WikiTreeNode> tree;
  final String? selectedPath;
  final AsyncValue<WikiEntry?> pageAsync;
  final WikiActionState actionState;
  final ValueChanged<String> onSelectFile;

  const _WideWikiLayout({
    required this.tree,
    required this.selectedPath,
    required this.pageAsync,
    required this.actionState,
    required this.onSelectFile,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 280,
          child: _WikiTreePanel(
            tree: tree,
            selectedPath: selectedPath,
            onSelectFile: onSelectFile,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            children: [
              if (actionState.isBusy) ...[
                SizedBox(
                    height: 240,
                    child: _ActionProgressCard(state: actionState)),
                const SizedBox(height: 16),
              ],
              Expanded(
                child: _WikiPageCard(
                  pageAsync: pageAsync,
                  compact: false,
                  onSelectFile: onSelectFile,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WikiTreePanel extends StatelessWidget {
  final List<WikiTreeNode> tree;
  final String? selectedPath;
  final ValueChanged<String> onSelectFile;

  const _WikiTreePanel({
    required this.tree,
    required this.selectedPath,
    required this.onSelectFile,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Text(
                'Wiki files',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: ListView(
                children: tree
                    .map(
                      (node) => _WikiTreeNodeTile(
                        node: node,
                        depth: 0,
                        selectedPath: selectedPath,
                        onSelectFile: onSelectFile,
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WikiTreeSheet extends StatelessWidget {
  final List<WikiTreeNode> tree;
  final String? selectedPath;
  final ValueChanged<String> onSelectFile;

  const _WikiTreeSheet({
    required this.tree,
    required this.selectedPath,
    required this.onSelectFile,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 18,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Wiki files',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: tree
                  .map(
                    (node) => _WikiTreeNodeTile(
                      node: node,
                      depth: 0,
                      selectedPath: selectedPath,
                      onSelectFile: onSelectFile,
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        ],
      ),
    );
  }
}

class _WikiTreeNodeTile extends StatelessWidget {
  final WikiTreeNode node;
  final int depth;
  final String? selectedPath;
  final ValueChanged<String> onSelectFile;

  const _WikiTreeNodeTile({
    required this.node,
    required this.depth,
    required this.selectedPath,
    required this.onSelectFile,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final padding = EdgeInsets.only(left: depth * 14.0);

    if (node.isDirectory) {
      return Padding(
        padding: padding,
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 8),
          childrenPadding: EdgeInsets.zero,
          leading: Icon(Icons.folder_outlined, color: scheme.primary),
          title: Text(
            node.displayTitle,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          children: node.children
              .map(
                (child) => _WikiTreeNodeTile(
                  node: child,
                  depth: depth + 1,
                  selectedPath: selectedPath,
                  onSelectFile: onSelectFile,
                ),
              )
              .toList(growable: false),
        ),
      );
    }

    final selected = selectedPath == node.relativePath;
    return Padding(
      padding: padding,
      child: ListTile(
        selected: selected,
        selectedTileColor: scheme.primaryContainer.withValues(alpha: 0.65),
        leading: Icon(
          node.name == 'index.md'
              ? Icons.home_work_outlined
              : node.name == 'log.md'
                  ? Icons.history
                  : Icons.description_outlined,
          color: selected ? scheme.primary : scheme.onSurfaceVariant,
        ),
        title: Text(
          node.displayTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          node.relativePath,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () => onSelectFile(node.relativePath),
      ),
    );
  }
}

class _WikiPageCard extends StatelessWidget {
  final AsyncValue<WikiEntry?> pageAsync;
  final bool compact;
  final ValueChanged<String> onSelectFile;

  const _WikiPageCard({
    required this.pageAsync,
    required this.compact,
    required this.onSelectFile,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: pageAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Failed to load page: $error')),
        data: (entry) {
          if (entry == null) {
            return Center(
              child: Text(
                'Pick a wiki page to start reading.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            );
          }

          return _WikiEntryView(entry: entry, compact: compact);
        },
      ),
    );
  }
}

class _WikiEntryView extends StatelessWidget {
  final WikiEntry entry;
  final bool compact;

  const _WikiEntryView({
    required this.entry,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final headings = extractWikiHeadings(entry.rawContent);
    final sections = splitWikiSections(entry.rawContent);
    final sectionKeys = {
      for (final section in sections) section.id: GlobalKey(),
    };

    final reader = SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _StatusChip(
                icon: Icons.category_outlined,
                label: entry.category,
              ),
              _StatusChip(
                icon: Icons.update,
                label: DateFormat('MMM d, HH:mm').format(entry.updatedAt),
              ),
              if (entry.materialIds.isNotEmpty)
                _StatusChip(
                  icon: Icons.link_outlined,
                  label: '${entry.materialIds.length} linked source(s)',
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            entry.title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            entry.relativePath,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (compact && headings.isNotEmpty) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                backgroundColor: Colors.transparent,
                builder: (_) => _WikiTocSheet(
                  headings: headings,
                  onTap: (heading) async {
                    Navigator.of(context).pop();
                    final key = sectionKeys[heading.anchor];
                    if (key?.currentContext != null) {
                      await Scrollable.ensureVisible(
                        key!.currentContext!,
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        alignment: 0.08,
                      );
                    }
                  },
                ),
              ),
              icon: const Icon(Icons.toc_outlined),
              label: const Text('Table of contents'),
            ),
          ],
          const SizedBox(height: 18),
          ...sections.map(
            (section) => Container(
              key: sectionKeys[section.id],
              margin: const EdgeInsets.only(bottom: 16),
              child: MarkdownBody(
                data: prepareWikiMarkdown(section.markdown),
                styleSheet: _wikiMarkdownStyle(context),
              ),
            ),
          ),
        ],
      ),
    );

    if (compact) return reader;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: reader),
        Container(width: 1, color: scheme.outlineVariant),
        SizedBox(
          width: 220,
          child: _WikiTocPanel(
            headings: headings,
            onTap: (heading) async {
              final key = sectionKeys[heading.anchor];
              if (key?.currentContext != null) {
                await Scrollable.ensureVisible(
                  key!.currentContext!,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  alignment: 0.08,
                );
              }
            },
          ),
        ),
      ],
    );
  }
}

class _WikiTocPanel extends StatelessWidget {
  final List<WikiHeading> headings;
  final ValueChanged<WikiHeading> onTap;

  const _WikiTocPanel({
    required this.headings,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
      child: headings.isEmpty
          ? Center(
              child: Text(
                'No headings',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Contents',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.separated(
                    itemCount: headings.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final heading = headings[index];
                      return InkWell(
                        onTap: () => onTap(heading),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: EdgeInsets.only(
                            left: (heading.level - 1) * 10.0,
                            right: 8,
                            top: 8,
                            bottom: 8,
                          ),
                          child: Text(
                            heading.title,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontWeight: heading.level == 1
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

class _WikiTocSheet extends StatelessWidget {
  final List<WikiHeading> headings;
  final ValueChanged<WikiHeading> onTap;

  const _WikiTocSheet({
    required this.headings,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 18,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Table of contents',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: headings.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final heading = headings[index];
                return ListTile(
                  contentPadding: EdgeInsets.only(
                    left: (heading.level - 1) * 10.0 + 4,
                    right: 8,
                  ),
                  leading: const Icon(Icons.subdirectory_arrow_right),
                  title: Text(heading.title),
                  onTap: () => onTap(heading),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

MarkdownStyleSheet _wikiMarkdownStyle(BuildContext context) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  return MarkdownStyleSheet.fromTheme(theme).copyWith(
    p: theme.textTheme.bodyLarge?.copyWith(
      color: scheme.onSurface,
      height: 1.6,
    ),
    h1: theme.textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w900,
      color: scheme.onSurface,
    ),
    h2: theme.textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w800,
      color: scheme.onSurface,
    ),
    h3: theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
      color: scheme.onSurface,
    ),
    strong: theme.textTheme.bodyLarge?.copyWith(
      fontWeight: FontWeight.w800,
      color: scheme.onSurface,
      height: 1.6,
    ),
    em: theme.textTheme.bodyLarge?.copyWith(
      fontStyle: FontStyle.italic,
      color: scheme.onSurface,
      height: 1.6,
    ),
    codeblockDecoration: BoxDecoration(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
    ),
    code: theme.textTheme.bodyMedium?.copyWith(
      fontFamily: 'monospace',
      color: scheme.primary,
      backgroundColor: scheme.surfaceContainerHighest,
    ),
    blockquoteDecoration: BoxDecoration(
      color: scheme.primaryContainer.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(12),
      border: Border(
        left: BorderSide(color: scheme.primary, width: 3),
      ),
    ),
  );
}

List<String> _flattenFilePaths(List<WikiTreeNode> nodes) {
  final paths = <String>[];
  for (final node in nodes) {
    if (node.isFile) {
      paths.add(node.relativePath);
    } else {
      paths.addAll(_flattenFilePaths(node.children));
    }
  }
  return paths;
}
