import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/breakpoints.dart';
import '../../core/models/models.dart';
import '../../core/state/app_state.dart';
import '../../widgets/quex_ui.dart';

class SummaryScreen extends ConsumerWidget {
  final int sessionId;
  final int quizId;

  const SummaryScreen({
    super.key,
    required this.sessionId,
    required this.quizId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bundleAsync = ref.watch(quizBundleProvider(quizId));
    final sessionAsync = ref.watch(sessionBundleProvider(sessionId));
    final compact = MediaQuery.sizeOf(context).width < QuexBreakpoints.tablet;

    return bundleAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        body: Center(child: Text('Failed to load summary: $error')),
      ),
      data: (bundle) {
        if (bundle == null) {
          return const Scaffold(
            body: Center(child: Text('Quiz not found')),
          );
        }

        final score = bundle.quiz.score ?? bundle.questions.where((question) {
          final answer = question.userAnswer;
          return answer != null && answer == question.correctOption;
        }).length;

        return sessionAsync.when(
          loading: () => const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => Scaffold(
            body: Center(child: Text('Failed to load session: $error')),
          ),
          data: (sessionBundle) {
            final session = sessionBundle?.session;
            return Scaffold(
              appBar: AppBar(
                title: const Text('Summary'),
                actions: [
                  TextButton(
                    onPressed: () => context.go('/session/$sessionId/chat'),
                    child: const Text('Chat'),
                  ),
                ],
              ),
              body: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                child: compact
                    ? Column(
                        children: [
                          _SummaryHero(
                            score: score,
                            total: bundle.questions.length,
                            quizCompleted: bundle.quiz.isCompleted,
                            sessionTitle: session?.title ?? 'Session',
                          ),
                          const SizedBox(height: 16),
                          _SummaryActions(sessionId: sessionId, quizId: quizId),
                          const SizedBox(height: 16),
                          _MissedQuestions(questions: bundle.questions),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                _SummaryHero(
                                  score: score,
                                  total: bundle.questions.length,
                                  quizCompleted: bundle.quiz.isCompleted,
                                  sessionTitle: session?.title ?? 'Session',
                                ),
                                const SizedBox(height: 16),
                                _SummaryActions(sessionId: sessionId, quizId: quizId),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _MissedQuestions(questions: bundle.questions),
                          ),
                        ],
                      ),
              ),
            );
          },
        );
      },
    );
  }
}

class _SummaryHero extends StatelessWidget {
  final int score;
  final int total;
  final bool quizCompleted;
  final String sessionTitle;

  const _SummaryHero({
    required this.score,
    required this.total,
    required this.quizCompleted,
    required this.sessionTitle,
  });

  @override
  Widget build(BuildContext context) {
    final percent = total == 0 ? 0.0 : score / total;
    return QuexPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const QuexSectionHeader(
            title: 'Results',
            subtitle: 'Review the quiz and keep the learning loop going.',
          ),
          const SizedBox(height: 16),
          Text(
            sessionTitle,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 8),
          Text(quizCompleted ? 'Quiz completed' : 'Quiz still in progress'),
          const SizedBox(height: 20),
          Center(
            child: SizedBox(
              width: 180,
              height: 180,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(value: percent, strokeWidth: 14),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$score',
                          style: Theme.of(context).textTheme.displaySmall?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        Text('of $total'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: QuexMetricCard(
                  label: 'Correct',
                  value: '$score',
                  icon: Icons.check_circle_outline,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: QuexMetricCard(
                  label: 'Total',
                  value: '$total',
                  icon: Icons.quiz_outlined,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryActions extends StatelessWidget {
  final int sessionId;
  final int quizId;

  const _SummaryActions({
    required this.sessionId,
    required this.quizId,
  });

  @override
  Widget build(BuildContext context) {
    return QuexPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const QuexSectionHeader(
            title: 'Next steps',
            subtitle: 'Keep the session moving forward.',
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () => context.go('/session/$sessionId/chat'),
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('Discuss'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => context.go('/session/$sessionId/processing'),
                icon: const Icon(Icons.replay_outlined),
                label: const Text('Retry quiz'),
              ),
              OutlinedButton.icon(
                onPressed: () => context.go('/session/$sessionId'),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Session details'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MissedQuestions extends StatelessWidget {
  final List<Question> questions;

  const _MissedQuestions({required this.questions});

  @override
  Widget build(BuildContext context) {
    final missed = questions.where((question) {
      final answer = question.userAnswer;
      return answer != null && answer != question.correctOption;
    }).toList();

    return QuexPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const QuexSectionHeader(
            title: 'Review',
            subtitle: 'Focus on the questions that need another pass.',
          ),
          const SizedBox(height: 16),
          if (missed.isEmpty)
            const Text('No missed questions. Nice work.')
          else
            ...missed.map(
              (question) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: QuexPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        question.questionText,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 10),
                      Text('Your answer: ${question.userAnswer}'),
                      Text('Correct answer: ${question.correctOption}'),
                      const SizedBox(height: 10),
                      Text(question.explanation),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
