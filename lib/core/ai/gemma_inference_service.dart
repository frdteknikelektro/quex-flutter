import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_gemma/flutter_gemma.dart' as gemma;

import '../models/models.dart';
import 'material_preprocessor.dart';
import 'quiz_generation_event.dart';
import 'tutor_event.dart';

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
    int maxTokens = _maxOutputTokens,
    gemma.PreferredBackend preferredBackend = gemma.PreferredBackend.gpu,
  }) async {
    if (_isInitialized) return;

    _model = await gemma.FlutterGemma.getActiveModel(
      maxTokens: maxTokens,
      preferredBackend: preferredBackend,
      supportImage: true,
      maxNumImages: MaterialPreprocessor.totalImageCap,
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

  /// Scan materials for existing quiz questions.
  /// Returns verbatim question texts found, or empty list if none detected.
  Future<List<String>> detectQuestionsInMaterials({
    required List<StudyMaterial> materials,
  }) async {
    if (!_isInitialized) throw StateError('Service not initialized');

    final prepared = await MaterialPreprocessor.prepare(materials);
    final hasImages = prepared.any((p) => p.images.isNotEmpty);
    final textContext = prepared
        .map((p) => p.textChunk)
        .where((t) => t.isNotEmpty)
        .join('\n\n');

    const systemInstruction =
        'You are a question extractor. Scan the study materials provided. '
        'If there are quiz questions already written in them, list each one EXACTLY as written, '
        'one per line, with no extra text or numbering. '
        'If there are no questions in the materials, respond with exactly: NONE';

    await createSession(
      systemInstruction: systemInstruction,
      temperature: 0.1,
      topK: 1,
      supportImage: hasImages,
    );

    final prompt = 'Extract all quiz questions from these materials. '
        'One per line, or NONE if none exist.\n\n$textContext';

    await _chat!.addQueryChunk(gemma.Message.text(text: prompt, isUser: true));

    for (final prep in prepared) {
      for (final imgBytes in prep.images) {
        await _chat!.addQueryChunk(
          gemma.Message.imageOnly(imageBytes: imgBytes, isUser: true),
        );
      }
    }

    final response = await _chat!.generateChatResponse();
    final raw = response is gemma.TextResponse ? response.token : '';

    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed.toUpperCase() == 'NONE') return [];

    return trimmed
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && line.toUpperCase() != 'NONE')
        .toList();
  }

  static const _questionTool = gemma.Tool(
    name: 'generate_question',
    description: 'Submit one quiz question. You must call this once per question.',
    parameters: {
      'type': 'object',
      'properties': {
        'type': {
          'type': 'string',
          'enum': ['multipleChoice', 'textAnswer'],
        },
        'questionText': {'type': 'string'},
        'options': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': 'Required for multipleChoice (3-4 items). Omit for textAnswer.',
        },
      },
      'required': ['type', 'questionText'],
    },
  );

  static const int _maxOutputTokens = 8192;

  /// Generate a quiz one question at a time via multi-turn tool calling.
  /// Calls generate_question once per question, yielding progress events.
  /// Retries up to 2 times per question before emitting QuizGenerationError.
  Stream<QuizGenerationEvent> generateQuizStreaming({
    required Session session,
    required List<StudyMaterial> materials,
    int questionCount = 10,
  }) async* {
    if (!_isInitialized) {
      throw StateError('Service not initialized');
    }

    final prepared = await MaterialPreprocessor.prepare(materials);
    final hasImages = prepared.any((p) => p.images.isNotEmpty);

    const systemInstruction =
        'You are a quiz generator for elementary students. '
        'You MUST call generate_question exactly once per question — no plain text answers. '
        'Each call submits exactly one question. '
        'Use multipleChoice for factual recall (3-4 options). '
        'Use textAnswer for definitions or short answers. '
        'Match difficulty to the student grade level.';

    await createSession(
      systemInstruction: systemInstruction,
      isThinking: false,
      tools: [_questionTool],
      supportsFunctionCalls: true,
      supportImage: hasImages,
    );

    yield QuizGenerationStarted(questionCount);

    final textContext = prepared
        .map((p) => p.textChunk)
        .where((t) => t.isNotEmpty)
        .join('\n\n');

    final initialPrompt =
        'Generate exactly $questionCount quiz questions for "${session.title}" '
        '(Grade ${session.gradeOverride}) based on the study materials below. '
        'Call generate_question once per question. '
        '${hasImages ? 'Images of the materials follow. ' : ''}'
        'Start now: call generate_question for question 1 of $questionCount.\n\n'
        '$textContext';

    await _chat!.addQueryChunk(gemma.Message.text(text: initialPrompt, isUser: true));

    for (final prep in prepared) {
      for (final imgBytes in prep.images) {
        await _chat!.addQueryChunk(
          gemma.Message.imageOnly(imageBytes: imgBytes, isUser: true),
        );
      }
    }

    final questions = <Question>[];

    for (var i = 1; i <= questionCount; i++) {
      Question? parsed;
      var retries = 0;

      while (parsed == null && retries < 2) {
        var gotCall = false;

        try {
          await for (final response in _chat!.generateChatResponseAsync()) {
            if (response is gemma.ThinkingResponse) {
              yield QuizThinkingToken(response.content);
            } else if (response is gemma.TextResponse) {
              yield QuizTextToken(response.token);
            } else if (response is gemma.FunctionCallResponse) {
              gotCall = true;
              parsed = _parseToolCallQuestion(response.args, orderIndex: i - 1);
              if (parsed == null) retries++;
            }
          }
        } catch (e) {
          print('Turn $i error during generation: $e');
          retries++;
        }

        if (!gotCall) retries++;

        if (parsed == null && retries < 2) {
          final prompt = 'Please call generate_question for question $i of $questionCount now.';
          print('Turn $i retry #$retries: $prompt');
          await _chat!.addQueryChunk(gemma.Message.text(
            text: prompt,
            isUser: true,
          ));
        }
      }

      if (parsed == null) {
        // Try continuation prompt with full explicit structure
        if (retries < 2 && i == questionCount - 1) {
          // Last question: be very explicit
          await _chat!.addQueryChunk(gemma.Message.text(
            text: 'Last question: Call generate_question for question $questionCount of $questionCount. '
                'This is the final question.',
            isUser: true,
          ));
          // One more attempt
          await for (final response in _chat!.generateChatResponseAsync()) {
            if (response is gemma.FunctionCallResponse) {
              parsed = _parseToolCallQuestion(response.args, orderIndex: questionCount - 1);
              break;
            }
          }
          if (parsed != null) {
            questions.add(parsed);
            yield QuizQuestionGenerated(parsed, questionCount, questionCount);
            yield QuizGenerationComplete(questions);
            return;
          }
        }

        yield QuizGenerationError('Failed to generate question $i after retries');
        return;
      }

      questions.add(parsed);
      yield QuizQuestionGenerated(parsed, i, questionCount);

      if (i < questionCount) {
        await _chat!.addQueryChunk(gemma.Message.text(
          text: 'Question $i of $questionCount recorded. '
              'Now generate question ${i + 1} of $questionCount using the tool. '
              'Call generate_question immediately.',
          isUser: true,
        ));
      }
    }

    yield QuizGenerationComplete(questions);
  }

  Question? _parseToolCallQuestion(
    Map<String, dynamic> args, {
    required int orderIndex,
  }) {
    try {
      final typeStr = args['type'] as String? ?? 'multipleChoice';
      final type =
          typeStr == 'textAnswer' ? QuestionType.textAnswer : QuestionType.multipleChoice;
      final options = (args['options'] as List<dynamic>?)?.cast<String>() ?? [];

      if (type == QuestionType.multipleChoice && options.length < 2) return null;

      final questionText = args['questionText'] as String?;
      if (questionText == null) return null;

      return Question(
        quizId: -1,
        source: QuestionSource.generated,
        type: type,
        questionText: questionText,
        options: type == QuestionType.multipleChoice ? options : [],
        orderIndex: orderIndex,
      );
    } catch (_) {
      return null;
    }
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

  /// Get a tutoring reply for a specific quiz question.
  /// Creates a fresh session focused on question + study materials context.
  Future<String> getQuestionTutorReply({
    required Question question,
    required List<StudyMaterial> materials,
    required List<QuestionMessage> history,
    required String userMessage,
  }) async {
    final optionsText = question.type == QuestionType.multipleChoice
        ? question.options.asMap().entries
            .map((e) => '${String.fromCharCode(65 + e.key)}) ${e.value}')
            .join('\n')
        : '';

    final materialsContext = materials
        .map((m) => '${m.title}:\n${m.content}')
        .join('\n\n');

    final historyText = history.map((m) {
      final role = m.role == QuestionMessageRole.user ? 'Student' : 'Tutor';
      return '$role: ${m.content}';
    }).join('\n');

    const systemInstruction =
        'You are a friendly tutor helping an elementary student answer a quiz question. '
        'Guide them with hints and encouragement — do NOT reveal the answer directly until '
        'they demonstrate understanding. Keep responses short and simple.';

    await createSession(systemInstruction: systemInstruction, temperature: 0.7);

    final prompt = '${materialsContext.isNotEmpty ? 'Study materials:\n$materialsContext\n\n' : ''}'
        'Question: ${question.questionText}\n'
        '${optionsText.isNotEmpty ? 'Options:\n$optionsText\n\n' : ''}'
        '${historyText.isNotEmpty ? 'Conversation so far:\n$historyText\n\n' : ''}'
        'Student: $userMessage\n\nTutor:';

    return await sendMessage(prompt);
  }

  /// Streaming tutoring reply with thinking mode and multimodal image support.
  ///
  /// Context separation: stable context (question + materials) goes into the
  /// system instruction; the user turn carries only conversation history +
  /// the student's new message. Yields [TutorEvent] — either [TutorThinking]
  /// or [TutorReply] tokens so the UI can display them distinctly.
  Stream<TutorEvent> getQuestionTutorReplyStreaming({
    required Question question,
    required List<StudyMaterial> materials,
    required List<QuestionMessage> history,
    required String userMessage,
  }) async* {
    final prepared = await MaterialPreprocessor.prepare(materials);
    final hasImages = prepared.any((p) => p.images.isNotEmpty);

    final optionsText = question.type == QuestionType.multipleChoice
        ? question.options.asMap().entries
            .map((e) => '${String.fromCharCode(65 + e.key)}) ${e.value}')
            .join('\n')
        : '';

    // Text chunks only (photo paths → title label; actual images sent as chunks)
    final materialsContext = prepared
        .where((p) => p.textChunk.isNotEmpty)
        .map((p) => p.textChunk)
        .join('\n\n');

    // System instruction = stable context: role + question + materials
    final systemInstruction = StringBuffer(
      'You are a friendly tutor helping an elementary student answer a quiz question. '
      'Guide them with hints and encouragement — do NOT reveal the answer directly until '
      'they demonstrate understanding. Keep responses short and simple.\n\n'
      '--- QUIZ QUESTION ---\n'
      'Question: ${question.questionText}\n',
    );
    if (optionsText.isNotEmpty) {
      systemInstruction.writeln('Options:\n$optionsText');
    }
    if (materialsContext.isNotEmpty) {
      systemInstruction
        ..writeln()
        ..writeln('--- STUDY MATERIALS ---')
        ..write(materialsContext);
    }

    await createSession(
      systemInstruction: systemInstruction.toString(),
      temperature: 0.7,
      supportImage: hasImages,
      isThinking: false,
    );

    // Send images first (visual context)
    for (final p in prepared) {
      for (final imageBytes in p.images) {
        await _chat!.addQueryChunk(
          gemma.Message.imageOnly(imageBytes: imageBytes, isUser: true),
        );
      }
    }

    // User turn = conversation history + new student message only
    final historyText = history.map((m) {
      final role = m.role == QuestionMessageRole.user ? 'Student' : 'Tutor';
      return '$role: ${m.content}';
    }).join('\n');

    final userTurn = '${historyText.isNotEmpty ? '$historyText\n\n' : ''}'
        'Student: $userMessage';

    await _chat!.addQueryChunk(gemma.Message.text(text: userTurn, isUser: true));

    await for (final response in _chat!.generateChatResponseAsync()) {
      if (response is gemma.ThinkingResponse) {
        yield TutorThinking(response.content);
      } else if (response is gemma.TextResponse) {
        yield TutorReply(response.token);
      }
    }
  }

  /// Evaluate student understanding for a question (0.0–1.0).
  /// Returns null if score cannot be determined.
  Future<double?> evaluateQuestionScore({
    required Question question,
    required List<StudyMaterial> materials,
    required List<QuestionMessage> history,
  }) async {
    if (history.isEmpty) return null;

    final materialsContext = materials
        .map((m) => '${m.title}:\n${m.content}')
        .join('\n\n');

    final historyText = history.map((m) {
      final role = m.role == QuestionMessageRole.user ? 'Student' : 'Tutor';
      return '$role: ${m.content}';
    }).join('\n');

    const systemInstruction =
        'You are an evaluator. Rate student understanding on a scale from 0.0 to 1.0. '
        'Respond with ONLY a single decimal number. Nothing else.';

    await createSession(systemInstruction: systemInstruction, temperature: 0.1, topK: 1);

    final prompt = '${materialsContext.isNotEmpty ? 'Study materials:\n$materialsContext\n\n' : ''}'
        'Question: ${question.questionText}\n\n'
        'Conversation:\n$historyText\n\n'
        'Rate the student\'s understanding (0.0 = wrong, 0.5 = partial, 1.0 = correct). '
        'Reply with ONLY a number:';

    final raw = await sendMessage(prompt);
    return double.tryParse(raw.trim().replaceAll(RegExp(r'[^0-9.]'), ''));
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

}
