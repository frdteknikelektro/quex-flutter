import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/ai/gemma_inference_service.dart';
import '../../core/ai/gemma_service_host.dart';
import '../../core/ai/gemma_quiz_service.dart';
import '../../core/ai/material_preprocessor.dart';
import '../../core/ai/quiz_generation_event.dart';
import '../../core/db/daos.dart';
import '../../core/models/models.dart';
import '../../core/state/app_state.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../widgets/math_markdown.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

enum _ModalStep { materialSelection, extracting, extractionReview, generating, complete }

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
  final _streamBuffer = StringBuffer();
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
  bool _isGenerating = false;
  bool _isExtracting = false;
  StreamSubscription<QuizGenerationEvent>? _subscription;
  int? _quizId;
  GemmaQuizService? _quizService;
  Session? _session;
  String? _extractedQuestions;
  List<StudyMaterial> _selectedMaterials = [];

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
      final l10n = AppLocalizations.of(context)!;
      _showErrorAndPop(l10n.quizGenAddMaterialsFirst);
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
      final service = await _ensureModel();
      _quizService ??= GemmaQuizService(service);

      final stream = _quizService!.runQuizAgent(
        session: session,
        materials: selected,
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

    // Add visual separation before Session 2
    setState(() {
      _streamBuffer.write('\n\n');
    });

    setState(() => _step = _ModalStep.generating);

    try {
      await _ensureModel();

      // Prepare materials for Session 2
      final prepared = await MaterialPreprocessor.prepare(_selectedMaterials);
      final hasImages = prepared.any((p) => p.images.isNotEmpty);
      final textContext = prepared
          .map((p) => p.textChunk)
          .where((t) => t.isNotEmpty)
          .join('\n\n');

      final allImages = <Uint8List>[];
      for (final prep in prepared) {
        allImages.addAll(prep.images);
      }

      final stream = _quizService!.runGenerationSession(
        session: session,
        textContext: textContext,
        images: allImages,
        hasImages: hasImages,
        extractedQuestions: _extractedQuestions,
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
        setState(() => _isExtracting = true);
        _scrollToBottom();
      case QuizExtractionComplete(:final extractedQuestions):
        setState(() {
          _extractedQuestions = extractedQuestions;
          _isExtracting = false;
          _step = _ModalStep.extractionReview;
        });
        _scrollToBottom();
      case QuizExtractionEmpty():
        setState(() {
          _extractedQuestions = null;
          _isExtracting = false;
          _step = _ModalStep.extractionReview;
        });
        _scrollToBottom();
      case QuizThinkingToken(:final token):
        setState(() {
          _isThinking = true;
          _thinkingBuffer.write(token);
        });
        _scrollToBottom();
      case QuizTextToken(:final token):
        setState(() {
          _isGenerating = true;
          _streamBuffer.write(token);
        });
        _scrollToBottom();
      case QuizGenerationStarted():
        setState(() => _isGenerating = true);
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
                    l10n.quizGenFoundDescription,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: Br.md,
                      ),
                      padding: const EdgeInsets.all(12),
                      child: SingleChildScrollView(
                        child: MathMarkdownBody(
                          data: _extractedQuestions!,
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
                  ),
                ] else ...[
                  Text(
                    l10n.quizGenNoQuestionsDescription,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        // Continue button
        Padding(
          padding: const EdgeInsets.all(Sp.md),
          child: FilledButton(
            onPressed: _continueToGeneration,
            child: Text(l10n.quizGenContinue),
          ),
        ),
      ],
    );
  }

  Widget _buildGeneratingView(ColorScheme scheme) {
    final theme = Theme.of(context);
    final hasStream = _planSteps.isNotEmpty ||
        _thinkingBuffer.isNotEmpty ||
        _streamBuffer.isNotEmpty ||
        _isGenerating;

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
                  : _isGenerating
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
                      if (_streamBuffer.isNotEmpty ||
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
                    if (_thinkingBuffer.isNotEmpty && _streamBuffer.isNotEmpty)
                      const Divider(height: 16),
                    if (_streamBuffer.isNotEmpty)
                      MathMarkdownBody(
                        data: _streamBuffer.toString(),
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
