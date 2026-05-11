import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as pathlib;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../app/theme.dart';
import '../../core/ai/question_chat_service.dart';
import '../../core/ai/tts_service.dart';
import '../../core/ai/tutor_event.dart';
import '../../core/db/daos.dart';
import '../../core/models/models.dart';
import '../../core/state/app_state.dart';
import '../../core/utils/image_normalizer.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../widgets/math_markdown.dart';
import '../chat/chat_screen.dart';

const String _kVoiceSentinel = '__voice__';

class QuestionChatScreen extends ConsumerStatefulWidget {
  final int sessionId;
  final int quizId;
  final int questionId;

  const QuestionChatScreen({
    super.key,
    required this.sessionId,
    required this.quizId,
    required this.questionId,
  });

  @override
  ConsumerState<QuestionChatScreen> createState() => _QuestionChatScreenState();
}

class _QuestionChatScreenState extends ConsumerState<QuestionChatScreen> {
  // ===========================================================================
  // Controllers
  // ===========================================================================
  final _textController = TextEditingController();
  final _scrollController = ScrollController();

  // ===========================================================================
  // Services
  // ===========================================================================
  final QuestionChatService _chatService = QuestionChatService();
  final TtsService _ttsService = TtsService();
  StreamSubscription<TutorEvent>? _streamSub;

  // ===========================================================================
  // Chat State
  // ===========================================================================
  final List<QuestionMessage> _messages = [];
  bool _openerFired = false;

  // ===========================================================================
  // AI / Streaming State
  // ===========================================================================
  bool _sending = true;
  bool _modelLoading = false;
  String? _streamingContent;
  String? _thinkingContent;
  bool _thinkingExpanded = false;

  // ===========================================================================
  // Session State
  // ===========================================================================
  bool _isThinkingMode = false;
  bool _thinkingSpeechFired = false;
  int _sendEra = 0;

  // ===========================================================================
  // Audio Recording State
  // ===========================================================================
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  DateTime? _recordingStartTime;

  // ===========================================================================
  // Image Attachment State
  // ===========================================================================
  final List<File> _attachedImages = [];
  static const int _maxAttachedImages = 4;
  final Map<int, List<File>> _messageImages = {};

  // ===========================================================================
  // UI / Scroll State
  // ===========================================================================
  int _tokenCount = 0;
  int _totalTokens = 0;
  int _maxTokens = 8192;
  static const int _scrollThrottleTokens = 10;
  bool _isScrolling = false;

  // ===========================================================================
  // Score State
  // ===========================================================================
  double? _currentScore;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    unawaited(_ttsService.initialize());

