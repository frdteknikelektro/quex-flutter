import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart' as gemma;

import 'gemma_config_service.dart';
import 'model_manager.dart';

/// Tool execution callback for function calling.
/// Returns the tool response as a map.
typedef ToolExecutor = Future<Map<String, Object?>> Function(
  String toolName,
  Map<String, Object?> args,
);

/// Simple chat service wrapping flutter_gemma's InferenceChat.
///
/// Much leaner than GemmaSessionService - no tutor/coach logic,
/// just text chat with support for images, audio, streaming, and thinking mode.
class GemmaChatService {
  static GemmaChatService? _instance;

  gemma.InferenceModel? _model;
  gemma.InferenceChat? _chat;
  ToolExecutor? _toolExecutor;
  int? _effectiveMaxTokens;

  /// Factory constructor returns singleton instance.
  factory GemmaChatService() => _instance ??= GemmaChatService._internal();

  /// Explicit singleton access.
  static GemmaChatService getInstance() => GemmaChatService();

  GemmaChatService._internal();

  bool get isInitialized => _model != null;

  bool get hasActiveSession => _chat != null;

  /// The effective max tokens used by the model after applying upper bound.
  /// Available after initialize() is called successfully.
  int? get effectiveMaxTokens => _effectiveMaxTokens;

  static const int _defaultMaxTokens = 8192;

  /// Initialize the service by creating the model.
  /// Only needed if no model was provided in the constructor.
  /// [maxTokens] is capped by the calculated upper bound based on device RAM.
  Future<void> initialize({int? maxTokens}) async {
    if (_model != null) return;

    await ModelManager.activateModel();

    final effectiveMaxTokens = await GemmaConfigService.applyUpperBound(
      maxTokens,
      defaultValue: _defaultMaxTokens,
    );
    _effectiveMaxTokens = effectiveMaxTokens;

    _model = await gemma.FlutterGemma.getActiveModel(
      maxTokens: effectiveMaxTokens,
      preferredBackend: gemma.PreferredBackend.cpu,
      supportImage: true,
      supportAudio: true,
      maxNumImages: 32,
    );
  }

  /// Create a new chat session.
  ///
  /// [systemInstruction] - Optional system prompt
  /// [temperature] - Sampling temperature (0.0-1.0)
  /// [topP] - Nucleus sampling (0.0-1.0)
  /// [topK] - Top-K sampling
  /// [isThinking] - Enable thinking mode for reasoning
  /// [tools] - List of available tools for function calling
  /// [toolExecutor] - Callback to execute tool calls
  Future<void> createSession({
    String? systemInstruction,
    double temperature = 1.0,
    double topP = 0.95,
    int topK = 64,
    bool isThinking = false,
    List<gemma.Tool> tools = const [],
    ToolExecutor? toolExecutor,
  }) async {
    if (_model == null) {
      throw StateError('Service not initialized. Call initialize() first.');
    }

    await _chat?.close();
    _chat = null;
    _toolExecutor = toolExecutor;

    _chat = await _model!.createChat(
      systemInstruction: systemInstruction,
      temperature: temperature,
      topP: topP,
      topK: topK,
      supportImage: true,
      supportAudio: true,
      isThinking: isThinking,
      toolChoice:
          tools.isNotEmpty ? gemma.ToolChoice.auto : gemma.ToolChoice.none,
      tools: tools,
      supportsFunctionCalls: tools.isNotEmpty,
    );
  }

  /// Send a text message and get streaming response.
  ///
  /// Yields events: (text: String?, thinking: String?)
  /// - text: reply token (null if just thinking)
  /// - thinking: thinking token when in thinking mode (null for regular text)
  Stream<({String? text, String? thinking})> sendMessage(
      String message) async* {
    if (_chat == null) {
      throw StateError('No active session. Call createSession() first.');
    }

    await _chat!.addQueryChunk(
      gemma.Message.text(text: message, isUser: true),
    );

    await for (final response
        in _processResponseStream(_chat!.generateChatResponseAsync())) {
      yield response;
    }
  }

