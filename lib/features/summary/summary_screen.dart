import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/breakpoints.dart';
import '../../core/models/models.dart';
import '../../core/state/app_state.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../widgets/quex_ui.dart';
import '../processing/quiz_generation_modal.dart';

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
    final l10n = AppLocalizations.of(context)!;
    final bundleAsync = ref.watch(quizBundleProvider(quizId));
    final sessionAsync = ref.watch(sessionBundleProvider(sessionId));
    final compact = MediaQuery.sizeOf(context).width < QuexBreakpoints.tablet;

    return bundleAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        body: Center(child: Text(l10n.summaryFailedToLoad(error.toString()))),
      ),
      data: (bundle) {
        if (bundle == null) {
          return Scaffold(
            body: Center(child: Text(l10n.summaryQuizNotFound)),
          );
        }

        final score = bundle.quiz.score ??
            bundle.questions.where((q) => (q.score ?? 0) >= 0.5).length;

        return sessionAsync.when(
          loading: () => const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => Scaffold(
            body: Center(child: Text(l10n.summaryFailedToLoadSession(error.toString()))),
          ),
          data: (sessionBundle) {
            final session = sessionBundle?.session;
            return Scaffold(
              appBar: AppBar(
                title: Text(l10n.summaryTitle),
                actions: [
                  TextButton(
                    onPressed: () => context.go('/session/$sessionId/chat'),
                    child: Text(l10n.summaryChat),
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
                            sessionTitle: session?.title ?? l10n.summarySession,
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
                                  sessionTitle: session?.title ?? l10n.summarySession,
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
    final l10n = AppLocalizations.of(context)!;
    final percent = total == 0 ? 0.0 : score / total;
    return QuexPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          QuexSectionHeader(
            title: l10n.summaryResults,
            subtitle: l10n.summaryResultsSubtitle,
          ),
          const SizedBox(height: 16),
          Text(
            sessionTitle,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 8),
          Text(quizCompleted ? l10n.summaryQuizCompleted : l10n.summaryQuizInProgress),
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
                        Text(l10n.summaryOf(total)),
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
                  label: l10n.summaryCorrect,
                  value: '$score',
                  icon: Icons.check_circle_outline,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: QuexMetricCard(
                  label: l10n.summaryTotal,
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
    final l10n = AppLocalizations.of(context)!;
    return QuexPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          QuexSectionHeader(
            title: l10n.summaryNextSteps,
            subtitle: l10n.summaryNextStepsSubtitle,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () => context.go('/session/$sessionId/chat'),
                icon: const Icon(Icons.chat_bubble_outline),
                label: Text(l10n.summaryDiscuss),
              ),
              FilledButton.tonalIcon(
                onPressed: () => showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => QuizGenerationModal(sessionId: sessionId),
                ),
                icon: const Icon(Icons.replay_outlined),
                label: Text(l10n.summaryRetryQuiz),
              ),
              OutlinedButton.icon(
                onPressed: () => context.go('/session/$sessionId'),
                icon: const Icon(Icons.open_in_new),
                label: Text(l10n.summarySessionDetails),
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
    final l10n = AppLocalizations.of(context)!;
    final missed = questions.where((q) => q.score != null && q.score! < 0.5).toList();

    return QuexPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          QuexSectionHeader(
            title: l10n.summaryReview,
            subtitle: l10n.summaryReviewSubtitle,
          ),
          const SizedBox(height: 16),
          if (missed.isEmpty)
            Text(l10n.summaryNoMissed)
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
                      Text(l10n.summaryYourAnswer(question.userAnswerText ?? question.userAnswer ?? '—')),
                      const SizedBox(height: 8),
                      Text(
                        l10n.summaryChatToLearn,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontStyle: FontStyle.italic,
                        ),
                      ),
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