    if (_chatService.isInitialized) {
      final effectiveMaxTokens = _chatService.effectiveMaxTokens ?? 8192;
      if (mounted) setState(() => _maxTokens = effectiveMaxTokens);
      return;
    }
    try {
      if (mounted) setState(() => _modelLoading = true);
      await _chatService.initialize();
      final effectiveMaxTokens = _chatService.effectiveMaxTokens ?? 8192;
      if (mounted) setState(() => _maxTokens = effectiveMaxTokens);
    } catch (e) {
      debugPrint('Failed to initialize chat service: $e');
    } finally {
      if (mounted) setState(() => _modelLoading = false);
    }
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    _cleanupOnDispose();
    super.dispose();
  }

  void _cleanupOnDispose() async {
    try {
      await _ttsService.dispose();
    } catch (e) {
      debugPrint('Error disposing tts service: $e');
    }
    try {
      await _chatService.dispose();
    } catch (e) {
      debugPrint('Error disposing chat service: $e');
    }
    try {
      await _recorder.dispose();
    } catch (e) {
      debugPrint('Error disposing recorder: $e');
    }
    if (_isRecording) {
      try {
        await _recorder.stop();
      } catch (e) {
        debugPrint('Error stopping recording on dispose: $e');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Session Management
  // ---------------------------------------------------------------------------

  Future<void> _fireOpener(
    Question question,
    List<StudyMaterial> materials,
  ) async {
    if (_openerFired) return;

    final l10n = AppLocalizations.of(context);
    final locale = l10n?.localeName ?? 'en';
    unawaited(_ttsService.setLocale(locale));

    try {
      await _chatService.createSession(
        question: question,
        materials: materials,
        locale: locale,
        isThinking: _isThinkingMode,
      );
    } catch (e) {
      debugPrint('Failed to create tutor session: $e');
      if (mounted) {
        setState(() {
          _openerFired = false;
          _sending = false;
        });
      }
      return;
    }

    _openerFired = true;

    if (!mounted) return;
    setState(() {
      _sending = true;
      _sendEra++;
      _streamingContent = '';
      _thinkingContent = null;
    });

    try {
      final imageBytes = <Uint8List>[];
      for (final image in _attachedImages) {
        try {
          final bytes = await image.readAsBytes();
          imageBytes.add(bytes);
        } catch (e) {
          debugPrint('Failed to read opener image bytes: $e');
        }
      }

      final stream = _chatService.sendOpener(locale, images: imageBytes);
      final result = await _handleTutorStream(stream);
      _thinkingSpeechFired = false;
      unawaited(_ttsService.speak(result.reply));

      _clearImages();

      if (mounted) {
        setState(() {
          if (result.reply.isNotEmpty) {
            _messages.add(QuestionMessage(
              questionId: widget.questionId,
              role: QuestionMessageRole.assistant,
              content: result.reply,
              createdAt: DateTime.now(),
            ));
          }
          _streamingContent = null;
          _sending = false;
          _thinkingContent = result.thinking.isEmpty ? null : result.thinking;
          _thinkingExpanded = false;
        });
      }
      _scrollToBottom();
    } catch (e) {
      debugPrint('Opener error: $e');
      _tokenCount = 0;
      if (mounted) {
        setState(() {
          _streamingContent = null;
          _thinkingContent = null;
          _sending = false;
        });
      }
    }
  }

  Future<void> _resetChat(
    Question question,
    List<StudyMaterial> materials,
  ) async {
    await _ttsService.stop();
    await _streamSub?.cancel();
    _streamSub = null;
    _clearImages();
    _messageImages.clear();
    await _chatService.resetSession();
    if (mounted) {
      setState(() {
        _messages.clear();
        _sending = false;
        _streamingContent = null;
        _thinkingContent = null;
        _thinkingSpeechFired = false;
        _openerFired = false;
      });
    }
  }

  Future<void> _toggleThinkingMode(
    Question question,
    List<StudyMaterial> materials,
  ) async {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return;

    final newValue = !_isThinkingMode;
    final title = newValue
        ? l10n.chatThinkingModeConfirm
        : l10n.chatThinkingModeDisableConfirm;
    final message = newValue
        ? l10n.chatThinkingModeConfirmMessage
        : l10n.chatThinkingModeDisableMessage;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final dialogL10n = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(dialogL10n?.cancel ?? 'Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(dialogL10n?.continueButton ?? 'Continue'),
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      setState(() {
        _isThinkingMode = newValue;
        _sending = true;
        _sendEra++;
      });
      await _resetChat(question, materials);
    }
  }

  // ---------------------------------------------------------------------------
  // Score Handling
  // ---------------------------------------------------------------------------

  Future<void> _handleScore(double score) async {
    if (!mounted) return;
    setState(() => _currentScore = score);
    await QuestionDAO().saveScore(widget.questionId, score);
    ref.invalidate(questionProvider(widget.questionId));
    ref.invalidate(quizBundleProvider(widget.quizId));
  }

  // ---------------------------------------------------------------------------
  // Streaming & UI Helpers
  // ---------------------------------------------------------------------------

  Future<void> _stopGeneration() async {
    await _ttsService.stop();
    await _streamSub?.cancel();
    _streamSub = null;
    _tokenCount = 0;
    _thinkingSpeechFired = false;
    await _chatService.stopGeneration();
    if (mounted) {
      setState(() {
        _sending = false;
        _streamingContent = null;
        _thinkingContent = null;
      });
    }
  }

  Future<({String reply, String thinking})> _handleTutorStream(
    Stream<TutorEvent> stream,
  ) async {
    final accumulatedReply = StringBuffer();
    final accumulatedThinking = StringBuffer();
    final completer = Completer<void>();
    _tokenCount = 0;
    final thinkingPhrase = AppLocalizations.of(context)?.chatTtsSayThinking
        ?? 'Let me think for a moment…';

    await _streamSub?.cancel();
    _streamSub = stream.listen(
      (event) {
        if (!mounted) return;
        if (event is TutorThinking) {
          accumulatedThinking.write(event.token);
          if (!_thinkingSpeechFired) {
            _thinkingSpeechFired = true;
            unawaited(_ttsService.speak(thinkingPhrase));
          }
          if (mounted) {
            setState(() => _thinkingContent = accumulatedThinking.toString());
          }
        } else if (event is TutorReply) {
          accumulatedReply.write(event.token);
          if (mounted) {
            setState(() => _streamingContent = accumulatedReply.toString());
          }
          _tokenCount++;
          if (_tokenCount % _scrollThrottleTokens == 0) _scrollToBottom();
        } else if (event is TutorEvaluation) {
          unawaited(_handleScore(event.score));
        }
      },
      onDone: () {
        _scrollToBottom();
        if (mounted) _captureSessionMetrics();
        completer.complete();
      },
      onError: (e) {
        _streamSub = null;
        completer.completeError(e);
      },
      cancelOnError: true,
    );

    await completer.future;
    return (
      reply: accumulatedReply.toString(),
      thinking: accumulatedThinking.toString(),
    );
  }

  void _scrollToBottom() {
    if (!mounted || _isScrolling) return;
    _isScrolling = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        _scrollController
            .animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        )
            .then((_) {
          _isScrolling = false;
        });
      } else {
        _isScrolling = false;
      }
    });
  }

  void _captureSessionMetrics() {
    try {
      final metrics = _chatService.getSessionMetrics();
      if (metrics == null) {
        if (mounted) setState(() => _totalTokens = 0);
        return;
      }
      final dynamic m = metrics;
      final metricsTotal = m.totalTokens as int? ?? 0;
      if (mounted) setState(() => _totalTokens = metricsTotal);
    } catch (e) {
      debugPrint('Failed to capture session metrics: $e');
      if (mounted) setState(() => _totalTokens = 0);
    }
  }

  // ---------------------------------------------------------------------------
  // Image Attachment
  // ---------------------------------------------------------------------------

  Future<File?> _compressImage(File image) async {
    try {
      final dir = await getTemporaryDirectory();
      final normalized = await ImageNormalizer.normalizeFile(
        image,
        outputDirectory: dir,
        fileStem: pathlib.basenameWithoutExtension(image.path),
      );
      return normalized?.file;
    } catch (e) {
      debugPrint('Failed to normalize image: $e');
      return null;
    }
  }

  Future<void> _addImage() async {
    if (_attachedImages.length >= _maxAttachedImages) return;

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile == null) return;

    if (mounted) setState(() { _sending = true; _sendEra++; });

    try {
      final originalFile = File(pickedFile.path);
      final compressedFile = await _compressImage(originalFile);

      if (compressedFile == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not process image. Please try another one.'),
            ),
          );
          setState(() => _sending = false);
        }
        return;
      }

      if (mounted) {
        setState(() {
          _attachedImages.add(compressedFile);
          _sending = false;
        });
      }
    } catch (e) {
      debugPrint('Failed to add image: $e');
      if (mounted) setState(() => _sending = false);
    }
  }

  void _removeImage(int index) async {
    if (index >= 0 && index < _attachedImages.length) {
      final file = _attachedImages[index];
      try {
        await file.delete();
      } catch (e) {
        debugPrint('Failed to delete image file: $e');
      }
      setState(() => _attachedImages.removeAt(index));
    }
  }

  void _clearImages() async {
    for (final file in _attachedImages) {
      try {
        await file.delete();
      } catch (e) {
        debugPrint('Failed to delete image file: $e');
      }
    }
    _attachedImages.clear();
  }

  // ---------------------------------------------------------------------------
  // Audio Recording
  // ---------------------------------------------------------------------------

  Future<void> _startRecording() async {
    if (_sending || _isRecording) return;
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                l10n?.chatMicPermissionDenied ?? 'Microphone permission denied'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/quex_voice_${DateTime.now().millisecondsSinceEpoch}.wav';
    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );
      _recordingStartTime = DateTime.now();
      if (mounted) setState(() => _isRecording = true);
    } catch (e) {
      debugPrint('Failed to start recording: $e');
      if (mounted) setState(() => _isRecording = false);
    }
  }

  Future<void> _stopAndSendAudio(
    Question question,
    List<StudyMaterial> materials,
  ) async {
    final path = await _recorder.stop();
    if (mounted) setState(() => _isRecording = false);

    final elapsed = _recordingStartTime != null
        ? DateTime.now().difference(_recordingStartTime!)
        : Duration.zero;
    _recordingStartTime = null;
    if (elapsed.inMilliseconds < 2000) return;

    if (path == null) return;

    final bytes = await File(path).readAsBytes();
    try {
      await File(path).delete();
    } catch (e) {
      debugPrint('Failed to delete temp audio file: $e');
    }

    if (bytes.isEmpty) return;
    await _sendAudioMessage(bytes, question, materials);
  }

  Future<void> _sendAudioMessage(
    Uint8List audioBytes,
    Question question,
    List<StudyMaterial> materials,
  ) async {
    if (!_chatService.hasSession) {
      try {
        await _fireOpener(question, materials);
      } catch (e) {
        if (mounted) {
          final l10n = AppLocalizations.of(context)!;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.chatFailedToStartSession)),
          );
        }
        return;
      }
    }

    setState(() {
      _sending = true;
      _sendEra++;
      _streamingContent = '';
      _thinkingContent = null;
      _thinkingExpanded = false;
      _messages.add(QuestionMessage(
        questionId: widget.questionId,
        role: QuestionMessageRole.user,
        content: _kVoiceSentinel,
        createdAt: DateTime.now(),
      ));
    });
    _scrollToBottom();

    try {
      final stream = _chatService.sendUserAudio(audioBytes);
      final result = await _handleTutorStream(stream);
      _thinkingSpeechFired = false;
      unawaited(_ttsService.speak(result.reply));

      if (mounted) {
        setState(() {
          if (result.reply.isNotEmpty) {
            _messages.add(QuestionMessage(
              questionId: widget.questionId,
              role: QuestionMessageRole.assistant,
              content: result.reply,
              createdAt: DateTime.now(),
            ));
          }
          _streamingContent = null;
          _sending = false;
          _thinkingContent = result.thinking.isEmpty ? null : result.thinking;
          _thinkingExpanded = false;
        });
      }
      _scrollToBottom();
    } catch (e) {
      debugPrint('Audio stream error: $e');
      _tokenCount = 0;
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        setState(() {
          _streamingContent = null;
          _thinkingContent = null;
          _sending = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.chatSessionInterrupted),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Message Sending
  // ---------------------------------------------------------------------------

  Future<void> _sendMessage(
    Question question,
    List<StudyMaterial> materials,
  ) async {
    final text = _textController.text.trim();
    if ((text.isEmpty && _attachedImages.isEmpty) || _sending) return;

    if (!_chatService.hasSession) {
      try {
        await _fireOpener(question, materials);
      } catch (e) {
        if (mounted) {
          final l10n = AppLocalizations.of(context)!;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.chatFailedToStartSession)),
          );
        }
        return;
      }
    }

    final imageBytes = <Uint8List>[];
    for (final image in _attachedImages) {
      try {
        final bytes = await image.readAsBytes();
        imageBytes.add(bytes);
      } catch (e) {
        debugPrint('Failed to read image bytes: $e');
      }
    }

    setState(() {
      _sending = true;
      _sendEra++;
      _streamingContent = '';
      _thinkingContent = null;
      _thinkingExpanded = false;
      _messages.add(QuestionMessage(
        questionId: widget.questionId,
        role: QuestionMessageRole.user,
        content: text,
        createdAt: DateTime.now(),
      ));
      if (_attachedImages.isNotEmpty) {
        _messageImages[_messages.length - 1] = List.from(_attachedImages);
      }
    });
    _textController.clear();
    _clearImages();
    setState(() {});
    _scrollToBottom();

    try {
      final stream = _chatService.sendMessage(text, images: imageBytes);
      final result = await _handleTutorStream(stream);
      _thinkingSpeechFired = false;
      unawaited(_ttsService.speak(result.reply));

      if (mounted) {
        setState(() {
          if (result.reply.isNotEmpty) {
            _messages.add(QuestionMessage(
              questionId: widget.questionId,
              role: QuestionMessageRole.assistant,
              content: result.reply,
              createdAt: DateTime.now(),
            ));
          }
          _streamingContent = null;
          _sending = false;
          _thinkingContent = result.thinking.isEmpty ? null : result.thinking;
          _thinkingExpanded = false;
        });
      }
      _scrollToBottom();
    } catch (e) {
      debugPrint('Tutor stream error: $e');
      _tokenCount = 0;
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        setState(() {
          _streamingContent = null;
          _thinkingContent = null;
          _sending = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.chatSessionInterrupted),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final questionAsync = ref.watch(questionProvider(widget.questionId));
    final materialsAsync = ref.watch(materialsProvider(widget.sessionId));
    final materials = materialsAsync.valueOrNull ?? const <StudyMaterial>[];
    final materialsReady = materialsAsync.hasValue;

    final currentQuestion = questionAsync.valueOrNull;

    if (!_openerFired &&
        _chatService.isInitialized &&
        currentQuestion != null &&
        materialsReady) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fireOpener(currentQuestion, materials);
      });
    }

    return questionAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) =>
          Scaffold(body: Center(child: Text(l10n.chatError(e.toString())))),
      data: (question) {
        if (question == null) {
          return Scaffold(
            appBar: AppBar(leading: const BackButton()),
            body: Center(child: Text(l10n.questionChatNotFound)),
          );
        }

        final hasThinking = _thinkingContent != null;
        final hasStreaming = _streamingContent != null;
        final isEmpty = _messages.isEmpty && !hasThinking && !hasStreaming;

        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.pop(),
            ),
            title: Text(
              l10n.questionChatTitle(question.orderIndex + 1),
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            actions: [
              IconButton(
                icon: Icon(
                  _ttsService.isMuted
                      ? Icons.volume_off_rounded
                      : Icons.volume_up_rounded,
                  color: scheme.onSurfaceVariant,
                ),
                onPressed: () async {
                  await _ttsService.setMuted(!_ttsService.isMuted);
                  setState(() {});
                },
              ),
              if (!isEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: TextButton(
                    onPressed: _sending
                        ? null
                        : () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) {
                                final dialogL10n = AppLocalizations.of(ctx);
                                return AlertDialog(
                                  title: Text(dialogL10n?.chatResetQuestion ??
                                      'Reset chat?'),
                                  content: Text(dialogL10n?.chatResetConfirm ??
                                      'This will clear all messages'),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
                                      child:
                                          Text(dialogL10n?.cancel ?? 'Cancel'),
                                    ),
                                    FilledButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: Text(
                                          dialogL10n?.chatReset ?? 'Reset'),
                                    ),
                                  ],
                                );
                              },
                            );
                            if (confirm == true) {
                              unawaited(_resetChat(question, materials));
                            }
                          },
                    child: Text(l10n.chatReset),
                  ),
                ),
            ],
          ),
          body: Stack(
            children: [
              Column(
                children: [
                  if (materials.isNotEmpty)
                    MaterialsStrip(
                      materials: materials,
                      sessionId: widget.sessionId,
                      scheme: scheme,
                      theme: theme,
                    ),
                  if ((_currentScore ?? question.score) != null)
                    _ScoreBadgeRow(
                      score: _currentScore ?? question.score ?? 0.0,
                      scheme: scheme,
                      theme: theme,
                    ),
                  Expanded(
                    child: _ThreadList(
                      question: question,
                      messages: _messages,
                      streamingContent: _streamingContent,
                      thinkingContent: _thinkingContent,
                      thinkingExpanded: _thinkingExpanded,
                      onThinkingToggle: () =>
                          setState(() => _thinkingExpanded = !_thinkingExpanded),
                      isSending: _sending,
                      scrollController: _scrollController,
                      scheme: scheme,
                      theme: theme,
                      messageImages: _messageImages,
                    ),
                  ),
                  ImageAttachmentRow(
                    images: _attachedImages,
                    isRecording: _isRecording,
                    onAddImage: _addImage,
                    onRemoveImage: _removeImage,
                    scheme: scheme,
                    theme: theme,
                  ),
                  ChatInputBar(
                    controller: _textController,
                    sending: _sending,
                    sendEra: _sendEra,
                    modelLoading: _modelLoading,
                    onSend: () => _sendMessage(question, materials),
                    onStop: _stopGeneration,
                    isRecording: _isRecording,
                    onMicStart: _startRecording,
                    onMicStop: () => _stopAndSendAudio(question, materials),
                    scheme: scheme,
                    theme: theme,
                  ),
                  ThinkingModeToggle(
                    isThinkingMode: _isThinkingMode,
                    totalTokens: _totalTokens,
                    maxTokens: _maxTokens,
                    onToggle: () => _toggleThinkingMode(question, materials),
                    scheme: scheme,
                    theme: theme,
                  ),
                ],
              ),
              if (_modelLoading ||
                  (_sending &&
                      _messages.isEmpty &&
                      (_streamingContent == null ||
                          _streamingContent!.isEmpty)))
                ModelLoadingOverlay(
                  scheme: scheme,
                  theme: theme,
                  isWaitingForResponse: !_modelLoading && _sending,
                ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Score badge row ─────────────────────────────────────────────────────────

class _ScoreBadgeRow extends StatelessWidget {
  final double score;
  final ColorScheme scheme;
  final ThemeData theme;

  const _ScoreBadgeRow({
    required this.score,
    required this.scheme,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final Color color;
    final String label;
    final IconData icon;

    if (score >= 0.8) {
      color = const Color(0xFF4CAF50);
      label = l10n.questionChatScoreCorrect;
      icon = Icons.check_circle;
    } else if (score >= 0.4) {
      color = const Color(0xFFFFB347);
      label = l10n.questionChatScorePartial;
      icon = Icons.remove_circle;
    } else {
      color = const Color(0xFFFF6B6B);
      label = l10n.questionChatScoreIncorrect;
      icon = Icons.cancel;
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: Br.md,
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            '${(score * 100).round()}%',
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Question card ───────────────────────────────────────────────────────────

class _QuestionCard extends StatelessWidget {
  final Question question;
  final ColorScheme scheme;
  final ThemeData theme;

  const _QuestionCard({
    required this.question,
    required this.scheme,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final hasOptions = question.type == QuestionType.multipleChoice &&
        question.options.isNotEmpty;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: double.infinity,
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(18),
          ),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.questionChatQuestionLabel,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 8),
              MathMarkdownBody(
                data: question.questionText,
                styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                  p: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                    height: 1.25,
                  ),
                ),
                textStyle: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                  height: 1.25,
                ),
              ),
              if (hasOptions) ...[
                const SizedBox(height: 14),
                ...question.options.asMap().entries.map((entry) {
                  final letter = String.fromCharCode(65 + entry.key);
                  final isLast = entry.key == question.options.length - 1;
                  return Padding(
                    padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 24,
                          child: Text(
                            '$letter.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Expanded(
                          child: MathMarkdownBody(
                            data: entry.value,
                            styleSheet:
                                MarkdownStyleSheet.fromTheme(theme).copyWith(
                              p: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                                height: 1.35,
                              ),
                            ),
                            textStyle: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Conversation thread ─────────────────────────────────────────────────────

class _ThreadList extends StatelessWidget {
  final Question question;
  final List<QuestionMessage> messages;
  final String? streamingContent;
  final String? thinkingContent;
  final bool thinkingExpanded;
  final VoidCallback onThinkingToggle;
  final bool isSending;
  final ScrollController scrollController;
  final ColorScheme scheme;
  final ThemeData theme;
  final Map<int, List<File>> messageImages;

  const _ThreadList({
    required this.question,
    required this.messages,
    required this.streamingContent,
    required this.thinkingContent,
    required this.thinkingExpanded,
    required this.onThinkingToggle,
    required this.isSending,
    required this.scrollController,
    required this.scheme,
    required this.theme,
    required this.messageImages,
  });

  @override
  Widget build(BuildContext context) {
    final hasThinking = thinkingContent != null;
    final hasStreaming = streamingContent != null;
    final extraItems = (hasThinking ? 1 : 0) + (hasStreaming ? 1 : 0);
    final totalItems = 1 + messages.length + extraItems;

    final screenWidth = MediaQuery.sizeOf(context).width;
    final maxBubbleWidth = screenWidth * 0.78;
    final markdownStyle = MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurface),
    );
    final textStyle =
        theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurface);

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      itemCount: totalItems,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _QuestionCard(
              question: question,
              scheme: scheme,
              theme: theme,
            ),
          );
        }

        final messageIndex = index - 1;

        if (hasThinking && messageIndex == messages.length) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: ThinkingBubble(
              content: thinkingContent!,
              expanded: thinkingExpanded,
              isStreaming:
                  isSending && streamingContent != null ? false : isSending,
              onToggle: onThinkingToggle,
              scheme: scheme,
              theme: theme,
            ),
          );
        }

        final replyIndex = messages.length + (hasThinking ? 1 : 0);
        if (hasStreaming && messageIndex == replyIndex) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                    bottomLeft: Radius.circular(4),
                    bottomRight: Radius.circular(18),
                  ),
                ),
                child: streamingContent!.isEmpty
                    ? TypingIndicator(scheme: scheme)
                    : MathMarkdownBody(
                        data: streamingContent!,
                        styleSheet: markdownStyle,
                        textStyle: textStyle,
                      ),
              ),
            ),
          );
        }

        final msg = messages[messageIndex];
        final isUser = msg.role == QuestionMessageRole.user;
        final images = messageImages[messageIndex];

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment:
                isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (isUser && images != null && images.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: images.map((image) {
                      return SizedBox(
                        width: 80,
                        height: 80,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            image,
                            width: 80,
                            height: 80,
                            fit: BoxFit.cover,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              Align(
                alignment:
                    isUser ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isUser
                        ? scheme.primaryContainer
                        : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(isUser ? 18 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 18),
                    ),
                  ),
                  child: isUser
                      ? (msg.content == _kVoiceSentinel
                          ? VoiceMessageBubble(scheme: scheme, theme: theme)
                          : Text(
                              msg.content,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onPrimaryContainer,
                              ),
                            ))
                      : MathMarkdownBody(
                          data: msg.content,
                          styleSheet: markdownStyle,
                          textStyle: textStyle,
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
