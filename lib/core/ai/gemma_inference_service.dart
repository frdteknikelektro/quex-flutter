import 'dart:async';
import 'dart:typed_data';

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

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  /// True if active chat session exists.
  bool get hasActiveSession => _chat != null;

  static const int _maxOutputTokens = 8192;

  /// Initialize the inference service by creating the model.
  /// Call this after the model has been downloaded via ModelManager.
  Future<void> initialize({
    int maxTokens = _maxOutputTokens,
    gemma.PreferredBackend preferredBackend = gemma.PreferredBackend.gpu,
  }) async {
    if (_isInitialized) return;

    _model = await gemma.FlutterGemma.getActiveModel(
      maxTokens: maxTokens,
      preferredBackend: preferredBackend,
      supportImage: true,
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
    bool supportImage = false,
    bool isThinking = false,
    List<gemma.Tool> tools = const [],
    bool supportsFunctionCalls = false,
  }) async {
    if (_model == null) {
      throw StateError(
          'GemmaInferenceService not initialized. Call initialize() first.');
    }

    // Close existing chat if any
    await _chat?.close();

    _chat = await _model!.createChat(
      systemInstruction: systemInstruction,
      temperature: temperature,
      randomSeed: randomSeed,
      topK: topK,
      supportImage: supportImage,
      isThinking: isThinking,
      tools: tools,
      supportsFunctionCalls: supportsFunctionCalls,
      modelType: gemma.ModelType.gemmaIt,
    );
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
  Future<void> addTextQuery(
    String message, {
    bool noTool = false,
  }) async {
    if (_chat == null) {
      throw StateError('No active chat. Call createSession() first.');
    }

    await _chat!.addQueryChunk(
      gemma.Message.text(text: message, isUser: true),
      noTool,
    );
  }

  /// Add an image query chunk to the current session.
  Future<void> addImageQuery(Uint8List imageBytes) async {
    if (_chat == null) {
      throw StateError('No active chat. Call createSession() first.');
    }

    await _chat!.addQueryChunk(
      gemma.Message.imageOnly(imageBytes: imageBytes, isUser: true),
    );
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
  }

  /// Close the model and release all resources.
  Future<void> dispose() async {
    await closeSession();
    await _model?.close();
    _model = null;
    _isInitialized = false;
  }
}
