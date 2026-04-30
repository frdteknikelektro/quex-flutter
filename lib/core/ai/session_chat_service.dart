import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'chat_prompts.dart';
import 'gemma_chat_service.dart';
import 'material_preprocessor.dart';

/// Study coach specific chat service.
///
/// Encapsulates all chat logic for the session/coach screen including:
/// - Coach system prompts from [ChatPrompts]
/// - Materials context preparation
/// - Session lifecycle (create, reset, close)
/// - High-level chat operations (opener, text, images, audio)
class SessionChatService {
  final GemmaChatService _chatService = GemmaChatService.getInstance();
  bool _sessionCreated = false;
  final List<Uint8List> _materialImages = [];

  bool get isInitialized => _chatService.isInitialized;
  bool get hasSession => _sessionCreated;

  /// The effective max tokens used by the model after applying upper bound.
  /// Available after initialize() is called successfully.
  int? get effectiveMaxTokens => _chatService.effectiveMaxTokens;

  /// Initialize the underlying chat service.
  Future<void> initialize() => _chatService.initialize();

  /// Create coach session with materials context.
  Future<void> createSession({
    required Session session,
    required List<StudyMaterial> materials,
    String locale = 'en',
    bool isThinking = false,
  }) async {
    final prepared = await MaterialPreprocessor.prepare(materials);

    final textContext = prepared
        .where((p) => p.textChunk.isNotEmpty)
        .map((p) => p.textChunk)
        .join('\n\n');

    // Collect images from photo materials
    _materialImages.clear();
    _materialImages.addAll(prepared.expand((p) => p.images));
    debugPrint(
        '[SessionChatService] createSession: collected ${_materialImages.length} images from materials');

    final systemInstruction = StringBuffer(
      ChatPrompts.getCoachSystemInstruction(session.title, locale),
    );
    if (textContext.isNotEmpty) {
      systemInstruction
        ..writeln('\n\n--- STUDY MATERIALS ---')
        ..write(textContext);
    }

    await _chatService.createSession(
      systemInstruction: systemInstruction.toString(),
      temperature: 1.1,
      isThinking: isThinking,
    );
    _sessionCreated = true;
  }

  /// Send the opener/greeting message. Returns stream of response tokens.
  /// [images] - Optional additional images to include with the opener message.
  /// Material images collected during createSession are automatically included.
  Stream<({String? text, String? thinking})> sendOpener(
    String locale, {
    List<Uint8List> images = const [],
  }) {
    // Combine material images with any additional images
    final allImages = <Uint8List>[..._materialImages, ...images];
    final openerMessage = ChatPrompts.getCoachOpenerMessage(locale);
    if (allImages.isNotEmpty) {
      return _chatService.sendMessageWithImages(openerMessage, allImages);
    }
    return _chatService.sendMessage(openerMessage);
  }

  /// Send user text message with optional images. Returns stream of response tokens.
  Stream<({String? text, String? thinking})> sendUserMessage(
    String message, {
    List<Uint8List> images = const [],
  }) {
    if (images.isNotEmpty) {
      return _chatService.sendMessageWithImages(message, images);
    }
    return _chatService.sendMessage(message);
  }

  /// Send user audio message. Returns stream of response tokens.
  Stream<({String? text, String? thinking})> sendUserAudio(Uint8List audioBytes) {
    return _chatService.sendAudioMessage(audioBytes);
  }

  /// Stop ongoing generation.
  Future<void> stopGeneration() => _chatService.stopGeneration();

  /// Reset the session (close and clear state).
  Future<void> resetSession() async {
    await _chatService.closeSession();
    _sessionCreated = false;
    _materialImages.clear();
  }

  /// Dispose and close session.
  Future<void> dispose() async {
    await _chatService.closeSession();
    _sessionCreated = false;
    _materialImages.clear();
  }

  /// Get session metrics from the current chat session.
  /// Returns null if no session exists.
  /// Note: Metrics are only available on FFI/.litertlm platforms.
  /// Uses dynamic to avoid compilation errors with older flutter_gemma versions.
  dynamic getSessionMetrics() {
    return _chatService.getSessionMetrics();
  }
}
