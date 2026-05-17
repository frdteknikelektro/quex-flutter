import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/ai/quiz_generation_service.dart';
import '../../core/ai/quiz_generation_event.dart';
import '../../core/db/daos.dart';
import '../../core/models/models.dart';
import '../../core/state/app_state.dart';
import 'emoji_memory_game.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../widgets/math_markdown.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

enum _ModalStep {
  materialSelection,
  extracting,
  reviewing,
  extractionReview,
  generating,
  complete
}

@visibleForTesting
String sanitizeQuizTranscript(String content) {
  var sanitized = content;
  sanitized = sanitized.replaceAll(
    RegExp(
      r'\[CORRECT\]\s*[\s\S]*?(?=\n\[[A-Z_]+\]|\s*$)',
      caseSensitive: false,
    ),
    '',
  );
  sanitized = sanitized.replaceAll(
    RegExp(
      r'\[EXPECTED_ANSWER\]\s*[\s\S]*?(?=\n\[[A-Z_]+\]|\s*$)',
      caseSensitive: false,
    ),
    '',
  );
  sanitized = sanitized.replaceAll(
    RegExp(
      r'^\s*(answer|correct answer|expected answer|jawaban|kunci jawaban)\s*[:：].*$',
      caseSensitive: false,
      multiLine: true,
    ),
    '',
  );
  sanitized = sanitized.replaceAll(
    RegExp(r'^\s*\[END\]\s*$', multiLine: true),
    '',
  );
  sanitized = sanitized.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return sanitized.trim();
}

class QuizGenerationModal extends ConsumerStatefulWidget {
  final int sessionId;
  final QuizGenerationService? quizService;

  const QuizGenerationModal({
    super.key,
    required this.sessionId,
    this.quizService,
  });

  @override
  ConsumerState<QuizGenerationModal> createState() =>
      _QuizGenerationModalState();
}

class _QuizGenerationModalState extends ConsumerState<QuizGenerationModal> {
  final _thinkingBuffer = StringBuffer();
  final _extractionBuffer = StringBuffer();
  final Map<QuizGenerationPhase, StringBuffer> _phaseBuffers = {};
  final Set<QuizGenerationPhase> _completedPhases = {};
  final List<QuizGenerationPhase> _phaseOrder = [];
  List<String> _planSteps = [];
  final Set<int> _completedSteps = {};
  final _scrollController = ScrollController();

  _ModalStep _step = _ModalStep.materialSelection;
  List<StudyMaterial> _allMaterials = [];
  Set<int> _selectedIds = {};

  bool _isThinking = false;
  bool _isComplete = false;
  bool _isLoadingModel = false;
  bool _isGenerating = false;
  bool _isExtracting = false;
  bool _isReviewing = false;
  StreamSubscription<QuizGenerationEvent>? _subscription;
  int? _quizId;
  late final QuizGenerationService _quizService;
  Session? _session;
  String? _extractedQuestions;
  String? _reviewText;
  List<StudyMaterial> _selectedMaterials = [];

