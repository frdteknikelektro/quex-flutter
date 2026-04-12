import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/breakpoints.dart';
import '../../core/models/models.dart';
import '../../core/state/app_state.dart';
import '../../widgets/quex_ui.dart';

class SessionDetailScreen extends ConsumerWidget {
  final int sessionId;

  const SessionDetailScreen({super.key, required this.sessionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bundleAsync = ref.watch(sessionBundleProvider(sessionId));
    final compact = MediaQuery.sizeOf(context).width < QuexBreakpoints.tablet;

    return bundleAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        body: Center(child: Text('Failed to load session: $error')),
      ),
      data: (bundle) {
        if (bundle == null) {
          return const Scaffold(
            body: Center(child: Text('Session not found')),
          );
        }

        final bundleData = bundle;
        final latestQuiz = bundleData.quizzes.isNotEmpty ? bundleData.quizzes.first : null;

        return Scaffold(
          appBar: AppBar(
            title: Text(bundleData.session.title),
            actions: [
              IconButton(
                onPressed: () => context.go('/session/$sessionId/material'),
                icon: const Icon(Icons.library_books_outlined),
              ),
              IconButton(
                onPressed: () => context.go('/session/$sessionId/chat'),
                icon: const Icon(Icons.chat_bubble_outline),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => context.go('/session/$sessionId/material'),
            icon: const Icon(Icons.add),
            label: const Text('Add material'),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
            child: compact
                ? Column(
                    children: [
                      _SessionOverview(bundle: bundleData, latestQuiz: latestQuiz),
                      const SizedBox(height: 16),
                      _SessionActions(sessionId: sessionId, latestQuiz: latestQuiz),
                      const SizedBox(height: 16),
                      _MaterialList(materials: bundleData.materials),
                      const SizedBox(height: 16),
                      _QuizList(sessionId: sessionId, quizzes: bundleData.quizzes),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            _SessionOverview(bundle: bundleData, latestQuiz: latestQuiz),
                            const SizedBox(height: 16),
                            _MaterialList(materials: bundleData.materials),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 420,
                        child: Column(
                          children: [
                            _SessionActions(sessionId: sessionId, latestQuiz: latestQuiz),
                            const SizedBox(height: 16),
                            _QuizList(sessionId: sessionId, quizzes: bundleData.quizzes),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

class _SessionOverview extends StatelessWidget {
  final SessionBundle bundle;
  final Quiz? latestQuiz;

  const _SessionOverview({
    required this.bundle,
    required this.latestQuiz,
  });

  @override
  Widget build(BuildContext context) {
    return QuexPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              QuexAvatar(emoji: bundle.session.emoji, size: 58),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bundle.session.title,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Grade ${bundle.session.gradeOverride} • ${DateFormat.yMMMMd().format(bundle.session.createdAt)}',
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: QuexMetricCard(
                  label: 'Materials',
                  value: '${bundle.materials.length}',
                  icon: Icons.layers_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: QuexMetricCard(
                  label: 'Quizzes',
                  value: '${bundle.quizzes.length}',
                  icon: Icons.quiz_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: QuexMetricCard(
                  label: 'Chat',
                  value: '${bundle.messages.length}',
                  icon: Icons.chat_bubble_outline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Builder(
            builder: (context) {
              final quiz = latestQuiz;
              if (quiz == null) {
                return const Text('No quiz yet. Add notes and generate one.');
              }
              if (quiz.isCompleted) {
                return Text('Latest quiz score: ${quiz.score}/${quiz.questionCount}');
              }
              return const Text('Latest quiz is in progress.');
            },
          ),
        ],
      ),
    );
  }
}

class _SessionActions extends StatelessWidget {
  final int sessionId;
  final Quiz? latestQuiz;

  const _SessionActions({
    required this.sessionId,
    required this.latestQuiz,
  });

  @override
  Widget build(BuildContext context) {
    return QuexPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const QuexSectionHeader(
            title: 'Actions',
            subtitle: 'Move to the next step in the study flow.',
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () => context.go('/session/$sessionId/material'),
                icon: const Icon(Icons.library_books_outlined),
                label: const Text('Materials'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => context.go('/session/$sessionId/processing'),
                icon: const Icon(Icons.auto_fix_high),
                label: Text(latestQuiz == null ? 'Generate quiz' : 'Retry quiz'),
              ),
              OutlinedButton.icon(
                onPressed: () => context.go('/session/$sessionId/chat'),
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('Chat'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MaterialList extends StatelessWidget {
  final List<StudyMaterial> materials;

  const _MaterialList({required this.materials});

  @override
  Widget build(BuildContext context) {
    return QuexPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const QuexSectionHeader(
            title: 'Materials',
            subtitle: 'The notes that power the quiz.',
          ),
          const SizedBox(height: 14),
          if (materials.isEmpty)
            const QuexEmptyState(
              icon: Icons.layers_outlined,
              title: 'No materials yet',
              message: 'Add notes before generating a quiz.',
            )
          else
            ...materials.map(
              (material) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: QuexTonePill(label: '${material.pageIndex + 1}'),
                  title: Text(material.title),
                  subtitle: Text(material.preview),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _QuizList extends StatelessWidget {
  final int sessionId;
  final List<Quiz> quizzes;

  const _QuizList({
    required this.sessionId,
    required this.quizzes,
  });

  @override
  Widget build(BuildContext context) {
    return QuexPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const QuexSectionHeader(
            title: 'Quizzes',
            subtitle: 'Open the latest quiz or review older runs.',
          ),
          const SizedBox(height: 14),
          if (quizzes.isEmpty)
            const Text('No quizzes yet.')
          else
            ...quizzes.map(
              (quiz) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: Icon(
                    quiz.isCompleted ? Icons.check_circle : Icons.pending,
                  ),
                  title: Text('Quiz ${quiz.id}'),
                  subtitle: Text(
                    quiz.isCompleted
                        ? 'Score ${quiz.score}/${quiz.questionCount}'
                        : 'In progress',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go('/session/$sessionId/quiz/${quiz.id}'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
