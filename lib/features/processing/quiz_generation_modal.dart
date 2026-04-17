import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/ai/gemma_inference_service.dart';
import '../../core/ai/quiz_generation_event.dart';
import '../../core/ai/quex_ai.dart';
import '../../core/db/daos.dart';
import '../../core/models/models.dart';
import '../../core/state/app_state.dart';
import 'quiz_results_debug_screen.dart';

class QuizGenerationModal extends ConsumerStatefulWidget {
  final int sessionId;

  const QuizGenerationModal({super.key, required this.sessionId});

  @override
  ConsumerState<QuizGenerationModal> createState() => _QuizGenerationModalState();
}

class _QuizGenerationModalState extends ConsumerState<QuizGenerationModal> {
  final _thinkingBuffer = StringBuffer();
  final _generatedQuestions = <String>[];
  final _scrollController = ScrollController();

  bool _isThinking = false;
  bool _isComplete = false;
  bool _isLoading = false;
  int _generatedCount = 0;
  int _totalCount = 0;
  StreamSubscription<QuizGenerationEvent>? _subscription;
  int? _quizId;
  GemmaInferenceService? _gemmaService;

  @override
  void initState() {
    super.initState();
    _startGeneration();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _gemmaService?.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _startGeneration() async {
    final bundle = await ref.read(sessionBundleProvider(widget.sessionId).future);
    if (!mounted || bundle == null) return;
    if (bundle.materials.isEmpty) {
      _showErrorAndPop('Add study materials first.');
      return;
    }

    if (_quizId == null) {
      final quizId = await QuizDAO().insert(Quiz(
        sessionId: bundle.session.id!,
        questionCount: bundle.session.questionCount,
        createdAt: DateTime.now(),
      ));
      if (!mounted) return;
      setState(() => _quizId = quizId);
    }

    try {
      setState(() => _isLoading = true);
      final service = GemmaInferenceService();
      await service.initialize();
      if (!mounted) {
        await service.dispose();
        return;
      }
      _gemmaService = service;
      QuexAi.setGemmaService(service);
      setState(() => _isLoading = false);

      final stream = service.generateQuizStreaming(
        session: bundle.session,
        materials: bundle.materials,
        questionCount: bundle.session.questionCount,
      );

      _subscription = stream.listen(
        _handleEvent,
        onError: (Object e) => _showErrorAndPop(e.toString()),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showErrorAndPop(e.toString());
      return;
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showErrorAndPop(String message) {
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Quiz generation failed: $message')),
    );
  }

  void _handleEvent(QuizGenerationEvent event) {
    if (!mounted) return;
    switch (event) {
      case QuizThinkingToken(:final token):
        setState(() {
          _isThinking = true;
          _thinkingBuffer.write(token);
        });
        _scrollToBottom();
      case QuizTextToken():
        // text tokens not displayed — thinking + question list is sufficient
        break;
      case QuizGenerationStarted(:final total):
        setState(() => _totalCount = total);
      case QuizQuestionGenerated(:final question, :final index, :final total):
        setState(() {
          _isThinking = false;
          _generatedCount = index;
          _totalCount = total;
          _generatedQuestions.add('Q$index: ${question.questionText}');
        });
        _scrollToBottom();
      case QuizGenerationComplete(:final questions):
        _saveAndNavigate(questions);
      case QuizGenerationError(:final message):
        _showErrorAndPop(message);
    }
  }

  Future<void> _saveAndNavigate(List<Question> questions) async {
    final qid = _quizId;
    if (qid == null || !mounted) return;

    final withId = questions.map((q) => q.copyWith(quizId: qid)).toList();
    await QuestionDAO().insertAll(withId);
    if (!mounted) return;

    setState(() => _isComplete = true);

    _gemmaService?.dispose();
    _gemmaService = null;
    QuexAi.setGemmaService(null);

    ref.invalidate(sessionBundleProvider(widget.sessionId));

    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QuizResultsDebugScreen(
          sessionId: widget.sessionId,
          quizId: qid,
          questions: withId,
        ),
      ),
    );
  }

  void _cancel() {
    _subscription?.cancel();
    _subscription = null;
    _gemmaService?.dispose();
    _gemmaService = null;
    QuexAi.setGemmaService(null);
    if (mounted) Navigator.of(context).pop();
  }

  String _statusText() {
    if (_isLoading) return 'Loading brain...';
    if (_isComplete) return 'Quiz is ready! 🎉';
    if (_totalCount > 0) return 'Question $_generatedCount of $_totalCount';
    if (_isThinking) return 'Quex is thinking...';
    return 'Getting ready...';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final hasStream = _thinkingBuffer.isNotEmpty || _generatedQuestions.isNotEmpty;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // [A] Close row — single cancel control
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                icon: const Icon(Icons.close),
                onPressed: _cancel,
              ),
            ),

            const Spacer(flex: 1),

            // [B] Brain + status
            Column(
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, anim) => ScaleTransition(
                    scale: anim,
                    child: FadeTransition(opacity: anim, child: child),
                  ),
                  child: _isComplete
                      ? Icon(
                          Icons.check_circle_rounded,
                          key: const ValueKey('check'),
                          size: 64,
                          color: scheme.primary,
                        )
                      : _PulsingBrain(
                          key: const ValueKey('brain'),
                          isComplete: _isComplete,
                        ),
                ),
                const SizedBox(height: 16),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    _statusText(),
                    key: ValueKey(_statusText()),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),

            // [C] Streaming panel — fixed 240dp, terminal-style scroll
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Sp.md),
              child: AnimatedOpacity(
                opacity: hasStream ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: SizedBox(
                  height: 240,
                  child: Container(
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: Br.md,
                    ),
                    child: ListView(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(12),
                      children: [
                        if (_thinkingBuffer.isNotEmpty)
                          Text(
                            _thinkingBuffer.toString(),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        if (_thinkingBuffer.isNotEmpty && _generatedQuestions.isNotEmpty)
                          const Divider(height: 16),
                        ..._generatedQuestions.map(
                          (q) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(
                              q,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // [D] Progress bar — primary colors, dark-mode safe
            if (!_isComplete)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Sp.md),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    minHeight: 6,
                    value: _totalCount > 0 ? _generatedCount / _totalCount : null,
                    backgroundColor: scheme.primaryContainer,
                    valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
                  ),
                ),
              ),

            const Spacer(flex: 1),
          ],
        ),
      ),
    );
  }
}


class _PulsingBrain extends StatefulWidget {
  final bool isComplete;

  const _PulsingBrain({super.key, required this.isComplete});

  @override
  State<_PulsingBrain> createState() => _PulsingBrainState();
}

class _PulsingBrainState extends State<_PulsingBrain>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );
  }

  @override
  void didUpdateWidget(_PulsingBrain oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isComplete && !oldWidget.isComplete) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: const Text('🧠', style: TextStyle(fontSize: 64)),
    );
  }
}
