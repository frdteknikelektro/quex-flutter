import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/breakpoints.dart';
import '../../core/ai/quex_ai.dart';
import '../../core/db/daos.dart';
import '../../core/models/models.dart';
import '../../core/state/app_state.dart';
import '../../widgets/quex_ui.dart';

class ProcessingScreen extends ConsumerStatefulWidget {
  final int sessionId;

  const ProcessingScreen({super.key, required this.sessionId});

  @override
  ConsumerState<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends ConsumerState<ProcessingScreen> {
  bool _generating = false;

  Future<void> _generateQuiz(SessionBundle bundle) async {
    if (bundle.materials.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one material first.')),
      );
      return;
    }

    setState(() => _generating = true);
    final quiz = Quiz(
      sessionId: bundle.session.id!,
      questionCount: bundle.session.questionCount,
      createdAt: DateTime.now(),
    );
    final quizId = await QuizDAO().insert(quiz);
    final questions = QuexAi.buildQuiz(
      session: bundle.session,
      materials: bundle.materials,
      questionCount: bundle.session.questionCount,
    ).map((question) => question.copyWith(quizId: quizId)).toList();
    await QuestionDAO().insertAll(questions);
    if (!mounted) return;

    ref.invalidate(sessionBundleProvider(widget.sessionId));
    setState(() => _generating = false);
    context.go('/session/${widget.sessionId}/quiz/$quizId');
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < QuexBreakpoints.tablet;
    final bundleAsync = ref.watch(sessionBundleProvider(widget.sessionId));

    return bundleAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        body: Center(child: Text('Failed to load processing state: $error')),
      ),
      data: (bundle) {
        if (bundle == null) {
          return const Scaffold(
            body: Center(child: Text('Session not found')),
          );
        }

        final latestQuiz = bundle.quizzes.isNotEmpty ? bundle.quizzes.first : null;
        final highlights = QuexAi.highlights(bundle.materials);

        return Scaffold(
          appBar: AppBar(
            title: Text(bundle.session.title),
            actions: [
              TextButton(
                onPressed: () => context.go('/session/${widget.sessionId}/material'),
                child: const Text('Back'),
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
            child: compact
                ? Column(
                    children: [
                      _ProcessingStatus(
                        session: bundle.session,
                        materialCount: bundle.materials.length,
                        quizCount: bundle.quizzes.length,
                        latestQuiz: latestQuiz,
                        highlights: highlights,
                      ),
                      const SizedBox(height: 16),
                      _ProcessingAction(
                        generating: _generating,
                        onGenerate: _generating ? null : () => _generateQuiz(bundle),
                        onOpenQuiz: latestQuiz == null
                            ? null
                            : () => context.go(
                                  '/session/${widget.sessionId}/quiz/${latestQuiz.id}',
                                ),
                      ),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _ProcessingStatus(
                          session: bundle.session,
                          materialCount: bundle.materials.length,
                          quizCount: bundle.quizzes.length,
                          latestQuiz: latestQuiz,
                          highlights: highlights,
                        ),
                      ),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 360,
                        child: _ProcessingAction(
                          generating: _generating,
                          onGenerate: _generating ? null : () => _generateQuiz(bundle),
                          onOpenQuiz: latestQuiz == null
                              ? null
                              : () => context.go(
                                    '/session/${widget.sessionId}/quiz/${latestQuiz.id}',
                                  ),
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

class _ProcessingStatus extends StatelessWidget {
  final Session session;
  final int materialCount;
  final int quizCount;
  final Quiz? latestQuiz;
  final List<String> highlights;

  const _ProcessingStatus({
    required this.session,
    required this.materialCount,
    required this.quizCount,
    required this.latestQuiz,
    required this.highlights,
  });

  @override
  Widget build(BuildContext context) {
    return QuexPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const QuexSectionHeader(
            title: 'Processing',
            subtitle: 'Turn the session notes into a structured quiz.',
          ),
          const SizedBox(height: 18),
          Text(
            session.title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Grade ${session.gradeOverride} • ${session.questionCount} questions',
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: QuexMetricCard(
                  label: 'Materials',
                  value: '$materialCount',
                  icon: Icons.layers_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: QuexMetricCard(
                  label: 'Quizzes',
                  value: '$quizCount',
                  icon: Icons.quiz_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Highlights',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (highlights.isEmpty)
            const Text('No text-based highlights yet. Add more notes to improve quiz quality.')
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: highlights.map((highlight) => QuexTonePill(label: highlight)).toList(),
            ),
          const SizedBox(height: 20),
          if (latestQuiz != null)
            QuexPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Latest quiz',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    latestQuiz!.isCompleted
                        ? 'Completed • ${latestQuiz!.score}/${latestQuiz!.questionCount}'
                        : 'In progress',
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ProcessingAction extends StatelessWidget {
  final bool generating;
  final VoidCallback? onGenerate;
  final VoidCallback? onOpenQuiz;

  const _ProcessingAction({
    required this.generating,
    required this.onGenerate,
    required this.onOpenQuiz,
  });

  @override
  Widget build(BuildContext context) {
    return QuexPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const QuexSectionHeader(
            title: 'Generate quiz',
            subtitle: 'Use the study engine to create questions from the saved materials.',
          ),
          const SizedBox(height: 18),
          LinearProgressIndicator(value: generating ? null : 1),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onGenerate,
            icon: generating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_fix_high),
            label: Text(generating ? 'Generating...' : 'Generate quiz'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onOpenQuiz,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Open latest quiz'),
          ),
        ],
      ),
    );
  }
}
