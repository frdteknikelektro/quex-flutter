import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/ai/gemma_inference_service.dart';
import '../../core/ai/gemma_service_host.dart';
import '../../core/ai/gemma_quiz_service.dart';
import '../../core/ai/quiz_generation_event.dart';
import '../../core/db/daos.dart';
import '../../core/models/models.dart';
import '../../core/state/app_state.dart';

enum _ModalStep { materialSelection, detecting, generating, complete }

class QuizGenerationModal extends ConsumerStatefulWidget {
  final int sessionId;
  final GemmaInferenceService Function()? gemmaServiceFactory;

  const QuizGenerationModal({
    super.key,
    required this.sessionId,
    this.gemmaServiceFactory,
  });

  @override
  ConsumerState<QuizGenerationModal> createState() =>
      _QuizGenerationModalState();
}

class _QuizGenerationModalState extends ConsumerState<QuizGenerationModal> {
  final _thinkingBuffer = StringBuffer();
  final _currentQuestionBuffer = StringBuffer();
  final _generatedQuestions = <String>[];
  List<String> _planSteps = [];
  final Set<int> _completedSteps = {};
  final _scrollController = ScrollController();
  late final GemmaServiceHost _gemmaHost;

  _ModalStep _step = _ModalStep.materialSelection;
  List<StudyMaterial> _allMaterials = [];
  Set<int> _selectedIds = {};

  bool _isThinking = false;
  bool _isComplete = false;
  bool _isLoadingModel = false;
  int _generatedCount = 0;
  int _totalCount = 0;
  String _extractedQuestionText = '';
  StreamSubscription<QuizGenerationEvent>? _subscription;
  int? _quizId;
  GemmaQuizService? _quizService;
  Session? _session;

