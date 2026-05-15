import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../app/router.dart';
import '../../core/ai/question_chat_service.dart';
import '../../core/db/daos.dart';
import '../../core/models/models.dart';
import '../../core/state/app_state.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../widgets/math_markdown.dart';
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

class _QuizDetailScreenState extends ConsumerState<QuizDetailScreen>
    with RouteAware {
  final QuestionChatService _questionChatService = QuestionChatService();
  List<StudyMaterial> _lastMaterials = const [];
  bool _prewarmRequested = false;
  bool _awaitingQuestionCleanup = false;
  bool _routeSubscribed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (!_routeSubscribed && route is PageRoute<dynamic>) {
      routeObserver.subscribe(this, route);
      _routeSubscribed = true;
    }
  }

  @override
  void didPushNext() {
    _awaitingQuestionCleanup = true;
    _prewarmRequested = false;
  }

  @override
  void didPopNext() {
    debugPrint('[QuizDetailScreen] Returned from question, starting prewarm');
    _warmAfterQuestionCleanup(_lastMaterials);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    unawaited(_questionChatService.dispose());
    super.dispose();
  }

  void _startPrewarm(List<StudyMaterial> materials) {
    if (_prewarmRequested) return;
    _prewarmRequested = true;

    final l10n = AppLocalizations.of(context);
    final locale = l10n?.localeName ?? 'en';

    unawaited(_questionChatService
        .prewarmSession(
      materials: materials,
      locale: locale,
      isThinking: false,
    )
        .catchError((Object e) {
      debugPrint('Failed to prewarm question tutor session: $e');
      _prewarmRequested = false;
    }));
  }

  void _warmAfterQuestionCleanup(List<StudyMaterial> materials) {
    unawaited(() async {
      await _questionChatService.waitForQuestionTurnToEnd();
      if (!mounted) return;
      _awaitingQuestionCleanup = false;
      _startPrewarm(materials);
    }());
  }

  Future<void> _handleFinishQuiz(List<Question> questions) async {
    final scored = questions.where((q) => q.score != null).toList();
    if (scored.isEmpty) return;

    final totalScore = scored.fold(0.0, (sum, q) => sum + q.score!);
    final finalScore = (totalScore / questions.length * 100).round();

    await QuizDAO().complete(widget.quizId, finalScore);
    ref.invalidate(sessionBundleProvider(widget.sessionId));

    if (!mounted) return;
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bundle = ref.watch(quizBundleProvider(widget.quizId));
    final materialsAsync = ref.watch(materialsProvider(widget.sessionId));
    final materials = materialsAsync.valueOrNull ?? const <StudyMaterial>[];
    _lastMaterials = materials;
    if (materialsAsync.hasValue && !_awaitingQuestionCleanup) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startPrewarm(materials);
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.quizDetailTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: bundle.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            Center(child: Text(l10n.quizDetailError(e.toString()))),
        data: (b) {
          if (b == null) {
            return QuexEmptyState(
              icon: Icons.quiz_outlined,
              title: l10n.quizDetailNotFound,
              message: l10n.quizDetailDeleted,
            );
          }

          final questions = b.questions;
          final scored = questions.where((q) => q.score != null).toList();
          final totalScore = scored.isEmpty
              ? null
              : scored.fold(0.0, (sum, q) => sum + q.score!) / questions.length;

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                  child: _ScoreHeader(
                    quiz: b.quiz,
                    totalScore: totalScore,
                    answered: scored.length,
                    total: questions.length,
                    scheme: scheme,
                    theme: theme,
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _QuestionTile(
                        question: questions[index],
                        index: index,
                        sessionId: widget.sessionId,
                        quizId: widget.quizId,
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
      floatingActionButton: bundle.maybeWhen(
        data: (b) => b != null && b.questions.isNotEmpty
            ? FloatingActionButton.extended(
                onPressed: () => _handleFinishQuiz(b.questions),
                icon: const Icon(Icons.check_circle),
                label: Text(l10n.quizDetailFinish),
              )
            : null,
        orElse: () => null,
      ),
    );
  }
}

class _ScoreHeader extends StatelessWidget {
  final Quiz quiz;
  final double? totalScore;
  final int answered;
  final int total;
  final ColorScheme scheme;
  final ThemeData theme;

  const _ScoreHeader({
    required this.quiz,
    required this.totalScore,
    required this.answered,
    required this.total,
    required this.scheme,
    required this.theme,
  });

  String _formatDate(DateTime dt, BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(date).inDays;
    if (diff == 0) return l10n.quizDetailToday;
    if (diff == 1) return l10n.quizDetailYesterday;
    if (dt.year == now.year) return DateFormat('MMM d').format(dt);
    return DateFormat('MMM d, y').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _formatDate(quiz.createdAt, context),
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.quizDetailQuestionsCount(total),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.quizDetailAnswered(answered),
                    style: theme.textTheme.bodyMedium?.copyWith(
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
      ],
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
  final ColorScheme scheme;
  final ThemeData theme;

  const _QuestionTile({
    required this.question,
    required this.index,
    required this.sessionId,
    required this.quizId,
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
    if (question.id == null) return;
    context.push('/session/$sessionId/quiz/$quizId/question/${question.id}');
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: question.id == null ? 0.5 : 1.0,
      child: Card(
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerLow,
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _onTap(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${index + 1}.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                      height: 1.35),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MathMarkdownBody(
                        data: question.questionText,
                        styleSheet:
                            MarkdownStyleSheet.fromTheme(theme).copyWith(
                          p: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface,
                            height: 1.35,
                          ),
                        ),
                        textStyle: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _scoreBadge(question.score),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
