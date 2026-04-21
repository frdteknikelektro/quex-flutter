import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/breakpoints.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import 'wiki_build_modal.dart';
import '../../core/ai/wiki_storage_service.dart';
import '../../core/state/app_state.dart';
import '../../core/state/wiki_state.dart';

class SessionWikiScreen extends ConsumerStatefulWidget {
  final int sessionId;

  const SessionWikiScreen({super.key, required this.sessionId});

  @override
  ConsumerState<SessionWikiScreen> createState() => _SessionWikiScreenState();
}

class _SessionWikiScreenState extends ConsumerState<SessionWikiScreen> {
  String? _selectedPath;

  void _openBuildModal(
    BuildContext context, {
    bool cleanFirst = false,
  }) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useSafeArea: false,
      builder: (_) => WikiBuildModal(
        sessionId: widget.sessionId,
        cleanFirst: cleanFirst,
      ),
    );
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
    ref.listen(wikiActionControllerProvider(widget.sessionId),
        (previous, next) {
      if (previous?.status == next.status) return;
      if (!mounted) return;
      if (next.isSuccess) setState(() => _selectedPath = 'index.md');
    });

    final compact = MediaQuery.sizeOf(context).width < QuexBreakpoints.tablet;
    final bundleAsync = ref.watch(sessionBundleProvider(widget.sessionId));
    final treeAsync = ref.watch(wikiTreeProvider(widget.sessionId));

    return bundleAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(
          title: const Text('Wiki'),
        ),
        body: Center(child: Text('Failed to load session: $error')),
      ),
      data: (bundle) {
        if (bundle == null) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Wiki'),
            ),
            body: const Center(child: Text('Session not found')),
          );
        }

        final materials = bundle.materials;
        final hasMaterials = materials.isNotEmpty;
        final hasWiki = treeAsync.maybeWhen(
          data: (tree) => tree.isNotEmpty,
          orElse: () => false,
        );

        return Scaffold(
          appBar: AppBar(
            leading: BackButton(
              onPressed: () =>
                  context.canPop() ? context.pop() : context.go(Routes.home),
            ),
            title: const Text('Wiki'),
          ),
          floatingActionButton: hasWiki
              ? FloatingActionButton.extended(
                  onPressed: () => _openBuildModal(
                    context,
                    cleanFirst: true,
                  ),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Re-build wiki'),
                )
              : null,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: treeAsync.when(
                      loading: () => const Center(
                        child: CircularProgressIndicator(),
                      ),
                      error: (error, _) => Center(
                        child: _WikiEmptyState(
                          emoji: '🗂️',
                          title: 'Wiki unavailable',
                          subtitle:
                              'Could not load wiki tree right now. Try again after the session finishes syncing.',
                          actionIcon: Icons.refresh_rounded,
                          actionLabel: 'Retry',
                          errorText: error.toString(),
                          onAction: () => ref.invalidate(
                            wikiTreeProvider(widget.sessionId),
                          ),
                        ),
                      ),
                      data: (tree) {
                        _syncSelection(tree);
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

                        if (!hasMaterials) {
                          return Center(
                            child: _WikiEmptyState(
                              emoji: '📚',
                              title: 'Add study materials first',
                              subtitle:
                                  'Wiki needs notes, PDFs, or photos before it can build linked pages.',
                              actionIcon: Icons.library_books_outlined,
                              actionLabel: 'Open study materials',
                              onAction: () => context.push(
                                Routes.addMaterial.replaceFirst(
                                  ':sessionId',
                                  '${widget.sessionId}',
                                ),
                              ),
                            ),
                          );
                        }

                        if (!hasWiki) {
                          return Center(
                            child: _WikiEmptyState(
                              emoji: '🗺️',
                              title: 'Build a knowledge wiki',
                              subtitle:
                                  'Ingest materials into sources, concepts, entities, syntheses, index, and log.',
                              actionIcon: Icons.auto_awesome_rounded,
                              actionLabel: 'Build wiki',
                              onAction: () => _openBuildModal(context),
                            ),
                          );
                        }

                        return compact
                            ? _CompactWikiLayout(
                                pageAsync: pageAsync,
                                onOpenFiles: () => _showTreeSheet(tree),
                              )
                            : _WideWikiLayout(
                                tree: tree,
                                selectedPath: selectedPath,
                                pageAsync: pageAsync,
                                onSelectFile: (path) {
                                  setState(() => _selectedPath = path);
                                },
                              );
                      },
                    ),
                  ),
                ],
              ),
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

