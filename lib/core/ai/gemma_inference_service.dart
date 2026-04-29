import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart' as gemma;

/// Service for running inference using Gemma 4 E4B model.
///
/// Handles model creation and chat sessions with streaming responses.
/// Supports text, multimodal (image), and function calling.
///
/// For higher-level features, see:
/// - [GemmaSessionService] for tutor/coach chat sessions
/// - [GemmaQuizService] for quiz generation
class GemmaInferenceService {
  gemma.InferenceModel? _model;
  gemma.InferenceChat? _chat;
  final List<Uint8List> _pendingImages = [];

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  /// True if active chat session exists.
  bool get hasActiveSession => _chat != null;

  /// True if there are pending images queued for the next message.
  bool get hasPendingImages => _pendingImages.isNotEmpty;

  /// Get the current token count from the active chat session.
  /// Returns 0 if no session is active.
  int get currentTokens => _chat?.currentTokens ?? 0;

  static const int _maxOutputTokens = 8192;

  /// Initialize the inference service by creating the model.
  /// Call this after the model has been downloaded via ModelManager.
  Future<void> initialize({
    int maxTokens = _maxOutputTokens,
    gemma.PreferredBackend preferredBackend = gemma.PreferredBackend.cpu,
  }) async {
    if (_isInitialized) return;

    _model = await gemma.FlutterGemma.getActiveModel(
      maxTokens: maxTokens,
      preferredBackend: preferredBackend,
      supportImage: true,
      supportAudio: true,
      maxNumImages: 32,
    );

    _isInitialized = true;
  }

  /// Create a new session with optional configuration.
  ///
  /// [systemInstruction] - System prompt to guide model behavior
  /// [temperature] - Controls randomness (0.0-1.0, default: 0.8)
  /// [supportImage] - Enable image support for multimodal chat
  /// [isThinking] - Enable thinking mode (for reasoning tasks)
  Future<void> createSession({
    String? systemInstruction,
    double temperature = 0.8,
    int randomSeed = 1,
    int topK = 1,
    gemma.ModelType modelType = gemma.ModelType.gemmaIt,
    bool supportImage = false,
    bool supportAudio = false,
    bool isThinking = false,
    List<gemma.Tool> tools = const [],
    bool supportsFunctionCalls = false,
    gemma.ToolChoice toolChoice = gemma.ToolChoice.auto,
  }) async {
    if (_model == null) {
      throw StateError(
          'GemmaInferenceService not initialized. Call initialize() first.');
    }

    // Close existing chat if any
    await _chat?.close();
    _pendingImages.clear();

    _chat = await _model!.createChat(
      systemInstruction: systemInstruction,
      temperature: temperature,
      randomSeed: randomSeed,
      topK: topK,
      supportImage: supportImage,
      supportAudio: supportAudio,
      isThinking: isThinking,
      tools: tools,
      supportsFunctionCalls: supportsFunctionCalls,
      modelType: modelType,
      toolChoice: toolChoice,
    );
  }

  /// Queue images to be included with the first user message.
  /// Images are accumulated and consumed when addTextQuery() is called.
  Future<void> addImagesToQueue(List<Uint8List> images) async {
    _pendingImages.addAll(images);
  }

  /// Send a text message and get a synchronous response.
  ///
  /// Returns the complete response text.
  Future<String> sendMessage(String message) async {
    if (_chat == null) {
      throw StateError('No active chat. Call createSession() first.');
    }

    await _chat!.addQueryChunk(
      gemma.Message.text(text: message, isUser: true),
    );

    final response = await _chat!.generateChatResponse();

    if (response is gemma.TextResponse) {
      return response.token;
    } else if (response is gemma.ThinkingResponse) {
      return response.content;
    } else if (response is gemma.FunctionCallResponse) {
      return 'Function call: ${response.name}(${response.args})';
    } else if (response is gemma.ParallelFunctionCallResponse) {
      final calls =
          response.calls.map((c) => '${c.name}(${c.args})').join(', ');
      return 'Function calls: $calls';
    }

    return '';
  }

