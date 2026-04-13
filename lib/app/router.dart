import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/ai/model_download_notifier.dart';
import '../features/chat/chat_screen.dart';
import '../features/home/home_screen.dart';
import '../features/material/add_material_screen.dart';
import '../features/model_download/model_download_screen.dart';
import '../features/processing/processing_screen.dart';
import '../features/quiz/quiz_screen.dart';
import '../features/session_detail/session_detail_screen.dart';
import '../features/session_new/new_session_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/splash/splash_screen.dart';
import '../features/summary/summary_screen.dart';

class Routes {
  static const splash = '/splash';
  static const home = '/';
  static const newSession = '/session/new';
  static const session = '/session/:sessionId';
  static const addMaterial = '/session/:sessionId/material';
  static const processing = '/session/:sessionId/processing';
  static const quiz = '/session/:sessionId/quiz/:quizId';
  static const chat = '/session/:sessionId/chat';
  static const summary = '/session/:sessionId/quiz/:quizId/summary';
  static const settings = '/settings';
  static const modelDownload = '/model-download';
}

final appRouter = GoRouter(
  initialLocation: Routes.splash,
  debugLogDiagnostics: false,
  redirect: (context, state) {
    final container = ProviderScope.containerOf(context);
    final downloadState = container.read(modelDownloadProvider);
    final isOnSplash = state.matchedLocation == Routes.splash;
    final isOnModelDownload = state.matchedLocation == Routes.modelDownload;

    // If model is completed and on splash, redirect to home
    if (downloadState.isCompleted && isOnSplash) {
      return Routes.home;
    }

    // If model is not completed and not on splash/model-download, redirect to splash
    if (!downloadState.isCompleted && !isOnSplash && !isOnModelDownload) {
      return Routes.splash;
    }

    return null; // No redirect
  },
  routes: [
    GoRoute(
      path: Routes.splash,
      name: 'splash',
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: Routes.home,
      name: 'home',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: Routes.newSession,
      name: 'new-session',
      builder: (context, state) => const NewSessionScreen(),
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
      path: Routes.settings,
      name: 'settings',
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: Routes.modelDownload,
      name: 'model-download',
      builder: (context, state) => const ModelDownloadScreen(),
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