class _WikiStatusPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _WikiStatusPill({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final iconColor = scheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: iconColor),
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

class _WikiCallout extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _WikiCallout({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: Br.md,
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WikiEmptyState extends StatefulWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final IconData actionIcon;
  final String actionLabel;
  final String? errorText;
  final VoidCallback? onAction;

  const _WikiEmptyState({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.actionIcon,
    required this.actionLabel,
    this.errorText,
    this.onAction,
  });

  @override
  State<_WikiEmptyState> createState() => _WikiEmptyStateState();
}

class _WikiEmptyStateState extends State<_WikiEmptyState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bounceController;
  late final Animation<double> _bounceAnimation;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _bounceAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -20.0), weight: 30),
      TweenSequenceItem(tween: Tween(begin: -20.0, end: 0.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -10.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: -10.0, end: 0.0), weight: 30),
    ]).animate(CurvedAnimation(
      parent: _bounceController,
      curve: Curves.easeInOut,
    ));
    _bounceController.forward();
  }

  @override
  void dispose() {
    _bounceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _bounceAnimation,
            builder: (context, child) => Transform.translate(
              offset: Offset(0, _bounceAnimation.value),
              child: child,
            ),
            child: Text(
              widget.emoji,
              style: const TextStyle(fontSize: 72, height: 1),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            widget.title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: scheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            widget.subtitle,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          if (widget.errorText != null) ...[
            const SizedBox(height: 14),
            _WikiCallout(
              icon: Icons.error_outline,
              text: widget.errorText!,
              color: scheme.error,
            ),
          ],
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: widget.onAction,
            icon: Icon(widget.actionIcon),
            label: Text(widget.actionLabel),
          ),
        ],
      ),
    );
  }
}

class _CompactWikiLayout extends StatelessWidget {
  final AsyncValue<WikiEntry?> pageAsync;
  final VoidCallback onOpenFiles;