  @override
  void initState() {
    super.initState();
    _gemmaHost = GemmaServiceHost(
      service: widget.gemmaServiceFactory?.call(),
    );
    _loadMaterials();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    unawaited(_gemmaHost.dispose());
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMaterials() async {
    final bundle =
        await ref.read(sessionBundleProvider(widget.sessionId).future);
    if (!mounted || bundle == null) return;
    if (bundle.materials.isEmpty) {
      _showErrorAndPop('Add study materials first.');
      return;
    }
    setState(() {
      _allMaterials = bundle.materials;
      _selectedIds = {};
      _session = bundle.session;
    });

    // Start loading model in background while user selects materials
    _initModelBackground();
  }

  Future<void> _initModelBackground() async {
    setState(() => _isLoadingModel = true);
    try {
      await _ensureModel();
    } catch (_) {
      // Generation will fall back to rule-based if model fails
    } finally {
      if (mounted) setState(() => _isLoadingModel = false);
    }
  }

  Future<GemmaInferenceService> _ensureModel() {
    return _gemmaHost.ensureInitialized();
  }

  String _extractQuestionTextFromJson(String jsonBuffer) {
    try {
      final parsed = jsonDecode(jsonBuffer) as Map<String, dynamic>;
      return parsed['args']?['questionText'] as String? ?? '';
    } catch (_) {}

    final completeMatch =
        RegExp(r'"questionText"\s*:\s*"([^"\\]*(?:\\.[^"\\]*)*)"')
            .firstMatch(jsonBuffer);
    if (completeMatch != null) return completeMatch.group(1) ?? '';

    final partialMatch =
        RegExp(r'"questionText"\s*:\s*"(.*)').firstMatch(jsonBuffer);
    if (partialMatch != null) return partialMatch.group(1) ?? '';

    return '';
  }

  Future<void> _onGenerateTapped() async {
    final session = _session;
    if (session == null) return;

    final selected =
        _allMaterials.where((m) => _selectedIds.contains(m.id)).toList();
    if (selected.isEmpty) return;

    // Create quiz row before detection so we have an ID ready
    if (_quizId == null) {
      final quizId = await QuizDAO().insert(Quiz(
        sessionId: session.id!,
        questionCount: 10, // placeholder; updated after detection
        createdAt: DateTime.now(),
      ));
      if (!mounted) return;
      setState(() => _quizId = quizId);
    }

    // Detection phase
    setState(() => _step = _ModalStep.detecting);

    List<String> detected = [];
    try {
      final service = await _ensureModel();
      _quizService = GemmaQuizService(service);
      detected =
          await _quizService!.detectQuestionsInMaterials(materials: selected);
    } catch (_) {
      detected = [];
    }

    if (!mounted) return;

    setState(() => _step = _ModalStep.generating);

    if (detected.isNotEmpty) {
      await _runExtractionPath(detected, session);
    } else {
      await _startAiGeneration(selected, session);
    }
  }

  Future<void> _runExtractionPath(
      List<String> detectedTexts, Session session) async {
    final qid = _quizId;
    if (qid == null || !mounted) return;

    // Update quiz with actual question count
    await QuizDAO().updateQuestionCount(qid, detectedTexts.length);

    setState(() {
      _totalCount = detectedTexts.length;
      _generatedCount = 0;
    });

    final questions = <Question>[];
    for (var i = 0; i < detectedTexts.length; i++) {
      final q = Question(
        quizId: -1,
        source: QuestionSource.extracted,
        type: QuestionType.textAnswer,
        questionText: detectedTexts[i],
        options: const [],
        orderIndex: i,
      );
      questions.add(q);

      if (mounted) {
        setState(() {
          _generatedCount = i + 1;
          _generatedQuestions.add('Q${i + 1}: ${detectedTexts[i]}');
        });
        _scrollToBottom();
      }
      await Future.delayed(const Duration(milliseconds: 80));
    }

    await _saveAndNavigate(questions);
  }

  Future<void> _startAiGeneration(
      List<StudyMaterial> selected, Session session) async {
    const questionCount = 10;
    final qid = _quizId;
    if (qid == null) return;

    // Update quiz with actual question count
    await QuizDAO().updateQuestionCount(qid, questionCount);

    try {
      final service = await _ensureModel();
      _quizService ??= GemmaQuizService(service);

      final stream = _quizService!.runQuizAgent(
        session: session,
        materials: selected,
        maxQuestions: questionCount,
      );

      _subscription = stream.listen(
        _handleEvent,
        onError: (Object e) => _showErrorAndPop(e.toString()),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingModel = false);
      _showErrorAndPop(e.toString());
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
      case QuizPlanAnnounced(:final steps):
        setState(() => _planSteps = steps);
        _scrollToBottom();
      case QuizStepCompleted(:final index):
        setState(() => _completedSteps.add(index));
        _scrollToBottom();
      case QuizPlanned(:final questionCount, :final topics):
        setState(() {
          _totalCount = questionCount;
          _generatedQuestions.add('Plan: ${topics.join(", ")}');
        });
        _scrollToBottom();
      case QuizUnderReview(:final issues):
        if (issues.isNotEmpty) {
          _generatedQuestions.add('Review: ${issues.length} issue(s) found');
        }
        _scrollToBottom();
      case QuizRegenerating(:final index):
        _generatedQuestions.add('Regenerating Q${index + 1}...');
        _scrollToBottom();
      case QuizSubmitted(:final summary):
        debugPrint('Quiz submitted: $summary');
      case QuizThinkingToken(:final token):
        setState(() {
          _isThinking = true;
          _thinkingBuffer.write(token);
        });
        _scrollToBottom();
      case QuizTextToken(:final token):
        setState(() {
          _currentQuestionBuffer.write(token);
          _extractedQuestionText =
              _extractQuestionTextFromJson(_currentQuestionBuffer.toString());
        });
        _scrollToBottom();
      case QuizGenerationStarted(:final total):
        setState(() => _totalCount = total);
      case QuizQuestionGenerated(:final question, :final index, :final total):
        setState(() {
          _isThinking = false;
          _generatedCount = index;
          _totalCount = total;
          final finalText = _extractedQuestionText.isEmpty
              ? question.questionText
              : _extractedQuestionText;
          _generatedQuestions.add('Q$index: $finalText');
          _currentQuestionBuffer.clear();
          _extractedQuestionText = '';
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

    setState(() {
      _isComplete = true;
      _step = _ModalStep.complete;
    });
    ref.invalidate(sessionBundleProvider(widget.sessionId));

    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    Navigator.of(context).pop();
    if (!mounted) return;
    context.push('/session/${widget.sessionId}/quiz/$qid/detail');
  }

  void _cancel() {
    _subscription?.cancel();
    _subscription = null;
    if (mounted) Navigator.of(context).pop();
  }

  String _statusText() {
    if (_step == _ModalStep.materialSelection) return 'Pick your materials';
    if (_step == _ModalStep.detecting) return 'Scanning materials…';
    if (_isLoadingModel) return 'Loading brain...';
    if (_isComplete) return 'Quiz is ready! 🎉';
    if (_totalCount > 0) return 'Question $_generatedCount of $_totalCount';
    if (_isThinking) return 'Quex is thinking...';
    return 'Getting ready...';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: switch (_step) {
          _ModalStep.materialSelection => _buildMaterialSelection(scheme),
          _ => _buildGeneratingView(scheme),
        },
      ),
    );
  }

  Widget _buildMaterialSelection(ColorScheme scheme) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Close button
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _cancel,
          ),
        ),

