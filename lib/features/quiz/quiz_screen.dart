import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/breakpoints.dart';
import '../../core/db/daos.dart';
import '../../core/models/models.dart';
import '../../core/state/app_state.dart';
import '../../widgets/quex_ui.dart';

class QuizScreen extends ConsumerStatefulWidget {
  final int sessionId;
  final int quizId;

  const QuizScreen({
    super.key,
    required this.sessionId,
    required this.quizId,
  });

  @override
  ConsumerState<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends ConsumerState<QuizScreen> {
  int _currentIndex = 0;
  final Map<int, String> _answers = {};
  bool _submitting = false;
  int? _loadedQuizId;

  Future<void> _answerQuestion(Question question, String answer) async {
    setState(() => _answers[question.id ?? question.orderIndex] = answer);
    if (question.id != null) {
      await QuestionDAO().saveAnswer(question.id!, answer);
      ref.invalidate(quizBundleProvider(widget.quizId));
    }
  }

  Future<void> _submitQuiz(List<Question> questions) async {
    setState(() => _submitting = true);
    for (final question in questions) {
      final answer = _answers[question.id ?? question.orderIndex];
      if (answer != null && question.id != null) {
        await QuestionDAO().saveAnswer(question.id!, answer);
      }
    }
    final score = questions
        .where((q) => _answers[q.id ?? q.orderIndex] == q.correctAnswer)
        .length;
    await QuizDAO().complete(widget.quizId, score);
    if (!mounted) return;
    ref.invalidate(quizBundleProvider(widget.quizId));
    ref.invalidate(sessionBundleProvider(widget.sessionId));
    setState(() => _submitting = false);
    context.go('/session/${widget.sessionId}/quiz/${widget.quizId}/summary');
  }

  @override
  Widget build(BuildContext context) {
    final bundleAsync = ref.watch(quizBundleProvider(widget.quizId));
    final compact = MediaQuery.sizeOf(context).width < QuexBreakpoints.tablet;

    return bundleAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        body: Center(child: Text('Failed to load quiz: $error')),
      ),
      data: (bundle) {
        if (bundle == null) {
          return const Scaffold(
            body: Center(child: Text('Quiz not found')),
          );
        }

        if (_loadedQuizId != bundle.quiz.id) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              _loadedQuizId = bundle.quiz.id;
              _currentIndex = 0;
              _answers.clear();
              for (final question in bundle.questions) {
                if (question.userAnswer != null) {
                  _answers[question.id ?? question.orderIndex] = question.userAnswer!;
                }
              }
            });
          });
        }

        final currentIndex = bundle.questions.isEmpty
            ? 0
            : _currentIndex.clamp(0, bundle.questions.length - 1).toInt();
        final question = bundle.questions[currentIndex];
        final progress = bundle.questions.isEmpty
            ? 0.0
            : (currentIndex + 1) / bundle.questions.length;

        return Scaffold(
          appBar: AppBar(
            title: Text('Quiz ${bundle.quiz.id}'),
            actions: [
              TextButton(
                onPressed: () => context.go('/session/${widget.sessionId}'),
                child: const Text('Session'),
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
            child: compact
                ? Column(
                    children: [
                      _QuizHeader(
                        progress: progress,
                        completed: _answers.length,
                        total: bundle.questions.length,
                        quiz: bundle.quiz,
                      ),
                      const SizedBox(height: 16),
                      _QuestionCard(
                        key: ValueKey(question.id ?? question.orderIndex),
                        question: question,
                        selected: _answers[question.id ?? question.orderIndex],
                        onAnswer: (value) => _answerQuestion(question, value),
                      ),
                      const SizedBox(height: 16),
                      _QuestionFooter(
                        currentIndex: currentIndex,
                        total: bundle.questions.length,
                        submitting: _submitting,
                        onPrevious: currentIndex == 0
                            ? null
                            : () => setState(() => _currentIndex = currentIndex - 1),
                        onNext: currentIndex == bundle.questions.length - 1
                            ? null
                            : () => setState(() => _currentIndex = currentIndex + 1),
                        onSubmit: _submitting
                            ? null
                            : () => _submitQuiz(bundle.questions),
                      ),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 280,
                        child: _QuestionRail(
                          questions: bundle.questions,
                          currentIndex: currentIndex,
                          onSelect: (index) => setState(() => _currentIndex = index),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          children: [
                            _QuizHeader(
                              progress: progress,
                              completed: _answers.length,
                              total: bundle.questions.length,
                              quiz: bundle.quiz,
                            ),
                            const SizedBox(height: 16),
                            _QuestionCard(
                              question: question,
                              selected: _answers[question.id ?? question.orderIndex],
                              onAnswer: (value) => _answerQuestion(question, value),
                            ),
                            const SizedBox(height: 16),
                            _QuestionFooter(
                              currentIndex: currentIndex,
                              total: bundle.questions.length,
                              submitting: _submitting,
                              onPrevious: currentIndex == 0
                                  ? null
                                  : () => setState(() => _currentIndex = currentIndex - 1),
                              onNext: currentIndex == bundle.questions.length - 1
                                  ? null
                                  : () => setState(() => _currentIndex = currentIndex + 1),
                              onSubmit: _submitting
                                  ? null
                                  : () => _submitQuiz(bundle.questions),
                            ),
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

class _QuizHeader extends StatelessWidget {
  final double progress;
  final int completed;
  final int total;
  final Quiz quiz;

  const _QuizHeader({
    required this.progress,
    required this.completed,
    required this.total,
    required this.quiz,
  });

  @override
  Widget build(BuildContext context) {
    return QuexPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const QuexSectionHeader(
            title: 'Quiz time',
            subtitle: 'Answer each question and submit when you are done.',
          ),
          const SizedBox(height: 16),
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 12),
          Text('$completed of $total answered'),
          if (quiz.isCompleted) ...[
            const SizedBox(height: 8),
            Text('Completed score: ${quiz.score}/${quiz.questionCount}'),
          ],
        ],
      ),
    );
  }
}

class _QuestionRail extends StatelessWidget {
  final List<Question> questions;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  const _QuestionRail({
    required this.questions,
    required this.currentIndex,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return QuexPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const QuexSectionHeader(
            title: 'Questions',
            subtitle: 'Jump between questions quickly on tablet.',
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(questions.length, (index) {
              final selected = index == currentIndex;
              return ChoiceChip(
                label: Text('${index + 1}'),
                selected: selected,
                onSelected: (_) => onSelect(index),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _QuestionCard extends StatefulWidget {
  final Question question;
  final String? selected;
  final ValueChanged<String> onAnswer;

  const _QuestionCard({
    super.key,
    required this.question,
    required this.selected,
    required this.onAnswer,
  });

  @override
  State<_QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends State<_QuestionCard> {
  late final TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(
      text: widget.question.type == QuestionType.textAnswer
          ? (widget.selected ?? '')
          : '',
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final letters = ['A', 'B', 'C', 'D', 'E', 'F'];

    return QuexPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Question ${widget.question.orderIndex + 1}',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.primary,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.question.questionText,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 18),
          if (widget.question.type == QuestionType.textAnswer) ...[
            TextField(
              controller: _textController,
              decoration: const InputDecoration(
                labelText: 'Your answer',
                hintText: 'Type your answer here...',
              ),
              onChanged: widget.onAnswer,
            ),
          ] else ...[
            ...widget.question.options.asMap().entries.map((entry) {
              final letter = letters[entry.key];
              final text = entry.value;
              final isSelected = widget.selected == letter;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => widget.onAnswer(letter),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isSelected ? scheme.primary : scheme.outlineVariant,
                        width: isSelected ? 2 : 1,
                      ),
                      color: isSelected
                          ? scheme.primaryContainer.withValues(alpha: 0.4)
                          : scheme.surfaceContainerLow,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        QuexTonePill(label: letter),
                        const SizedBox(width: 12),
                        Expanded(child: Text(text)),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
          if (widget.selected != null) ...[
            const SizedBox(height: 12),
            Text(
              widget.question.explanation,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _QuestionFooter extends StatelessWidget {
  final int currentIndex;
  final int total;
  final bool submitting;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onSubmit;

  const _QuestionFooter({
    required this.currentIndex,
    required this.total,
    required this.submitting,
    required this.onPrevious,
    required this.onNext,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return QuexPanel(
      child: Row(
        children: [
          OutlinedButton.icon(
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left),
            label: const Text('Previous'),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
            label: const Text('Next'),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: onSubmit,
            icon: submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.done),
            label: Text(submitting ? 'Submitting...' : 'Finish quiz'),
          ),
        ],
      ),
    );
  }
}
