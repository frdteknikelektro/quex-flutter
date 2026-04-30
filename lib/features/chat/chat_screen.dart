import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as pathlib;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../app/breakpoints.dart';
import '../../app/theme.dart';
import '../../core/ai/session_chat_service.dart';
import '../../core/ai/quex_ai.dart';
import '../../core/models/models.dart';
import '../../core/state/app_state.dart';
import '../../core/utils/image_normalizer.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../widgets/math_markdown.dart';

/// Sentinel value for voice messages in chat.
const String _kVoiceSentinel = '__voice__';

/// Chat screen for interacting with the AI tutor.
///
/// Displays a conversation interface with support for text and voice input,
/// streaming responses, and thinking process visualization.
class ChatScreen extends ConsumerStatefulWidget {
  final int sessionId;
  final List<int>? preselectedMaterialIds;

  const ChatScreen({
    super.key,
    required this.sessionId,
    this.preselectedMaterialIds,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  // ===========================================================================
  // Controllers
  // ===========================================================================
  final _textController = TextEditingController();
  final _scrollController = ScrollController();

  // ===========================================================================
  // Services
  // ===========================================================================
  final SessionChatService _sessionService = SessionChatService();
  StreamSubscription<({String? text, String? thinking})>? _streamSub;

  // ===========================================================================
  // Chat State
  // ===========================================================================
  final List<ChatMessage> _messages = [];
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

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      if (mounted) setState(() => _modelLoading = true);
      await _sessionService.initialize();
      // Get effective max tokens from the service (applies upper bound to default)
      final effectiveMaxTokens = _sessionService.effectiveMaxTokens ?? 8192;
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

    // Cleanup async operations
    _cleanupOnDispose();

    super.dispose();
  }

  void _cleanupOnDispose() async {
    try {
      await _sessionService.dispose();
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

  /// Create chat session with materials as context.
  Future<void> _ensureSession(
    Session session,
    List<StudyMaterial> materials,
  ) async {
    if (_sessionService.hasSession) return;

    final l10n = AppLocalizations.of(context);
    await _sessionService.createSession(
      session: session,
      materials: materials,
      locale: l10n?.localeName ?? 'en',
      isThinking: _isThinkingMode,
    );
  }

  Future<void> _resetChat(
    SessionBundle bundle,
    List<StudyMaterial> chatMaterials,
  ) async {
    await _streamSub?.cancel();
    _streamSub = null;
    _clearImages();
    _messageImages.clear();
    await _sessionService.resetSession();
    if (mounted) {
      setState(() {
        _messages.clear();
        // Session reset via _sessionService.resetSession()
        _sending = false;
        _streamingContent = null;
        _thinkingContent = null;
        _openerFired = false;
      });
    }
    unawaited(_fireOpener(bundle, chatMaterials));
  }

  Future<void> _toggleThinkingMode(
    SessionBundle bundle,
    List<StudyMaterial> chatMaterials,
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
        _sending = true; // Show waiting modal immediately
      });
      await _resetChat(bundle, chatMaterials);
    }
  }

  // ---------------------------------------------------------------------------
  // Message Handling
  // ---------------------------------------------------------------------------