  /// Add a text query chunk to the current session.
  /// If pending images exist, includes the first image with the text,
  /// then adds remaining images as separate queries.
  ///
  /// If [prefix] is true, the message is marked as a prefix for replay
  /// when sessions are recreated (e.g., for material context).
  Future<void> addTextQuery(
    String message, {
    bool noTool = false,
    bool prefix = false,
  }) async {
    if (_chat == null) {
      throw StateError('No active chat. Call createSession() first.');
    }

    // Include all queued images with the first user message.
    if (_pendingImages.isNotEmpty) {
      debugPrint(
          '[Gemma] Including ${_pendingImages.length} images with text message');
      await _chat!.addQueryChunk(
        gemma.Message.withImages(
          text: message,
          imageBytes: List<Uint8List>.from(_pendingImages),
          isUser: true,
        ),
        noTool,
        prefix,
      );
      _pendingImages.clear();
    } else {
      await _chat!.addQueryChunk(
        gemma.Message.text(text: message, isUser: true),
        noTool,
        prefix,
      );
    }
  }

  /// Replay existing chat messages into the active session without generating.
  ///
  /// This is used to rehydrate a session from stored history before the next
  /// live user turn is sent.
  Future<void> replayMessages(List<gemma.Message> messages) async {
    if (_chat == null) {
      throw StateError('No active chat. Call createSession() first.');
    }

    for (final message in messages) {
      await _chat!.addQueryChunk(message);
    }
  }

  /// Add an audio-only query to the current session.
  Future<void> addAudioQuery(Uint8List audioBytes) async {
    if (_chat == null) {
      throw StateError('No active chat. Call createSession() first.');
    }
    await _chat!.addQueryChunk(
      gemma.Message.audioOnly(audioBytes: audioBytes, isUser: true),
    );
  }

  /// Add an image query chunk to the current session.
  /// Images are queued and consumed when addTextQuery() is called.
  Future<void> addImageQuery(Uint8List imageBytes) async {
    if (_chat == null) {
      throw StateError('No active chat. Call createSession() first.');
    }

    await addImagesToQueue([imageBytes]);
  }

  /// Add a tool response to the current session.
  Future<void> addToolResponse({
    required String toolName,
    required Map<String, Object?> response,
  }) async {
    if (_chat == null) {
      throw StateError('No active chat. Call createSession() first.');
    }

    await _chat!.addQueryChunk(
      gemma.Message.toolResponse(
        toolName: toolName,
        response: Map<String, dynamic>.from(response),
      ),
    );
  }

  /// Generate a single response from the current session.
  Future<gemma.ModelResponse> generateResponse() async {
    if (_chat == null) {
      throw StateError('No active chat. Call createSession() first.');
    }
    return _chat!.generateChatResponse();
  }

  /// Generate streaming responses from the current session.
  Stream<gemma.ModelResponse> generateResponses() async* {
    if (_chat == null) {
      throw StateError('No active chat. Call createSession() first.');
    }
    yield* _chat!.generateChatResponseAsync();
  }

  /// Send a multimodal message with image and get a synchronous response.
  Future<String> sendMessageWithImage(
    String message,
    Uint8List imageBytes, {
    bool imageOnly = false,
  }) async {
    if (_chat == null) {
      throw StateError('No active chat. Call createSession() first.');
    }

    if (imageOnly) {
      await _chat!.addQueryChunk(
        gemma.Message.imageOnly(imageBytes: imageBytes, isUser: true),
      );
    } else {
      await _chat!.addQueryChunk(
        gemma.Message.withImage(
          text: message,
          imageBytes: imageBytes,
          isUser: true,
        ),
      );
    }

    final response = await _chat!.generateChatResponse();

    if (response is gemma.TextResponse) {
      return response.token;
    }

    return '';
  }

  /// Send a message and get a streaming response.
  ///
  /// Returns a stream of response tokens/text chunks.
  Stream<String> sendMessageStreaming(String message) async* {
    if (_chat == null) {
      throw StateError('No active chat. Call createSession() first.');
    }

    await _chat!.addQueryChunk(
      gemma.Message.text(text: message, isUser: true),
    );

    await for (final response in _chat!.generateChatResponseAsync()) {
      if (response is gemma.TextResponse) {
        yield response.token;
      } else if (response is gemma.ThinkingResponse) {
        yield response.content;
      }
    }
  }

  /// Close the chat and release resources.
  Future<void> closeSession() async {
    await _chat?.close();
    _chat = null;
    _pendingImages.clear();
  }

  /// Release chat resources owned by this service.
  ///
  /// The active Gemma model stays app-scoped. Feature owners should dispose
  /// their own service instance, but the shared model remains available.
  Future<void> dispose() async {
    await closeSession();
  }
}
