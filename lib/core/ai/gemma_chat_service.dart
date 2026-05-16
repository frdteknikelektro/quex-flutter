import 'dart:async';
import 'dart:math';

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

abstract class QuizChatService {
  bool get isInitialized;

  Future<void> initialize({
    int maxTokens = 8192,
    gemma.PreferredBackend? preferredBackend,
    int? maxNumImages,
    bool? enableSpeculativeDecoding,
  });

  Future<void> createSession({
    String? systemInstruction,
    double temperature = 1.0,
    double topP = 0.95,
    int topK = 64,
    bool isThinking = false,
    List<gemma.Tool> tools = const [],
    ToolExecutor? toolExecutor,
  });

  Stream<({String? text, String? thinking})> sendMessage(String message);

  Stream<({String? text, String? thinking})> sendMessageWithImages(
    String message,
    List<Uint8List> images,
  );
}

/// Simple chat service wrapping flutter_gemma's InferenceChat.
///
/// Supports text chat with support for images, audio, streaming, and thinking mode.
class GemmaChatService implements QuizChatService {
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

  @visibleForTesting
  Stream<({String? text, String? thinking})> processResponseStream(
    Stream<gemma.ModelResponse> stream,
  ) =>
      _processResponseStream(stream);

  @override
  bool get isInitialized => _model != null;

  bool get hasActiveSession => _chat != null;

  /// The effective max tokens used by the model after applying upper bound.
  /// Available after initialize() is called successfully.
  int? get effectiveMaxTokens => _effectiveMaxTokens;

  static const int _defaultMaxTokens = 8192;

  /// Initialize the service by creating the model.
  /// Only needed if no model was provided in the constructor.
  /// [maxTokens] is capped by the calculated upper bound based on device RAM.
  @override
  Future<void> initialize({
    int maxTokens = 8192,
    gemma.PreferredBackend? preferredBackend = gemma.PreferredBackend.gpu,
    int? maxNumImages = 16,
    bool? enableSpeculativeDecoding = true,
  }) async {
    if (_model != null) return;

    await ModelManager.activateModel();

    final effectiveMaxTokens = await GemmaConfigService.applyUpperBound(
      maxTokens,
      defaultValue: _defaultMaxTokens,
    );
    _effectiveMaxTokens = effectiveMaxTokens;

    _model = await ModelManager.getModel(
      maxTokens: effectiveMaxTokens,
      preferredBackend: preferredBackend,
      maxNumImages: maxNumImages,
      enableSpeculativeDecoding: enableSpeculativeDecoding,
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
  @override
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
        maxFunctionBufferLength: 2048,
        randomSeed: Random().nextInt(1000000));
  }

  /// Send a text message and get streaming response.
  ///
  /// Yields events: (text: String?, thinking: String?)
  /// - text: reply token (null if just thinking)
  /// - thinking: thinking token when in thinking mode (null for regular text)
  @override
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

  /// Append an assistant/context turn without requesting a model reply.
  Future<void> addAssistantContext(String message) async {
    if (_chat == null) {
      throw StateError('No active session. Call createSession() first.');
    }

    await _chat!.addQueryChunk(
      gemma.Message.text(text: message, isUser: false),
    );
  }

  /// Process response stream handling tool calls in a multi-turn loop.
  Stream<({String? text, String? thinking})> _processResponseStream(
    Stream<gemma.ModelResponse> stream,
  ) async* {
    final toolCalls = <({String name, Map<String, Object?> args})>[];
    var gotToolCall = false;

    // Track processed calls to avoid duplicates if library yields them at end of stream.
    // This is especially important for Gemma 4 where we manually scan the text stream.
    final processedCalls = <String>{};
    String funcBuffer = '';
    bool inThinkingChannel = false;

    await for (final response in stream) {
      if (response is gemma.TextResponse) {
        String token = response.token;

        // 1. Handle Channel Tags (Native thinking markers in Gemma 4)
        if (token.contains('<|channel')) {
          inThinkingChannel = true;
          // Extract any text before the tag and yield it
          final tagIndex = token.indexOf('<|channel');
          if (tagIndex > 0) {
            yield (text: token.substring(0, tagIndex), thinking: null);
          }

          // Check if the tag is complete in this token
          if (token.contains('<channel|>')) {
            const startMarker = 'thought\n';
            final startIdx = token.indexOf(startMarker);
            final endIdx = token.indexOf('<channel|>');

            if (startIdx != -1 && endIdx > startIdx) {
              final thought =
                  token.substring(startIdx + startMarker.length, endIdx);
              if (thought.isNotEmpty) yield (text: null, thinking: thought);
            }
            inThinkingChannel = false;

            final remaining = token.substring(endIdx + '<channel|>'.length);
            if (remaining.isEmpty) continue;
            token = remaining; // Continue processing the rest of the token
          } else {
            // Started but not ended in this token
            const startMarker = 'thought\n';
            final startIdx = token.indexOf(startMarker);
            if (startIdx != -1) {
              final thought = token.substring(startIdx + startMarker.length);
              if (thought.isNotEmpty) yield (text: null, thinking: thought);
            }
            continue;
          }
        } else if (inThinkingChannel) {
          if (token.contains('<channel|>')) {
            final parts = token.split('<channel|>');
            if (parts[0].isNotEmpty) yield (text: null, thinking: parts[0]);
            inThinkingChannel = false;
            if (parts[1].isEmpty) continue;
            token = parts[1];
          } else {
            yield (text: null, thinking: token);
            continue;
          }
        }

        // 2. Handle Function Calls (JSON tool calling)
        if (funcBuffer.isEmpty) {
          // Detect start of a function call (JSON block).
          if (gemma.FunctionCallParser.isFunctionCallStart(token)) {
            funcBuffer = token;
            continue;
          } else {
            yield (text: token, thinking: null);
          }
        } else {
          funcBuffer += token;
          // Check if the buffered block is now a complete tool call.
          if (gemma.FunctionCallParser.isFunctionCallComplete(funcBuffer)) {
            final calls = gemma.FunctionCallParser.parseAll(funcBuffer);
            for (final call in calls) {
              final key = '${call.name}:${call.args}';
              if (processedCalls.add(key)) {
                gotToolCall = true;
                toolCalls.add((name: call.name, args: call.args));
              }
            }
            funcBuffer = '';
          }
          continue;
        }
      } else if (response is gemma.ThinkingResponse) {
        yield (text: null, thinking: response.content);
      } else if (response is gemma.FunctionCallResponse) {
        final key = '${response.name}:${response.args}';
        if (processedCalls.add(key)) {
          gotToolCall = true;
          toolCalls.add((name: response.name, args: response.args));
        }
      } else if (response is gemma.ParallelFunctionCallResponse) {
        for (final call in response.calls) {
          final key = '${call.name}:${call.args}';
          if (processedCalls.add(key)) {
            gotToolCall = true;
            toolCalls.add((name: call.name, args: call.args));
          }
        }
      }
    }

    // If stream ended without a complete tool call, flush the buffer to UI.
    if (funcBuffer.isNotEmpty && !gotToolCall) {
      yield (text: funcBuffer, thinking: null);
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
  @override
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