        // Material list
        Expanded(
          child: ListView.builder(
            itemCount: _allMaterials.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding:
                      const EdgeInsets.fromLTRB(Sp.md, Sp.md, Sp.md, Sp.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Which materials to quiz on?',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Quex will scan these for existing questions.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                );
              }
              final m = _allMaterials[index - 1];
              final selected = _selectedIds.contains(m.id);
              final emoji = switch (m.kind) {
                MaterialKind.text => '📝',
                MaterialKind.document => '📄',
                MaterialKind.photo => '🖼️',
              };
              final kindLabel = switch (m.kind) {
                MaterialKind.text => 'Text',
                MaterialKind.document => 'Document',
                MaterialKind.photo => 'Photo',
              };

              return CheckboxListTile(
                controlAffinity: ListTileControlAffinity.leading,
                value: selected,
                onChanged: (val) {
                  setState(() {
                    if (val == true) {
                      _selectedIds.add(m.id!);
                    } else {
                      _selectedIds.remove(m.id);
                    }
                  });
                },
                title: Text(
                  m.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '$emoji $kindLabel',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              );
            },
          ),
        ),

        // Generate button
        Padding(
          padding: const EdgeInsets.all(Sp.md),
          child: FilledButton(
            onPressed: _selectedIds.isEmpty ? null : _onGenerateTapped,
            child: _isLoadingModel
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.onPrimary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text('Loading model…'),
                    ],
                  )
                : Text(
                    _selectedIds.isEmpty
                        ? 'Select materials first'
                        : 'Generate quiz  (${_selectedIds.length})',
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildGeneratingView(ColorScheme scheme) {
    final theme = Theme.of(context);
    final hasStream = _planSteps.isNotEmpty ||
        _thinkingBuffer.isNotEmpty ||
        _generatedQuestions.isNotEmpty ||
        (_totalCount > 0 && _generatedCount < _totalCount && !_isComplete);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _cancel,
          ),
        ),
        const Spacer(flex: 1),
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
                  : _step == _ModalStep.detecting
                      ? const _PulsingIcon(
                          key: ValueKey('scan'),
                          emoji: '🔍',
                        )
                      : _totalCount > 0
                          ? const _PulsingIcon(
                              key: ValueKey('pencil'),
                              emoji: '✏️',
                            )
                          : const _PulsingBrain(
                              key: ValueKey('brain'),
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
                    if (_planSteps.isNotEmpty) ...[
                      ..._planSteps.asMap().entries.map((e) {
                        final done = _completedSteps.contains(e.key);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                done
                                    ? Icons.check_circle_rounded
                                    : Icons.radio_button_unchecked,
                                size: 16,
                                color: done
                                    ? scheme.primary
                                    : scheme.outlineVariant,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  e.value,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: done
                                        ? scheme.onSurface
                                        : scheme.onSurfaceVariant,
                                    decoration: done
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      if (_generatedQuestions.isNotEmpty ||
                          _thinkingBuffer.isNotEmpty)
                        const Divider(height: 16),
                    ],
                    if (_thinkingBuffer.isNotEmpty)
                      Text(
                        _thinkingBuffer.toString(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    if (_thinkingBuffer.isNotEmpty &&
                        (_generatedQuestions.isNotEmpty ||
                            _extractedQuestionText.isNotEmpty))
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
                    if (_totalCount > 0 &&
                        _generatedCount < _totalCount &&
                        !_isComplete)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Text(
                                'Writing Q${_generatedCount + 1} of $_totalCount',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: scheme.primary,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                            const _AnimatedEllipsis(),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
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
    );
  }
}

class _PulsingIcon extends StatefulWidget {
  final String emoji;

  const _PulsingIcon({super.key, required this.emoji});

  @override
  State<_PulsingIcon> createState() => _PulsingIconState();
}

class _PulsingIconState extends State<_PulsingIcon>
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
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Text(widget.emoji, style: const TextStyle(fontSize: 64)),
    );
  }
}

class _PulsingBrain extends _PulsingIcon {
  const _PulsingBrain({super.key}) : super(emoji: '🧠');
}

class _AnimatedEllipsis extends StatefulWidget {
  const _AnimatedEllipsis();

  @override
  State<_AnimatedEllipsis> createState() => _AnimatedEllipsisState();
}

class _AnimatedEllipsisState extends State<_AnimatedEllipsis>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )
      ..repeat()
      ..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dots = '.' * ((_controller.value * 3).floor() + 1);
    return Text(
      dots,
      style: TextStyle(
        color: Theme.of(context).colorScheme.primary,
        fontStyle: FontStyle.italic,
      ),
    );
  }
}