  /// Process response stream handling tool calls in a multi-turn loop.
  Stream<({String? text, String? thinking})> _processResponseStream(
    Stream<gemma.ModelResponse> stream,
  ) async* {
    final toolCalls = <({String name, Map<String, Object?> args})>[];
    var gotToolCall = false;

    await for (final response in stream) {
      switch (response) {
        case gemma.TextResponse(:final token):
          yield (text: token, thinking: null);
        case gemma.ThinkingResponse(:final content):
          yield (text: null, thinking: content);
        case gemma.FunctionCallResponse(:final name, :final args):
          gotToolCall = true;
          toolCalls.add((name: name, args: args));
        case gemma.ParallelFunctionCallResponse(:final calls):
          gotToolCall = true;
          for (final call in calls) {
            toolCalls.add((name: call.name, args: call.args));
          }
      }
    }

    // Handle tool calls if any
    if (gotToolCall && _toolExecutor != null && _chat != null) {
      // Execute all tool calls
      for (final call in toolCalls) {
        final result = await _toolExecutor!(call.name, call.args);

        // Send tool response back to model
        await _chat!.addQueryChunk(
          gemma.Message.toolResponse(
            toolName: call.name,
            response: result,
          ),
        );
      }

      // Continue generation after tool responses
      await for (final response
          in _processResponseStream(_chat!.generateChatResponseAsync())) {
        yield response;
      }
    }
  }

  /// Send a message with images and get streaming response.
  ///
  /// Images are sent together with text in a single message chunk.
  Stream<({String? text, String? thinking})> sendMessageWithImages(
    String message,
    List<Uint8List> images,
  ) async* {
    if (_chat == null) {
      throw StateError('No active session. Call createSession() first.');
    }

    // Send text and all images in a SINGLE message chunk.
    // This is required for the FFI path which only buffers one pending image.
    await _chat!.addQueryChunk(
      gemma.Message.withImages(
        text: message,
        imageBytes: images,
        isUser: true,
      ),
    );

    await for (final response
        in _processResponseStream(_chat!.generateChatResponseAsync())) {
      yield response;
    }
  }

  /// Send an audio message and get streaming response.
  ///
  /// Audio must be WAV 16kHz mono 16-bit.
  Stream<({String? text, String? thinking})> sendAudioMessage(
    Uint8List audioBytes,
  ) async* {
    if (_chat == null) {
      throw StateError('No active session. Call createSession() first.');
    }

    await _chat!.addQueryChunk(
      gemma.Message.audioOnly(audioBytes: audioBytes, isUser: true),
    );

    await for (final response
        in _processResponseStream(_chat!.generateChatResponseAsync())) {
      yield response;
    }
  }

  /// Stop ongoing generation.
  Future<void> stopGeneration() async {
    await _chat?.stopGeneration();
  }

  /// Close the current session.
  Future<void> closeSession() async {
    await _chat?.close();
    _chat = null;
  }

  /// Get session metrics from the current chat session.
  /// Returns null if no session exists or metrics are unavailable.
  /// Note: Metrics are only available on FFI/.litertlm platforms.
  ///       MediaPipe platforms return zeroed metrics.
  /// Uses dynamic to avoid compilation errors with older flutter_gemma versions.
  dynamic getSessionMetrics() {
    try {
      final session = _chat?.session;
      debugPrint(
          'GemmaChatService.getSessionMetrics: _chat=$_chat, session=$session');
      if (session == null) return null;
      // Use dynamic to call getSessionMetrics which may not be available in all versions
      final dynamic dynamicSession = session;
      final metrics = dynamicSession.getSessionMetrics();
      debugPrint('GemmaChatService.getSessionMetrics: metrics=$metrics');
      return metrics;
    } catch (e) {
      debugPrint('SessionMetrics not available: $e');
      return null;
    }
  }

  /// Dispose the service and release resources.
  /// Note: Does NOT close the model - the caller owns it.
  Future<void> dispose() async {
    await closeSession();
  }
}
