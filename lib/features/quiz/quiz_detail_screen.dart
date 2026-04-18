import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/ai/gemma_inference_service.dart';
import '../../core/ai/quex_ai.dart';
import '../../core/models/models.dart';
import '../../core/state/app_state.dart';
import '../../widgets/quex_ui.dart';

class QuizDetailScreen extends ConsumerStatefulWidget {
  final int sessionId;
  final int quizId;

  const QuizDetailScreen({
    super.key,
    required this.sessionId,
    required this.quizId,
  });

  @override
  ConsumerState<QuizDetailScreen> createState() => _QuizDetailScreenState();
}

class _QuizDetailScreenState extends ConsumerState<QuizDetailScreen> {
  GemmaInferenceService? _gemmaService;
  bool _modelLoading = true;
  String? _modelError;

  @override
  void initState() {
    super.initState();
    _loadModel();
  }

  Future<void> _loadModel() async {
    setState(() {
      _modelLoading = true;
      _modelError = null;
    });
    try {
      final service = GemmaInferenceService();
      await service.initialize();
      if (!mounted) {
        await service.dispose();
        return;
      }
      _gemmaService = service;
      QuexAi.setGemmaService(service);
      setState(() => _modelLoading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _modelLoading = false;
        _modelError = e.toString();
      });
    }
  }

  @override
  void dispose() {
    if (_gemmaService != null) {
      _gemmaService!.dispose();
      QuexAi.setGemmaService(null);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bundle = ref.watch(quizBundleProvider(widget.quizId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quiz Questions'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: Column(
        children: [
          // Model loading / error banner
          if (_modelLoading)
            _ModelBanner(
              scheme: scheme,
              isError: false,
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Loading Quex brain…',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSecondaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            )
          else if (_modelError != null)
            _ModelBanner(
              scheme: scheme,
              isError: true,
              child: Row(
                children: [
                  Icon(Icons.error_outline,
                      size: 16, color: scheme.onErrorContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Failed to load brain. Tap to retry.',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onErrorContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _loadModel,
                    child: Icon(Icons.refresh,
                        size: 18, color: scheme.onErrorContainer),
                  ),
                ],
              ),
            ),
          // Question list
          Expanded(
            child: bundle.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (b) {
                if (b == null) {
                  return const QuexEmptyState(
                    icon: Icons.quiz_outlined,
                    title: 'Quiz not found',
                    message: 'This quiz may have been deleted.',
                  );
                }

                final questions = b.questions;
                final scored =
                    questions.where((q) => q.score != null).toList();
                final totalScore = scored.isEmpty
                    ? null
                    : scored.fold(0.0, (sum, q) => sum + q.score!) /
                        questions.length;

                return CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding:
                            const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: _ScoreHeader(
                          totalScore: totalScore,
                          answered: scored.length,
                          total: questions.length,
                          modelLoading: _modelLoading,
                          scheme: scheme,
                          theme: theme,
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding:
                          const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => Padding(
                            padding:
                                const EdgeInsets.only(bottom: 10),
                            child: _QuestionTile(
                              question: questions[index],
                              index: index,
                              sessionId: widget.sessionId,
                              quizId: widget.quizId,
                              modelLoading: _modelLoading,
                              scheme: scheme,
                              theme: theme,
                            ),
                          ),
                          childCount: questions.length,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelBanner extends StatelessWidget {
  final Widget child;
  final ColorScheme scheme;
  final bool isError;

  const _ModelBanner({
    required this.child,
    required this.scheme,
    required this.isError,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: isError ? scheme.errorContainer : scheme.secondaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: SafeArea(bottom: false, child: child),
    );
  }
}

class _ScoreHeader extends StatelessWidget {
  final double? totalScore;
  final int answered;
  final int total;
  final bool modelLoading;
  final ColorScheme scheme;
  final ThemeData theme;

  const _ScoreHeader({
    required this.totalScore,
    required this.answered,
    required this.total,
    required this.modelLoading,
    required this.scheme,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return QuexPanel(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$total Questions',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  modelLoading
                      ? 'Loading Quex brain before you can chat…'
                      : totalScore == null
                          ? 'Tap a question to start chatting with Quex!'
                          : '$answered answered · tap any to continue',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (totalScore != null) ...[
            const SizedBox(width: 16),
            _ScoreRing(score: totalScore!, scheme: scheme, theme: theme),
          ],
        ],
      ),
    );
  }
}

class _ScoreRing extends StatelessWidget {
  final double score;
  final ColorScheme scheme;
  final ThemeData theme;

  const _ScoreRing({
    required this.score,
    required this.scheme,
    required this.theme,
  });

  Color _scoreColor(double s) {
    if (s >= 0.8) return const Color(0xFF4CAF50);
    if (s >= 0.5) return const Color(0xFFFFB347);
    return const Color(0xFFFF6B6B);
  }

  @override
  Widget build(BuildContext context) {
    final color = _scoreColor(score);
    final percent = (score * 100).round();
    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: score,
            strokeWidth: 5,
            backgroundColor: scheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation(color),
          ),
          Text(
            '$percent%',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuestionTile extends StatelessWidget {
  final Question question;
  final int index;
  final int sessionId;
  final int quizId;
  final bool modelLoading;
  final ColorScheme scheme;
  final ThemeData theme;

  const _QuestionTile({
    required this.question,
    required this.index,
    required this.sessionId,
    required this.quizId,
    required this.modelLoading,
    required this.scheme,
    required this.theme,
  });

  Color? _scoreColor(double? score) {
    if (score == null) return null;
    if (score >= 0.8) return const Color(0xFF4CAF50);
    if (score >= 0.4) return const Color(0xFFFFB347);
    return const Color(0xFFFF6B6B);
  }

  Widget _scoreBadge(double? score) {
    final color = _scoreColor(score);
    if (score == null) {
      return Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: scheme.outlineVariant,
        ),
      );
    }
    IconData icon;
    if (score >= 0.8) {
      icon = Icons.check_circle;
    } else if (score >= 0.4) {
      icon = Icons.remove_circle;
    } else {
      icon = Icons.cancel;
    }
    return Icon(icon, size: 18, color: color);
  }

  void _onTap(BuildContext context) {
    if (modelLoading) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Still loading… please wait a moment.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    if (question.id == null) return;
    context.push('/session/$sessionId/quiz/$quizId/question/${question.id}');
  }

  @override
  Widget build(BuildContext context) {
    final disabled = modelLoading || question.id == null;
    return Opacity(
      opacity: modelLoading ? 0.5 : 1.0,
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          borderRadius: Br.lg,
          onTap: disabled ? () => _onTap(context) : () => _onTap(context),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${index + 1}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest,
                              borderRadius: Br.full,
                            ),
                            child: Text(
                              question.type == QuestionType.multipleChoice
                                  ? 'Multiple choice'
                                  : 'Text answer',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const Spacer(),
                          _scoreBadge(question.score),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        question.questionText,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (question.score != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          question.score! >= 0.8
                              ? 'Correct!'
                              : question.score! >= 0.4
                                  ? 'Partial credit'
                                  : 'Needs review',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: _scoreColor(question.score),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ] else ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Text(
                              'Tap to discuss with Quex',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.primary,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.chevron_right,
                                size: 14, color: scheme.primary),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
