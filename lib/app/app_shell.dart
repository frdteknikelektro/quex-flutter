import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'breakpoints.dart';
import 'router.dart';

enum QuexDestination { home, newSession, settings, model }

class QuexAppShell extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < QuexBreakpoints.tablet;
    final index = destination.index;

    final content = Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: actions,
        bottom: bottom,
      ),
      body: child,
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