  @override
  void initState() {
    super.initState();
    _quizService = widget.quizService ?? QuizGenerationService();
    _loadMaterials();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMaterials() async {
    final bundle =
        await ref.read(sessionBundleProvider(widget.sessionId).future);
    if (!mounted || bundle == null) return;
    if (bundle.materials.isEmpty) {
      final l10n = AppLocalizations.of(context)!;
      _showErrorAndPop(l10n.quizGenAddMaterialsFirst);
      return;
    }
    setState(() {
      _allMaterials = bundle.materials;
      _selectedIds = {};
      _session = bundle.session;
    });
  }

  Future<void> _onGenerateTapped() async {
    final session = _session;
    if (session == null) return;

    final selected =
        _allMaterials.where((m) => _selectedIds.contains(m.id)).toList();
    if (selected.isEmpty) return;

    // Store selected materials for Session 2
    _selectedMaterials = selected;

    // Create quiz row before generation so we have an ID ready
    if (_quizId == null) {
      final quizId = await QuizDAO().insert(Quiz(
        sessionId: session.id!,
        questionCount: 10, // placeholder; updated after planning
        createdAt: DateTime.now(),
      ));
      if (!mounted) return;
      setState(() => _quizId = quizId);
    }

    // Start with Session 1: extraction
    setState(() => _step = _ModalStep.extracting);
    await _startExtraction(selected, session);
  }

  Future<void> _startExtraction(
      List<StudyMaterial> selected, Session session) async {
    try {
      await _quizService.initialize();

      final stream = _quizService.runExtractionSession(
        session: session,
        materials: selected,
        locale: mounted ? Localizations.localeOf(context).languageCode : 'en',
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

  Future<void> _startReview() async {
    final session = _session;
    if (session == null) return;

    try {
      await _quizService.initialize();
      if (!mounted) return;

      final stream = _quizService.runReviewSession(
        session: session,
        materials: _selectedMaterials,
        extractedQuestions: _extractedQuestions ?? '',
        locale: mounted ? Localizations.localeOf(context).languageCode : 'en',
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

  Future<void> _continueToGeneration() async {
    final session = _session;
    if (session == null) return;

    final qid = _quizId;
    if (qid == null) return;
    final reviewText = _reviewText?.trim();
    if (reviewText == null || reviewText.isEmpty) {
      _showErrorAndPop('AI review is empty.');
      return;
    }

    // Add visual separation before Session 3.
    setState(() {
      _step = _ModalStep.generating;
      _completedSteps.add(1);
    });

    try {
      await _quizService.initialize();
      if (!mounted) return;

      final stream = _quizService.runGenerationSession(
        session: session,
        materials: _selectedMaterials,
        reviewText: reviewText,
        targetCount: 10,
        locale: mounted ? Localizations.localeOf(context).languageCode : 'en',
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
    final l10n = AppLocalizations.of(context)!;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.quizGenFailed(message))),
    );
  }

  StringBuffer _bufferForPhase(QuizGenerationPhase phase) {
    return _phaseBuffers.putIfAbsent(phase, StringBuffer.new);
  }

  String _phaseTitle(QuizGenerationPhase phase) {
    final locale = Localizations.localeOf(context).languageCode;
    return switch (phase) {
      QuizGenerationPhase.review =>
        locale == 'id' ? 'Tinjauan AI' : 'AI Review',
      QuizGenerationPhase.generation =>
        locale == 'id' ? 'Penyusunan' : 'Generation',
    };
  }

  String _phaseEmptyText() {
    final locale = Localizations.localeOf(context).languageCode;
    return locale == 'id'
        ? 'Belum ada draf yang keluar.'
        : 'No draft output yet.';
  }

  String _startingPhaseText() {
    final locale = Localizations.localeOf(context).languageCode;
    if (_isReviewing) {
      return locale == 'id'
          ? 'Memulai tinjauan AI...'
          : 'Starting AI review...';
    }
    if (_isGenerating) {
      return locale == 'id'
          ? 'Memulai penyusunan...'
          : 'Starting generation...';
    }
    return '';
  }

  void _resetGenerationBuffers() {
    _thinkingBuffer.clear();
    _phaseBuffers.clear();
    _completedPhases.clear();
    _phaseOrder.clear();
  }

  void _appendPhaseText(QuizGenerationPhase phase, String token) {
    if (!_phaseBuffers.containsKey(phase)) {
      _phaseOrder.add(phase);
    }
    _bufferForPhase(phase).write(token);
  }

  List<QuizGenerationPhase> _visibleGenerationPhases() {
    final ordered =
        _phaseOrder.isEmpty ? QuizGenerationPhase.values : _phaseOrder;
    return ordered
        .where((phase) =>
            _phaseBuffers.containsKey(phase) ||
            _completedPhases.contains(phase))
        .toList(growable: false);
  }

  bool _shouldShowMemoryGame() {
    return _isThinking ||
        _isExtracting ||
        _isReviewing ||
        _isGenerating ||
        _thinkingBuffer.isNotEmpty ||
        _extractionBuffer.isNotEmpty ||
        _planSteps.isNotEmpty ||
        _visibleGenerationPhases().isNotEmpty;
  }

  Widget _buildPhaseTranscript(
    QuizGenerationPhase phase,
    ColorScheme scheme,
    TextTheme textTheme,
  ) {
    final buffer = _phaseBuffers[phase];
    final content = sanitizeQuizTranscript(buffer?.toString() ?? '');
    final isComplete = _completedPhases.contains(phase);
    final hasContent = content.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isComplete ? Icons.check_circle_rounded : Icons.timelapse,
                size: 16,
                color: isComplete ? scheme.primary : scheme.outlineVariant,
              ),
              const SizedBox(width: 8),
              Text(
                _phaseTitle(phase),
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (hasContent)
            SelectableText(
              content,
              style: textTheme.bodyMedium?.copyWith(
                color: scheme.onSurface,
                fontFamily: 'monospace',
                height: 1.35,
              ),
            )
          else
            Text(
              _phaseEmptyText(),
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
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
      case QuizPlanned():
        // No longer used
        break;
      case QuizSubmitted():
        // No longer used
        break;
      case QuizQuestionGenerated():
        // No longer used
        break;
      case QuizExtractionStarted():
        setState(() {
          _isExtracting = true;
          _isReviewing = false;
          _isGenerating = false;
          _reviewText = null;
          _extractionBuffer.clear();
          _resetGenerationBuffers();
        });
        _scrollToBottom();
      case QuizExtractionComplete(:final extractedQuestions):
        setState(() {
          _extractedQuestions = extractedQuestions;
          _isExtracting = false;
          _isReviewing = true;
          _step = _ModalStep.reviewing;
        });
        _scrollToBottom();
        unawaited(_startReview());
      case QuizExtractionEmpty():
        setState(() {
          _extractedQuestions = null;
          _isExtracting = false;
          _isReviewing = true;
          _step = _ModalStep.reviewing;
        });
        _scrollToBottom();
        unawaited(_startReview());
      case QuizThinkingToken(:final token):
        setState(() {
          _isThinking = true;
          _thinkingBuffer.write(token);
        });
        _scrollToBottom();
      case QuizTextToken(:final token):
        setState(() {
          if (_step == _ModalStep.extracting) {
            _extractionBuffer.write(token);
          }
        });
        _scrollToBottom();
      case QuizGenerationStarted():
        setState(() {
          _isGenerating = true;
          _isReviewing = false;
          _isThinking = false;
          _resetGenerationBuffers();
        });
        _scrollToBottom();
      case QuizPhaseStarted(:final phase):
        setState(() {
          _isGenerating = phase == QuizGenerationPhase.generation;
          _isReviewing = phase == QuizGenerationPhase.review;
          _isThinking = false;
          if (!_phaseBuffers.containsKey(phase)) _phaseOrder.add(phase);
          _bufferForPhase(phase);
        });
        _scrollToBottom();
      case QuizPhaseTextToken(:final phase, :final token):
        setState(() {
          _isGenerating = phase == QuizGenerationPhase.generation;
          _isReviewing = phase == QuizGenerationPhase.review;
          _appendPhaseText(phase, token);
        });
        _scrollToBottom();
      case QuizPhaseCompleted(:final phase):
        setState(() => _completedPhases.add(phase));
        _scrollToBottom();
      case QuizReviewComplete(:final reviewText):
        setState(() {
          _reviewText = reviewText.trim();
          _isReviewing = false;
          _step = _ModalStep.extractionReview;
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

    // Update quiz with actual question count
    await QuizDAO().updateQuestionCount(qid, questions.length);

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
    final l10n = AppLocalizations.of(context)!;
    if (_step == _ModalStep.materialSelection) return l10n.quizGenPickMaterials;
    if (_isLoadingModel) return l10n.quizGenLoadingBrain;
    if (_isComplete) return l10n.quizGenReady;
    if (_isExtracting) return l10n.quizGenExtracting;
    if (_isReviewing) {
      return Localizations.localeOf(context).languageCode == 'id'
          ? 'Meninjau pertanyaan dan materi'
          : 'Reviewing questions and materials';
    }
    if (_isGenerating) return l10n.quizGenGenerating;
    if (_isThinking) return l10n.quizGenThinking;
    if (_step == _ModalStep.extractionReview) {
      return _extractedQuestions != null
          ? l10n.quizGenFoundQuestions
          : l10n.quizGenNoQuestions;
    }
    return l10n.quizGenGettingReady;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: switch (_step) {
          _ModalStep.materialSelection => _buildMaterialSelection(scheme),
          _ModalStep.extractionReview => _buildExtractionReview(scheme),
          _ => _buildGeneratingView(scheme),
        },
      ),
    );
  }

  Widget _buildMaterialSelection(ColorScheme scheme) {
    final l10n = AppLocalizations.of(context)!;
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
                        l10n.quizGenWhichMaterials,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.quizGenScanMaterials,
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
                      Text(l10n.quizGenLoadingModel),
                    ],
                  )
                : Text(
                    _selectedIds.isEmpty
                        ? l10n.quizGenSelectFirst
                        : l10n.quizGenGenerate(_selectedIds.length),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildExtractionReview(ColorScheme scheme) {
    final l10n = AppLocalizations.of(context)!;
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

        // Content
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(Sp.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _extractedQuestions != null
                      ? l10n.quizGenFoundTitle
                      : l10n.quizGenNoQuestionsTitle,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 16),
                if (_extractedQuestions != null) ...[
                  Text(
                    Localizations.localeOf(context).languageCode == 'id'
                        ? 'Pertanyaan hasil ekstraksi'
                        : 'Extracted questions',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.quizGenFoundDescription,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 150,
                    child: _ReviewPanel(
                      child: MathMarkdownBody(
                        data: sanitizeQuizTranscript(_extractedQuestions!),
                        styleSheet: MarkdownStyleSheet(
                          listBullet: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurface,
                          ),
                          listIndent: 32,
                        ),
                        textStyle: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  Text(
                    l10n.quizGenNoQuestionsDescription,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  Localizations.localeOf(context).languageCode == 'id'
                      ? 'Tinjauan AI & rencana'
                      : 'AI review & plan',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _ReviewPanel(
                    child: MathMarkdownBody(
                      data: sanitizeQuizTranscript(_reviewText ?? ''),
                      styleSheet: MarkdownStyleSheet(
                        listBullet: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurface,
                        ),
                        listIndent: 32,
                      ),
                      textStyle: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Continue button
        Padding(
          padding: const EdgeInsets.all(Sp.md),
          child: FilledButton(
            onPressed: (_reviewText?.trim().isEmpty ?? true)
                ? null
                : _continueToGeneration,
            child: Text(l10n.quizGenContinue),
          ),
        ),
      ],
    );
  }

  Widget _buildGeneratingView(ColorScheme scheme) {
    final theme = Theme.of(context);
    final visiblePhases = _visibleGenerationPhases();
    final hasStream = _planSteps.isNotEmpty ||
        _thinkingBuffer.isNotEmpty ||
        _isGenerating ||
        (_step == _ModalStep.extracting && _extractionBuffer.isNotEmpty) ||
        (_step == _ModalStep.reviewing && visiblePhases.isNotEmpty) ||
        visiblePhases.isNotEmpty;

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
                  : _shouldShowMemoryGame()
                      ? _buildMemoryGameHero(scheme, theme.textTheme)
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
        const SizedBox(height: 16),
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
                      if (_thinkingBuffer.isNotEmpty ||
                          (_step == _ModalStep.extracting &&
                              _extractionBuffer.isNotEmpty) ||
                          visiblePhases.isNotEmpty)
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
                        (_step == _ModalStep.extracting &&
                            _extractionBuffer.isNotEmpty))
                      const Divider(height: 16),
                    if (_step == _ModalStep.extracting &&
                        _extractionBuffer.isNotEmpty)
                      MathMarkdownBody(
                        data: _extractionBuffer.toString(),
                        styleSheet: MarkdownStyleSheet(
                          listBullet: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurface,
                          ),
                          listIndent: 32,
                        ),
                        textStyle: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurface,
                        ),
                      ),
                    if (_step == _ModalStep.reviewing ||
                        _step == _ModalStep.generating) ...[
                      if (visiblePhases.isEmpty)
                        Text(
                          _startingPhaseText(),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ...visiblePhases.map(
                        (phase) => _buildPhaseTranscript(
                            phase, scheme, theme.textTheme),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Spacer(flex: 1),
      ],
    );
  }

  Widget _buildMemoryGameHero(ColorScheme scheme, TextTheme textTheme) {
    return Column(
      key: const ValueKey('memory-hero'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'You can play while waiting...',
          textAlign: TextAlign.center,
          style: textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          key: const ValueKey('memory-game-frame'),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: Br.md,
            border: Border.all(
              color: scheme.outlineVariant,
              width: 1,
            ),
          ),
          child: const EmojiMemoryGame(
            maxWidth: 180,
            key: ValueKey('memory-game'),
          ),
        ),
      ],
    );
  }
}

class _ReviewPanel extends StatelessWidget {
  final Widget child;

  const _ReviewPanel({required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: Br.md,
        ),
        padding: const EdgeInsets.all(12),
        child: SingleChildScrollView(child: child),
      ),
    );
  }
}

class _PulsingBrain extends StatefulWidget {
  const _PulsingBrain({super.key});

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
