import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/breakpoints.dart';
import '../core/ai/download_state.dart';
import '../core/ai/model_download_notifier.dart';
import '../core/state/app_state.dart';
import '../features/chat/chat_screen.dart';
import '../features/home/home_screen.dart';
import '../features/material/add_material_screen.dart';
import '../features/processing/processing_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/session_new/new_session_screen.dart';
import '../features/profile_selection/create_first_profile_screen.dart';
import '../features/profile_selection/profile_selection_screen.dart';
import '../features/quiz/quiz_screen.dart';
import '../features/session_detail/session_detail_screen.dart';
import '../features/splash/splash_screen.dart';
import '../features/summary/summary_screen.dart';
class Routes {
  static const splash = '/splash';
  static const profileSelection = '/profile-selection';
  static const createFirstProfile = '/create-first-profile';
  static const home = '/';
  static const newSession = '/session/new';
  static const session = '/session/:sessionId';
  static const addMaterial = '/session/:sessionId/material';
  static const processing = '/session/:sessionId/processing';
  static const quiz = '/session/:sessionId/quiz/:quizId';
  static const chat = '/session/:sessionId/chat';
  static const summary = '/session/:sessionId/quiz/:quizId/summary';
  static const profile = '/profile';
  }

final appRouter = GoRouter(
  initialLocation: Routes.splash,
  debugLogDiagnostics: false,
  redirect: (context, state) {
    final container = ProviderScope.containerOf(context);
    final downloadState = container.read(modelDownloadProvider);
    final sessionProfileSet = container.read(sessionProfileSetProvider);

    final loc = state.matchedLocation;
    final isOnSplash = loc == Routes.splash;
    final isOnProfileSelection = loc == Routes.profileSelection;
    final isOnCreateFirstProfile = loc == Routes.createFirstProfile;

    // If model is not complete, enforce splash
    if (!downloadState.isCompleted && !isOnSplash) {
      return Routes.splash;
    }

    // Once model is ready on splash and profile not set, send to profile selection
    if (downloadState.isCompleted && isOnSplash) {
      return sessionProfileSet ? Routes.home : Routes.profileSelection;
    }

    // Gate every cold-start behind profile selection
    if (downloadState.isCompleted &&
        !sessionProfileSet &&
        !isOnProfileSelection &&
        !isOnCreateFirstProfile) {
      return Routes.profileSelection;
    }

    return null;
  },
  routes: [
    GoRoute(
      path: Routes.splash,
      name: 'splash',
      builder: (context, state) => const SplashScreen(),
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) => _BottomNavigationShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.home,
              name: 'home',
              builder: (context, state) => const HomeScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.profile,
              name: 'profile',
              builder: (context, state) => const ProfileScreen(),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: Routes.session,
      name: 'session',
      builder: (context, state) {
        final sessionId = int.parse(state.pathParameters['sessionId']!);
        return SessionDetailScreen(sessionId: sessionId);
      },
    ),
    GoRoute(
      path: Routes.addMaterial,
      name: 'add-material',
      builder: (context, state) {
        final sessionId = int.parse(state.pathParameters['sessionId']!);
        return AddMaterialScreen(sessionId: sessionId);
      },
    ),
    GoRoute(
      path: Routes.processing,
      name: 'processing',
      builder: (context, state) {
        final sessionId = int.parse(state.pathParameters['sessionId']!);
        return ProcessingScreen(sessionId: sessionId);
      },
    ),
    GoRoute(
      path: Routes.quiz,
      name: 'quiz',
      builder: (context, state) {
        final sessionId = int.parse(state.pathParameters['sessionId']!);
        final quizId = int.parse(state.pathParameters['quizId']!);
        return QuizScreen(sessionId: sessionId, quizId: quizId);
      },
    ),
    GoRoute(
      path: Routes.chat,
      name: 'chat',
      builder: (context, state) {
        final sessionId = int.parse(state.pathParameters['sessionId']!);
        return ChatScreen(sessionId: sessionId);
      },
    ),
    GoRoute(
      path: Routes.summary,
      name: 'summary',
      builder: (context, state) {
        final sessionId = int.parse(state.pathParameters['sessionId']!);
        final quizId = int.parse(state.pathParameters['quizId']!);
        return SummaryScreen(sessionId: sessionId, quizId: quizId);
      },
    ),
    GoRoute(
      path: Routes.newSession,
      name: 'new-session',
      builder: (context, state) => const NewSessionScreen(),
    ),
    GoRoute(
      path: Routes.profileSelection,
      name: 'profile-selection',
      builder: (context, state) => const ProfileSelectionScreen(),
    ),
    GoRoute(
      path: Routes.createFirstProfile,
      name: 'create-first-profile',
      builder: (context, state) => const CreateFirstProfileScreen(),
    ),
  ],
  errorBuilder: (context, state) => Scaffold(
    body: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('Quex', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          Text('Page not found: ${state.uri}'),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => context.go(Routes.home),
            child: const Text('Go home'),
          ),
        ],
      ),
    ),
  ),
);

