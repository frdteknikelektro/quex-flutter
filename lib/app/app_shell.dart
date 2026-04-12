import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/ai/download_state.dart';
import '../core/ai/model_download_notifier.dart';
import 'breakpoints.dart';
import 'router.dart';

enum QuexDestination { home, newSession, settings, model }

class QuexAppShell extends ConsumerWidget {
  final QuexDestination destination;
  final String title;
  final Widget child;
  final List<Widget> actions;
  final Widget? floatingActionButton;
  final PreferredSizeWidget? bottom;
  final bool showNavigation;

  const QuexAppShell({
    super.key,
    required this.destination,
    required this.title,
    required this.child,
    this.actions = const [],
    this.floatingActionButton,
    this.bottom,
    this.showNavigation = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final compact = MediaQuery.sizeOf(context).width < QuexBreakpoints.tablet;
    final index = destination.index;
    final downloadState = ref.watch(modelDownloadProvider);

    final content = Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: actions,
        bottom: bottom,
      ),
      body: Column(
        children: [
          Expanded(child: child),
          if (downloadState.isActive)
            _DownloadBanner(
              progress: downloadState.progress,
              status: downloadState.status,
              onCancel: () =>
                  ref.read(modelDownloadProvider.notifier).cancel(),
              onTap: () => context.go(Routes.modelDownload),
            ),
        ],
      ),
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: showNavigation && compact
          ? NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (selected) => _go(context, selected),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(Icons.edit_note_outlined),
                  selectedIcon: Icon(Icons.edit_note),
                  label: 'New session',
                ),
                NavigationDestination(
                  icon: Icon(Icons.tune_outlined),
                  selectedIcon: Icon(Icons.tune),
                  label: 'Settings',
                ),
                NavigationDestination(
                  icon: Icon(Icons.cloud_download_outlined),
                  selectedIcon: Icon(Icons.cloud_download),
                  label: 'Model',
                ),
              ],
            )
          : null,
    );

    if (!showNavigation || compact) {
      return content;
    }

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            NavigationRail(
              selectedIndex: index,
              onDestinationSelected: (selected) => _go(context, selected),
              labelType: NavigationRailLabelType.all,
              minWidth: 88,
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: Text('Home'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.edit_note_outlined),
                  selectedIcon: Icon(Icons.edit_note),
                  label: Text('New'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.tune_outlined),
                  selectedIcon: Icon(Icons.tune),
                  label: Text('Settings'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.cloud_download_outlined),
                  selectedIcon: Icon(Icons.cloud_download),
                  label: Text('Model'),
                ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }

  void _go(BuildContext context, int selected) {
    switch (QuexDestination.values[selected]) {
      case QuexDestination.home:
        context.go(Routes.home);
        return;
      case QuexDestination.newSession:
        context.go(Routes.newSession);
        return;
      case QuexDestination.settings:
        context.go(Routes.settings);
        return;
      case QuexDestination.model:
        context.go(Routes.modelDownload);
        return;
    }
  }
}

class _DownloadBanner extends StatelessWidget {
  final double progress;
  final DownloadStatus status;
  final VoidCallback onCancel;
  final VoidCallback onTap;

  const _DownloadBanner({
    required this.progress,
    required this.status,
    required this.onCancel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isCancelling = status == DownloadStatus.cancelling;
    final percent = (progress * 100).round();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        color: scheme.secondaryContainer,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              Icon(
                Icons.downloading_outlined,
                size: 20,
                color: scheme.onSecondaryContainer,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isCancelling ? 'Cancelling…' : 'Downloading model  $percent%',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: scheme.onSecondaryContainer,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: isCancelling ? null : progress,
                        backgroundColor:
                            scheme.onSecondaryContainer.withValues(alpha: 0.2),
                        color: scheme.onSecondaryContainer,
                        minHeight: 4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (!isCancelling)
                IconButton(
                  onPressed: onCancel,
                  icon: Icon(
                    Icons.close,
                    size: 18,
                    color: scheme.onSecondaryContainer,
                  ),
                  tooltip: 'Cancel download',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
