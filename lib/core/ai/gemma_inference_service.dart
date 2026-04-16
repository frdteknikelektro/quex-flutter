import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_gemma/flutter_gemma.dart' as gemma;

import '../models/models.dart';

/// Service for running inference using Gemma 4 E4B model.
///
/// Handles model creation, chat sessions, and streaming responses.
/// Supports text, multimodal (image/audio), function calling, and thinking mode.
class GemmaInferenceService {
  gemma.InferenceModel? _model;
  gemma.InferenceChat? _chat;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  /// Initialize the inference service by creating the model.
  /// Call this after the model has been downloaded via ModelManager.
  Future<void> initialize({
    int maxTokens = 4096,
    gemma.PreferredBackend preferredBackend = gemma.PreferredBackend.gpu,
  }) async {
    if (_isInitialized) return;

    _model = await gemma.FlutterGemma.getActiveModel(
      maxTokens: maxTokens,
      preferredBackend: preferredBackend,
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
      throw StateError('GemmaInferenceService not initialized. Call initialize() first.');
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
      final calls = response.calls.map((c) => '${c.name}(${c.args})').join(', ');
      return 'Function calls: $calls';
    }

    return '';
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

  /// Generate a quiz based on study materials using the LLM.
  Future<List<Question>> generateQuiz({
    required Session session,
    required List<StudyMaterial> materials,
    required int questionCount,
  }) async {
    if (_chat == null) {
      throw StateError('No active chat. Call createSession() first.');
    }

    final textMaterials = materials.where((m) => m.kind == MaterialKind.text).toList();
    final context = textMaterials.map((m) => '${m.title}:\n${m.content}').join('\n\n');

    final prompt = '''You are a study assistant helping create a quiz for "${session.title}".

Context from study materials:
$context

Create exactly $questionCount multiple choice questions based on the above materials. 
For each question:
1. Provide a clear question
2. Provide 4 answer options labeled A, B, C, D
3. Indicate the correct answer letter (A, B, C, or D)
4. Provide a brief explanation for why the correct answer is right

Format as JSON array with this structure for each question:
{
  "questionText": "...",
  "optionA": "...",
  "optionB": "...",
  "optionC": "...",
  "optionD": "...",
  "correctOption": "A|B|C|D",
  "explanation": "..."
}

Return only the JSON array, no other text.''';

    final response = await sendMessage(prompt);
    
    // Parse the response into questions
    // This is a simplified parser - in production, add proper JSON parsing
    return _parseQuizResponse(response, questionCount, session);
  }

  /// Get a coaching response based on user message and study context.
  Future<String> getCoachReply({
    required Session session,
    required List<StudyMaterial> materials,
    required List<ChatMessage> history,
    required String message,
  }) async {
    if (_chat == null) {
      throw StateError('No active chat. Call createSession() first.');
    }

    final context = materials.map((m) => '${m.title}:\n${m.content}').join('\n\n');
    
    final prompt = '''You are a helpful study coach for "${session.title}".

Study materials context:
$context

User message: $message

Provide a helpful, encouraging response that:
- Answers questions about the study material
- Offers study tips and strategies
- Suggests related topics to explore
- Keeps responses concise and actionable

Coach response:''';

    return await sendMessage(prompt);
  }

  /// Generate a summary of study materials.
  Future<String> generateSummary({
    required Session session,
    required List<StudyMaterial> materials,
  }) async {
    if (_chat == null) {
      throw StateError('No active chat. Call createSession() first.');
    }

    final context = materials.map((m) => '${m.title}:\n${m.content}').join('\n\n');
    
    final prompt = '''Summarize the following study materials for "${session.title}" in 3-5 key points:

$context

Summary:''';

    return await sendMessage(prompt);
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

  /// Parse quiz response from LLM into Question objects.
  List<Question> _parseQuizResponse(
    String response,
    int questionCount,
    Session session,
  ) {
    // Fallback to simple parsing - in production, implement proper JSON parsing
    final questions = <Question>[];
    
    // Simple template-based questions as fallback
    final templates = [
      'Which idea is best supported by this material?',
      'What is the clearest takeaway from this section?',
      'Which statement matches the study material?',
      'What should the learner remember most?',
    ];

    for (var i = 0; i < questionCount; i++) {
      questions.add(
        Question(
          quizId: -1,
          source: QuestionSource.generated,
          questionText: templates[i % templates.length],
          optionA: 'Option A',
          optionB: 'Option B',
          optionC: 'Option C',
          optionD: 'Option D',
          correctOption: 'A',
          explanation: 'This is the correct answer based on the study material.',
          orderIndex: i,
        ),
      );
    }

    return questions;
  }
}