  Future<void> _fireOpener(
    SessionBundle bundle,
    List<StudyMaterial> chatMaterials,
  ) async {
    if (_openerFired) return;

    try {
      await _ensureSession(bundle.session, chatMaterials);
    } catch (_) {
      // Reset state so we can retry on next build
      if (mounted) {
        setState(() {
          _openerFired = false;
          _sending = false;
        });
      }
      return;
    }

    // Mark as fired only after successful session creation
    _openerFired = true;

    if (!mounted) return;
    setState(() {
      _sending = true;
      _streamingContent = '';
      _thinkingContent = null;
    });

    try {
      final l10n = AppLocalizations.of(context);
      final locale = l10n?.localeName ?? 'en';

      // Convert attached images to bytes if user attached images before opener
      debugPrint(
          '[ChatScreen] _fireOpener: ${_attachedImages.length} images in _attachedImages');
      final imageBytes = <Uint8List>[];
      for (final image in _attachedImages) {
        try {
          final bytes = await image.readAsBytes();
          debugPrint(
              '[ChatScreen] _fireOpener: Read ${bytes.length} bytes from ${image.path}');
          imageBytes.add(bytes);
        } catch (e) {
          debugPrint(
              '[ChatScreen] _fireOpener: Failed to read opener image bytes: $e');
        }
      }
      debugPrint(
          '[ChatScreen] _fireOpener: Sending opener with ${imageBytes.length} images');

      final stream = _sessionService.sendOpener(locale, images: imageBytes);
      final result = await _handleStream(stream);

      // Clear attached images after sending with opener
      _clearImages();

      if (mounted) {
        setState(() {
          if (result.reply.isNotEmpty) {
            _messages.add(ChatMessage(
              sessionId: widget.sessionId,
              role: ChatRole.assistant,
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
          // Session reset via _sessionService.resetSession()
          _streamingContent = null;
          _thinkingContent = null;
          _sending = false;
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Streaming & UI Helpers
  // ---------------------------------------------------------------------------

  Future<void> _stopGeneration() async {
    await _streamSub?.cancel();
    _streamSub = null;
    _tokenCount = 0;
    await _sessionService.stopGeneration();
    if (mounted) {
      setState(() {
        _sending = false;
        _streamingContent = null;
        _thinkingContent = null;
      });
    }
  }

  Future<({String reply, String thinking})> _handleStream(
    Stream<({String? text, String? thinking})> stream,
  ) async {
    final accumulatedReply = StringBuffer();
    final accumulatedThinking = StringBuffer();
    final completer = Completer<void>();
    _tokenCount = 0;

    await _streamSub?.cancel();
    _streamSub = stream.listen(
      (event) {
        if (!mounted) return;
        if (event.thinking != null) {
          accumulatedThinking.write(event.thinking);
          if (mounted) {
            setState(() => _thinkingContent = accumulatedThinking.toString());
          }
        } else if (event.text != null) {
          accumulatedReply.write(event.text);
          if (mounted) {
            setState(() => _streamingContent = accumulatedReply.toString());
          }
          _tokenCount++;
          if (_tokenCount % _scrollThrottleTokens == 0) {
            _scrollToBottom();
          }
        }
      },
      onDone: () {
        _scrollToBottom();
        if (mounted) {
          // Get accurate token count from metrics (FFI/.litertlm only)
          // Falls back to 0 if metrics not available (MediaPipe/Web)
          _captureSessionMetrics();
        }
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

  /// Capture session metrics after generation completes.
  /// Uses totalTokens from metrics for accurate session-wide counting on FFI platforms.
  /// On MediaPipe/Web: _totalTokens will be 0 (metrics unavailable).
  void _captureSessionMetrics() {
    try {
      final metrics = _sessionService.getSessionMetrics();
      debugPrint('SessionMetrics: raw metrics=$metrics');
      if (metrics == null) {
        debugPrint('SessionMetrics: metrics is null (MediaPipe platform)');
        if (mounted) setState(() => _totalTokens = 0);
        return;
      }

      // Access metrics fields dynamically
      final dynamic m = metrics;
      final metricsTotal = m.totalTokens as int? ?? 0;

      debugPrint('SessionMetrics: totalTokens=$metricsTotal');

      // Use metrics total (0 if unavailable on this platform)
      if (mounted) {
        setState(() => _totalTokens = metricsTotal);
        debugPrint('SessionMetrics: applied _totalTokens=$metricsTotal');
      }
    } catch (e, st) {
      debugPrint('Failed to capture session metrics: $e');
      debugPrint('Stack trace: $st');
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

    if (mounted) {
      setState(() => _sending = true);
    }

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
      if (mounted) {
        setState(() => _sending = false);
      }
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
      setState(() {
        _attachedImages.removeAt(index);
      });
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
            content: Text(l10n?.chatMicPermissionDenied ??
                'Microphone permission denied'),
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
      if (mounted) {
        setState(() => _isRecording = false);
      }
    }
  }

  Future<void> _stopAndSendAudio(
    SessionBundle bundle,
    List<StudyMaterial> chatMaterials,
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
    await _sendAudioMessage(bytes, bundle, chatMaterials);
  }

  Future<void> _sendAudioMessage(
    Uint8List audioBytes,
    SessionBundle bundle,
    List<StudyMaterial> chatMaterials,
  ) async {
    try {
      await _ensureSession(bundle.session, chatMaterials);
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                l10n?.chatFailedToStartSession ?? 'Failed to start session'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    setState(() {
      _sending = true;
      _streamingContent = '';
      _thinkingContent = null;
      _thinkingExpanded = false;
      _messages.add(ChatMessage(
        sessionId: widget.sessionId,
        role: ChatRole.user,
        content: _kVoiceSentinel,
        createdAt: DateTime.now(),
      ));
    });
    _scrollToBottom();

    try {
      final stream = _sessionService.sendUserAudio(audioBytes);
      final result = await _handleStream(stream);

      if (mounted) {
        setState(() {
          if (result.reply.isNotEmpty) {
            _messages.add(ChatMessage(
              sessionId: widget.sessionId,
              role: ChatRole.assistant,
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
        final l10n = AppLocalizations.of(context);
        setState(() {
          // Session reset via _sessionService.resetSession()
          _streamingContent = null;
          _thinkingContent = null;
          _sending = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(l10n?.chatSessionInterrupted ?? 'Session interrupted'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _sendMessage(
    SessionBundle bundle,
    List<StudyMaterial> chatMaterials,
  ) async {
    final text = _textController.text.trim();
    if ((text.isEmpty && _attachedImages.isEmpty) || _sending) return;

    // Initialize session once per screen visit.
    try {
      await _ensureSession(bundle.session, chatMaterials);
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                l10n?.chatFailedToStartSession ?? 'Failed to start session'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    // Convert attached images to bytes for Gemma
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
      _streamingContent = '';
      _thinkingContent = null;
      _thinkingExpanded = false;
      final message = ChatMessage(
        sessionId: widget.sessionId,
        role: ChatRole.user,
        content: text,
        createdAt: DateTime.now(),
      );
      _messages.add(message);
      // Store images with the message index
      if (_attachedImages.isNotEmpty) {
        _messageImages[_messages.length - 1] = List.from(_attachedImages);
      }
    });
    _textController.clear();
    _clearImages(); // async - call outside setState
    setState(() {}); // just trigger rebuild
    _scrollToBottom();

    try {
      final stream = _sessionService.sendUserMessage(text, images: imageBytes);
      final result = await _handleStream(stream);

      if (mounted) {
        setState(() {
          if (result.reply.isNotEmpty) {
            _messages.add(ChatMessage(
              sessionId: widget.sessionId,
              role: ChatRole.assistant,
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
      debugPrint('Stream error: $e');
      _tokenCount = 0;

      if (mounted) {
        final l10n = AppLocalizations.of(context);
        setState(() {
          // Session reset via _sessionService.resetSession()
          _streamingContent = null;
          _thinkingContent = null;
          _sending = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(l10n?.chatSessionInterrupted ?? 'Session interrupted'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final compact = MediaQuery.sizeOf(context).width < QuexBreakpoints.tablet;

    final bundleAsync = ref.watch(sessionBundleProvider(widget.sessionId));

    return bundleAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
          body: Center(
              child: Text(l10n?.chatError(e.toString()) ?? 'Error: $e'))),
      data: (bundle) {
        if (bundle == null) {
          return Scaffold(
            appBar: AppBar(leading: const BackButton()),
            body: Center(
                child: Text(l10n?.chatSessionNotFound ?? 'Session not found')),
          );
        }

        final messages = _messages;
        final hasThinking = _thinkingContent != null;
        final hasStreaming = _streamingContent != null;
        final isEmpty = messages.isEmpty && !hasThinking && !hasStreaming;

        final chatMaterials = widget.preselectedMaterialIds == null
            ? bundle.materials
            : bundle.materials
                .where((m) => widget.preselectedMaterialIds!.contains(m.id))
                .toList();

        final suggestions = QuexAi.highlights(chatMaterials);

        // Fire opener once when bundle and materials are ready
        if (!_openerFired && _sessionService.isInitialized) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _fireOpener(bundle, chatMaterials);
          });
        }

        final chatColumn = Column(
          children: [
            if (chatMaterials.isNotEmpty)
              MaterialsStrip(
                materials: chatMaterials,
                sessionId: widget.sessionId,
                scheme: scheme,
                theme: theme,
              ),
            Expanded(
              child: isEmpty
                  ? EmptyChatPlaceholder(
                      scheme: scheme,
                      theme: theme,
                    )
                  : MessageList(
                      messages: messages,
                      streamingContent: _streamingContent,
                      thinkingContent: _thinkingContent,
                      thinkingExpanded: _thinkingExpanded,
                      onThinkingToggle: () => setState(
                          () => _thinkingExpanded = !_thinkingExpanded),
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
              modelLoading: _modelLoading,
              onSend: () => _sendMessage(bundle, chatMaterials),
              onStop: _stopGeneration,
              isRecording: _isRecording,
              onMicStart: _startRecording,
              onMicStop: () => _stopAndSendAudio(bundle, chatMaterials),
              scheme: scheme,
              theme: theme,
            ),
            ThinkingModeToggle(
              isThinkingMode: _isThinkingMode,
              totalTokens: _totalTokens,
              maxTokens: _maxTokens,
              onToggle: () => _toggleThinkingMode(bundle, chatMaterials),
              scheme: scheme,
              theme: theme,
            ),
          ],
        );

        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () =>
                  context.canPop() ? context.pop() : context.go('/'),
            ),
            title: Text(
              '${bundle.session.emoji} ${bundle.session.title}',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            actions: [
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
                              unawaited(_resetChat(bundle, chatMaterials));
                            }
                          },
                    child: Text(l10n?.chatReset ?? 'Reset'),
                  ),
                ),
            ],
          ),
          body: Stack(
            children: [
              compact
                  ? chatColumn
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: chatColumn),
                        Container(width: 1, color: scheme.outlineVariant),
                        SizedBox(
                          width: 280,
                          child: TipsPanel(
                            session: bundle.session,
                            suggestions: suggestions,
                            scheme: scheme,
                            theme: theme,
                          ),
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

// =============================================================================
// UI WIDGETS - Materials
// =============================================================================

/// A horizontal scrollable strip displaying study materials as thumbnails.
class MaterialsStrip extends StatelessWidget {
  final List<StudyMaterial> materials;
  final int sessionId;
  final ColorScheme scheme;
  final ThemeData theme;

  const MaterialsStrip({
    super.key,
    required this.materials,
    required this.sessionId,
    required this.scheme,
    required this.theme,
  });

  static ({String emoji, Color color}) _kindMeta(
          MaterialKind kind, ColorScheme scheme) =>
      switch (kind) {
        MaterialKind.text => (emoji: '📝', color: scheme.primaryContainer),
        MaterialKind.document => (
            emoji: '📄',
            color: scheme.secondaryContainer
          ),
        MaterialKind.photo => (emoji: '🖼️', color: scheme.tertiaryContainer),
      };

  static const double _thumbSize = 54;

  Widget _buildThumbnail(StudyMaterial m, ColorScheme scheme) {
    if (m.kind == MaterialKind.photo && m.content.isNotEmpty) {
      final firstPath = m.content.split('\n').firstWhere(
            (p) => p.isNotEmpty,
            orElse: () => '',
          );
      if (firstPath.isNotEmpty) {
        return ClipRRect(
          borderRadius: Br.sm,
          child: Image.file(
            File(firstPath),
            width: _thumbSize,
            height: _thumbSize,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _emojiAvatar(m.kind, scheme),
          ),
        );
      }
    }
    return _emojiAvatar(m.kind, scheme);
  }

  Widget _emojiAvatar(MaterialKind kind, ColorScheme scheme) {
    final meta = _kindMeta(kind, scheme);
    return Container(
      width: _thumbSize,
      height: _thumbSize,
      decoration: BoxDecoration(color: meta.color, borderRadius: Br.sm),
      alignment: Alignment.center,
      child: Text(meta.emoji, style: const TextStyle(fontSize: 22)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 96,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        itemCount: materials.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final m = materials[index];
          return SizedBox(
            width: 64,
            child: InkWell(
              borderRadius: Br.sm,
              onTap: () async {
                if (m.kind == MaterialKind.document) {
                  final result = await OpenFilex.open(m.content);
                  if (result.type != ResultType.done && context.mounted) {
                    final l10n = AppLocalizations.of(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(
                              l10n?.materialCouldNotOpen(result.message) ??
                                  'Could not open file')),
                    );
                  }
                } else {
                  context.push('/session/$sessionId/material/${m.id}');
                }
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _buildThumbnail(m, scheme),
                  const SizedBox(height: 2),
                  Text(
                    m.title,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontSize: 10,
                      height: 1.1,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// =============================================================================
// UI WIDGETS - Messages
// =============================================================================

/// Displays a scrollable list of chat messages with streaming and thinking states.
class MessageList extends StatelessWidget {
  final List<ChatMessage> messages;
  final String? streamingContent;
  final String? thinkingContent;
  final bool thinkingExpanded;
  final VoidCallback onThinkingToggle;
  final bool isSending;
  final ScrollController scrollController;
  final ColorScheme scheme;
  final ThemeData theme;
  final Map<int, List<File>> messageImages;

  const MessageList({
    super.key,
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
    final totalItems = messages.length + extraItems;

    // Cache expensive calculations
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
        if (hasThinking && index == messages.length) {
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
        if (hasStreaming && index == replyIndex) {
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

        final msg = messages[index];
        final isUser = msg.role == ChatRole.user;
        final images = messageImages[index];

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment:
                isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              // Show image thumbnails for user messages
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
              // Message bubble
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

/// An expandable bubble showing the AI's thinking process.
class ThinkingBubble extends StatelessWidget {
  final String content;
  final bool expanded;
  final bool isStreaming;
  final VoidCallback onToggle;
  final ColorScheme scheme;
  final ThemeData theme;

  const ThinkingBubble({
    super.key,
    required this.content,
    required this.expanded,
    required this.isStreaming,
    required this.onToggle,
    required this.scheme,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final labelColor = scheme.onSurfaceVariant;
    final bgColor = scheme.surfaceContainerLow;
    final borderColor = scheme.outlineVariant;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.85,
        ),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: Br.md,
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: content.isEmpty ? null : onToggle,
              borderRadius: expanded
                  ? const BorderRadius.vertical(top: Radius.circular(16))
                  : Br.md,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isStreaming)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: TypingIndicator(scheme: scheme),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Icon(Icons.psychology_outlined,
                            size: 14, color: labelColor),
                      ),
                    Text(
                      isStreaming ? l10n.chatThinking : l10n.chatThoughtProcess,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: labelColor,
                        fontWeight: FontWeight.w600,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    if (!isStreaming && content.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Icon(
                        expanded ? Icons.expand_less : Icons.expand_more,
                        size: 14,
                        color: labelColor,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (expanded && content.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: MathMarkdownBody(
                  data: content,
                  styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                    p: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                      height: 1.5,
                    ),
                  ),
                  textStyle: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                    height: 1.5,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Animated typing indicator with three pulsing dots.
class TypingIndicator extends StatefulWidget {
  final ColorScheme scheme;

  const TypingIndicator({super.key, required this.scheme});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final offset = i / 3;
            final t = ((_controller.value + offset) % 1.0);
            final opacity = (t < 0.5 ? t * 2 : (1 - t) * 2).clamp(0.3, 1.0);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Opacity(
                opacity: opacity,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: widget.scheme.onSurfaceVariant,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

/// Placeholder shown when the chat has no messages.
class EmptyChatPlaceholder extends StatelessWidget {
  final ColorScheme scheme;
  final ThemeData theme;

  const EmptyChatPlaceholder({
    super.key,
    required this.scheme,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline,
                size: 48, color: scheme.outlineVariant),
            const SizedBox(height: 16),
            Text(
              l10n.chatAskQuex,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.chatAskQuexSubtitle,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// UI WIDGETS - Sidebar
// =============================================================================

/// Sidebar panel showing session info and topic suggestions (tablet layout).
class TipsPanel extends StatelessWidget {
  final Session session;
  final List<String> suggestions;
  final ColorScheme scheme;
  final ThemeData theme;

  const TipsPanel({
    super.key,
    required this.session,
    required this.suggestions,
    required this.scheme,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.chatSession,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            '${session.emoji} ${session.title}',
            style:
                theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurface),
          ),
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              l10n.chatSuggestedTopics,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            SuggestionChipsList(
              suggestions: suggestions,
              scheme: scheme,
              theme: theme,
            ),
          ],
        ],
      ),
    );
  }
}

/// Wrap of suggestion chips for the sidebar panel.
class SuggestionChipsList extends StatelessWidget {
  final List<String> suggestions;
  final ColorScheme scheme;
  final ThemeData theme;

  const SuggestionChipsList({
    super.key,
    required this.suggestions,
    required this.scheme,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final s in suggestions)
          Chip(
            label: Text(s,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            backgroundColor: scheme.surfaceContainerLow,
            side: BorderSide(color: scheme.outlineVariant),
            padding: EdgeInsets.zero,
          ),
      ],
    );
  }
}

// =============================================================================
// UI WIDGETS - Input
// =============================================================================

/// Main chat input bar with text field, send/stop button, and mic button.
class ChatInputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final bool modelLoading;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final bool isRecording;
  final VoidCallback onMicStart;
  final VoidCallback onMicStop;
  final ColorScheme scheme;
  final ThemeData theme;

  const ChatInputBar({
    super.key,
    required this.controller,
    required this.sending,
    required this.modelLoading,
    required this.onSend,
    required this.onStop,
    required this.isRecording,
    required this.onMicStart,
    required this.onMicStop,
    required this.scheme,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      decoration: BoxDecoration(
        color: scheme.surface,
      ),
      child: Row(
        children: [
          Expanded(
            child: isRecording
                ? ListeningIndicator(scheme: scheme, theme: theme)
                : TextField(
                    controller: controller,
                    enabled: !sending && !modelLoading,
                    textInputAction: TextInputAction.newline,
                    maxLines: 4,
                    minLines: 1,
                    decoration: InputDecoration(
                      hintText: l10n.chatAskQuexHint,
                      hintStyle: TextStyle(color: scheme.onSurfaceVariant),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: scheme.outlineVariant),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: scheme.outlineVariant),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide:
                            BorderSide(color: scheme.primary, width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      isDense: true,
                    ),
                  ),
          ),
          if (!isRecording) const SizedBox(width: 8),
          if (!isRecording)
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: modelLoading
                  ? SizedBox(
                      key: const ValueKey('loading'),
                      width: 44,
                      height: 44,
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: scheme.primary,
                          ),
                        ),
                      ),
                    )
                  : sending
                      ? IconButton(
                          key: const ValueKey('stop'),
                          onPressed: onStop,
                          icon: Icon(Icons.stop_rounded,
                              color: scheme.onErrorContainer),
                          style: IconButton.styleFrom(
                            backgroundColor: scheme.errorContainer,
                            minimumSize: const Size(44, 44),
                          ),
                        )
                      : IconButton(
                          key: const ValueKey('send'),
                          onPressed: onSend,
                          icon: Icon(Icons.send_rounded, color: scheme.primary),
                          style: IconButton.styleFrom(
                            backgroundColor: scheme.primaryContainer,
                            minimumSize: const Size(44, 44),
                          ),
                        ),
            ),
          if (!sending && !modelLoading) ...[
            const SizedBox(width: 8),
            MicButton(
              isRecording: isRecording,
              onMicStart: onMicStart,
              onMicStop: onMicStop,
              scheme: scheme,
            ),
          ],
        ],
      ),
    );
  }
}

/// Long-press microphone button for voice recording.
class MicButton extends StatelessWidget {
  final bool isRecording;
  final VoidCallback onMicStart;
  final VoidCallback onMicStop;
  final ColorScheme scheme;

  const MicButton({
    super.key,
    required this.isRecording,
    required this.onMicStart,
    required this.onMicStop,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: (_) => onMicStart(),
      onLongPressEnd: (_) => onMicStop(),
      onLongPressCancel: onMicStop,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isRecording ? scheme.errorContainer : scheme.primaryContainer,
        ),
        child: Icon(
          isRecording ? Icons.mic : Icons.mic_none_rounded,
          color: isRecording ? scheme.onErrorContainer : scheme.primary,
          size: 22,
        ),
      ),
    );
  }
}

/// Row showing attached image thumbnails with remove buttons.
class ImageAttachmentRow extends StatelessWidget {
  final List<File> images;
  final bool isRecording;
  final VoidCallback onAddImage;
  final Function(int) onRemoveImage;
  final ColorScheme scheme;
  final ThemeData theme;

  const ImageAttachmentRow({
    super.key,
    required this.images,
    required this.isRecording,
    required this.onAddImage,
    required this.onRemoveImage,
    required this.scheme,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    if (isRecording) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      decoration: BoxDecoration(
        color: scheme.surface,
      ),
      child: SizedBox(
        height: 48,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: images.length + (images.length < 4 ? 1 : 0),
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            if (index < images.length) {
              return _ImageThumbnail(
                image: images[index],
                onRemove: () => onRemoveImage(index),
                scheme: scheme,
              );
            } else {
              return _AddImageButton(
                onTap: onAddImage,
                scheme: scheme,
              );
            }
          },
        ),
      ),
    );
  }
}

class _ImageThumbnail extends StatelessWidget {
  final File image;
  final VoidCallback onRemove;
  final ColorScheme scheme;

  const _ImageThumbnail({
    required this.image,
    required this.onRemove,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              image,
              width: 48,
              height: 48,
              fit: BoxFit.cover,
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: scheme.error,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.close,
                  size: 14,
                  color: scheme.onError,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddImageButton extends StatelessWidget {
  final VoidCallback onTap;
  final ColorScheme scheme;

  const _AddImageButton({
    required this.onTap,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: scheme.outlineVariant,
              width: 1,
              style: BorderStyle.solid,
            ),
          ),
          child: Icon(
            Icons.add_photo_alternate_outlined,
            size: 28,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// Animated indicator shown while recording voice input.
class ListeningIndicator extends StatefulWidget {
  final ColorScheme scheme;
  final ThemeData theme;
  const ListeningIndicator(
      {super.key, required this.scheme, required this.theme});

  @override
  State<ListeningIndicator> createState() => _ListeningIndicatorState();
}

class _ListeningIndicatorState extends State<ListeningIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
      ),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Icon(Icons.mic, size: 16, color: widget.scheme.primary),
          const SizedBox(width: 8),
          FadeTransition(
            opacity: _opacity,
            child: Text(
              l10n.chatMicHold,
              style: widget.theme.textTheme.bodyMedium?.copyWith(
                color: widget.scheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// UI WIDGETS - Voice
// =============================================================================

/// Compact indicator showing a voice message was sent.
class VoiceMessageBubble extends StatelessWidget {
  final ColorScheme scheme;
  final ThemeData theme;

  const VoiceMessageBubble(
      {super.key, required this.scheme, required this.theme});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.mic, size: 16, color: scheme.onPrimaryContainer),
        const SizedBox(width: 6),
        Text(
          l10n.chatVoiceMessage,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onPrimaryContainer,
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// UI WIDGETS - Overlays
// =============================================================================

/// Full-screen overlay shown while the AI model is loading or waiting for response.
class ModelLoadingOverlay extends StatelessWidget {
  final ColorScheme scheme;
  final ThemeData theme;
  final bool isWaitingForResponse;

  const ModelLoadingOverlay({
    super.key,
    required this.scheme,
    required this.theme,
    this.isWaitingForResponse = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final emoji = isWaitingForResponse ? '⏳' : '🧠';
    final text = isWaitingForResponse
        ? l10n.chatWaitingForResponse
        : l10n.quizGenLoadingBrain;

    return Container(
      color: scheme.surface,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            PulsingBrain(emoji: emoji),
            const SizedBox(height: 16),
            Text(
              text,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Animated pulsing emoji for the loading overlay.
class PulsingBrain extends StatefulWidget {
  final String emoji;

  const PulsingBrain({super.key, this.emoji = '🧠'});

  @override
  State<PulsingBrain> createState() => _PulsingBrainState();
}

class _PulsingBrainState extends State<PulsingBrain>
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

// =============================================================================
// UI WIDGETS - Thinking Mode Toggle
// =============================================================================

/// Toggle switch for enabling/disabling AI thinking mode.
class ThinkingModeToggle extends StatelessWidget {
  final bool isThinkingMode;
  final int totalTokens;
  final int maxTokens;
  final VoidCallback onToggle;
  final ColorScheme scheme;
  final ThemeData theme;

  const ThinkingModeToggle({
    super.key,
    required this.isThinkingMode,
    required this.totalTokens,
    required this.maxTokens,
    required this.onToggle,
    required this.scheme,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        4,
        16,
        8 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
      ),
      child: Row(
        children: [
          Switch(
            value: isThinkingMode,
            onChanged: (_) => onToggle(),
            activeTrackColor: scheme.primary,
          ),
          const SizedBox(width: 8),
          Text(
            l10n.chatThinkingLabel,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
          const Spacer(),
          Text(
            '$totalTokens / $maxTokens ${l10n.chatTokens}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