  const _CompactWikiLayout({
    required this.pageAsync,
    required this.onOpenFiles,
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
        Expanded(
          child: _WikiPageCard(
            pageAsync: pageAsync,
            compact: true,
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
  final ValueChanged<String> onSelectFile;

  const _WideWikiLayout({
    required this.tree,
    required this.selectedPath,
    required this.pageAsync,
    required this.onSelectFile,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 300,
          child: _WikiTreePanel(
            tree: tree,
            selectedPath: selectedPath,
            onSelectFile: onSelectFile,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _WikiPageCard(
            pageAsync: pageAsync,
            compact: false,
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
    final scheme = theme.colorScheme;

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: Br.md,
                  ),
                  child: Icon(
                    Icons.folder_copy_outlined,
                    color: scheme.onPrimaryContainer,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Wiki files',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        '${_flattenFilePaths(tree).length} pages',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Expanded(
              child: Scrollbar(
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
    final theme = Theme.of(context);

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
              width: 42,
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
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_flattenFilePaths(tree).length} pages',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
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

  IconData _fileIcon() {
    if (node.name == 'index.md') return Icons.home_work_outlined;
    if (node.name == 'log.md') return Icons.history_rounded;
    return Icons.description_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final padding = EdgeInsets.only(left: depth * 12.0);

    if (node.isDirectory) {
      return Padding(
        padding: padding,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.16),
            borderRadius: Br.md,
            border:
                Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
          ),
          child: ExpansionTile(
            initiallyExpanded: true,
            tilePadding: const EdgeInsets.symmetric(horizontal: 12),
            childrenPadding: const EdgeInsets.only(bottom: 8),
            iconColor: scheme.primary,
            collapsedIconColor: scheme.onSurfaceVariant,
            leading: Icon(Icons.folder_outlined, color: scheme.primary),
            title: Text(
              node.displayTitle,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
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
        ),
      );
    }

    final selected = selectedPath == node.relativePath;
    return Padding(
      padding: padding,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: selected
                ? scheme.primaryContainer.withValues(alpha: 0.65)
                : scheme.surfaceContainerHighest.withValues(alpha: 0.12),
            borderRadius: Br.md,
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
            ),
          ),
          child: ListTile(
            selected: selected,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: selected
                    ? scheme.onPrimaryContainer.withValues(alpha: 0.12)
                    : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _fileIcon(),
                size: 18,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
            title: Text(
              node.displayTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Text(
              node.relativePath,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            onTap: () => onSelectFile(node.relativePath),
          ),
        ),
      ),
    );
  }
}

class _WikiPageCard extends StatelessWidget {
  final AsyncValue<WikiEntry?> pageAsync;
  final bool compact;

  const _WikiPageCard({
    required this.pageAsync,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: pageAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Failed to load page: $error'),
          ),
        ),
        data: (entry) {
          if (entry == null) {
            final theme = Theme.of(context);
            final scheme = theme.colorScheme;
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: Br.lg,
                      ),
                      child: Icon(
                        Icons.chrome_reader_mode_outlined,
                        color: scheme.onPrimaryContainer,
                        size: 36,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Pick a wiki page to start reading',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Use the file tree to open index, log, or generated topic pages.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.45,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: Br.lg,
                ),
                child: Icon(
                  Icons.auto_stories_rounded,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _WikiStatusPill(
                icon: Icons.category_outlined,
                label: entry.category,
              ),
              _WikiStatusPill(
                icon: Icons.update_rounded,
                label: DateFormat('MMM d, HH:mm').format(entry.updatedAt),
              ),
              if (entry.materialIds.isNotEmpty)
                _WikiStatusPill(
                  icon: Icons.link_outlined,
                  label: '${entry.materialIds.length} linked source(s)',
                ),
            ],
          ),
          if (compact && headings.isNotEmpty) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                backgroundColor: Colors.transparent,
                isScrollControlled: true,
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
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.34),
                borderRadius: Br.lg,
                border: Border.all(color: scheme.outlineVariant),
              ),
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
          width: 224,
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
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
      child: Card(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.all(14),
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
                        fontWeight: FontWeight.w900,
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
                            borderRadius: Br.md,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOutCubic,
                              padding: EdgeInsets.only(
                                left: (heading.level - 1) * 10.0 + 8,
                                right: 8,
                                top: 8,
                                bottom: 8,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.surface.withValues(alpha: 0.45),
                                borderRadius: Br.md,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.subdirectory_arrow_right,
                                    size: 16,
                                    color: scheme.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      heading.title,
                                      style:
                                          theme.textTheme.bodyMedium?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                        fontWeight: heading.level == 1
                                            ? FontWeight.w800
                                            : FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
        ),
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
    final theme = Theme.of(context);

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
              width: 42,
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
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${headings.length} headings',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
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
                  shape: RoundedRectangleBorder(
                    borderRadius: Br.md,
                    side: BorderSide(color: scheme.outlineVariant),
                  ),
                  leading: Icon(
                    Icons.subdirectory_arrow_right,
                    color: scheme.primary,
                  ),
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
      height: 1.68,
    ),
    h1: theme.textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w900,
      color: scheme.onSurface,
    ),
    h2: theme.textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w900,
      color: scheme.onSurface,
    ),
    h3: theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w800,
      color: scheme.onSurface,
    ),
    strong: theme.textTheme.bodyLarge?.copyWith(
      fontWeight: FontWeight.w900,
      color: scheme.onSurface,
      height: 1.68,
    ),
    em: theme.textTheme.bodyLarge?.copyWith(
      fontStyle: FontStyle.italic,
      color: scheme.onSurface,
      height: 1.68,
    ),
    codeblockDecoration: BoxDecoration(
      color: scheme.surface,
      borderRadius: Br.md,
      border: Border.all(color: scheme.outlineVariant),
    ),
    code: theme.textTheme.bodyMedium?.copyWith(
      fontFamily: 'monospace',
      color: scheme.primary,
      backgroundColor: scheme.surfaceContainerHighest,
    ),
    blockquoteDecoration: BoxDecoration(
      color: scheme.primaryContainer.withValues(alpha: 0.35),
      borderRadius: Br.md,
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