class _BottomNavigationShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const _BottomNavigationShell({required this.navigationShell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final compact = MediaQuery.sizeOf(context).width < QuexBreakpoints.tablet;
    final downloadState = ref.watch(modelDownloadProvider);
    final activeProfileId = ref.watch(activeProfileProvider);
    final hasSessions = ref.watch(recentSessionsProvider(activeProfileId ?? 0)).when(
          data: (sessions) => sessions.isNotEmpty,
          loading: () => true,
          error: (_, __) => true,
        );

    String getTitle() {
      switch (navigationShell.currentIndex) {
        case 0:
          return '🦆 Quex';
        case 1:
          return 'Profile';
        default:
          return 'Quex';
      }
    }

    List<Widget> getActions() {
      switch (navigationShell.currentIndex) {
        case 0:
          return [];
        case 1:
          return [];
        default:
          return [];
      }
    }

    Widget? getFloatingActionButton() {
      if (compact && navigationShell.currentIndex == 0 && hasSessions) {
        return FloatingActionButton.extended(
          onPressed: () => context.go(Routes.newSession),
          icon: const Icon(Icons.add),
          label: const Text('New session'),
        );
      }
      return null;
    }

    final content = Scaffold(
      appBar: AppBar(
        title: Text(getTitle()),
        actions: getActions(),
      ),
      body: Column(
        children: [
          Expanded(child: navigationShell),
          if (downloadState.isActive)
            _DownloadBanner(
              progress: downloadState.progress,
              status: downloadState.status,
              onCancel: () => ref.read(modelDownloadProvider.notifier).cancel(),
            ),
        ],
      ),
      floatingActionButton: getFloatingActionButton(),
      bottomNavigationBar: compact
          ? NavigationBar(
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: navigationShell.goBranch,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: 'Profile',
                ),
              ],
            )
          : null,
    );

    if (!compact) {
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              NavigationRail(
                selectedIndex: navigationShell.currentIndex,
                onDestinationSelected: navigationShell.goBranch,
                labelType: NavigationRailLabelType.all,
                minWidth: 88,
                destinations: const [
                  NavigationRailDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home),
                    label: Text('Home'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.person_outline),
                    selectedIcon: Icon(Icons.person),
                    label: Text('Profile'),
                  ),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: Scaffold(
                  appBar: AppBar(
                    title: Text(getTitle()),
                    actions: getActions(),
                  ),
                  body: Column(
                    children: [
                      Expanded(child: navigationShell),
                      if (downloadState.isActive)
                        _DownloadBanner(
                          progress: downloadState.progress,
                          status: downloadState.status,
                          onCancel: () => ref.read(modelDownloadProvider.notifier).cancel(),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return content;
  }
}

class _DownloadBanner extends StatelessWidget {
  final double progress;
  final DownloadStatus status;
  final VoidCallback onCancel;

  const _DownloadBanner({
    required this.progress,
    required this.status,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isCancelling = status == DownloadStatus.cancelling;
    final percent = (progress * 100).round();

    return Container(
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
                      backgroundColor: scheme.onSecondaryContainer.withValues(alpha: 0.2),
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
    );
  }
}
