import 'dart:async';
import '../models/models.dart';
import 'chat_prompts.dart';
import 'gemma_chat_service.dart';
import 'material_preprocessor.dart';
import 'quiz_generation_event.dart';

/// Service for generating quizzes using a robust marker-based protocol.
/// 
/// Replaces GemmaQuizService with a more reliable implementation that uses
/// GemmaChatService singleton and a custom streaming parser to avoid JSON corruption.
class QuizGenerationService {
  final GemmaChatService _chatService = GemmaChatService.getInstance();
  
  bool get isInitialized => _chatService.isInitialized;

  Future<void> initialize() => _chatService.initialize();

  /// Session 1: Context-aware extraction of existing questions.
  Stream<QuizGenerationEvent> runExtractionSession({
    required Session session,
    required List<StudyMaterial> materials,
    String locale = 'en',
  }) async* {
    yield QuizExtractionStarted();

    final prepared = await MaterialPreprocessor.prepare(materials);
    final textContext = prepared.map((p) => p.textChunk).join('\n\n');
    final images = prepared.expand((p) => p.images).toList();

    await _chatService.createSession(
      systemInstruction: ChatPrompts.getQuizExtractionInstruction(locale),
      temperature: 0.7, // Lower temperature for accuracy in extraction
    );

    final prompt = 'Extract questions for "${session.title}" from these materials:\n\n$textContext';
    
    final Stream<({String? text, String? thinking})> stream;
    if (images.isNotEmpty) {
      stream = _chatService.sendMessageWithImages(prompt, images);
    } else {
      stream = _chatService.sendMessage(prompt);
    }

    StringBuffer fullText = StringBuffer();
    await for (final event in stream) {
      if (event.thinking != null) yield QuizThinkingToken(event.thinking!);
      if (event.text != null) {
        fullText.write(event.text);
        yield QuizTextToken(event.text!);
      }
    }

    final result = fullText.toString().trim();
    if (result.isEmpty || !result.contains('[Q]')) {
      yield QuizExtractionEmpty();
    } else {
      yield QuizExtractionComplete(result);
    }
  }

  /// Session 2: Generation of a full quiz using extracted questions as context.
  Stream<QuizGenerationEvent> runGenerationSession({
    required Session session,
    required List<StudyMaterial> materials,
    required String extractedQuestions,
    int targetCount = 10,
    String locale = 'en',
  }) async* {
    yield QuizGenerationStarted(targetCount);

    final prepared = await MaterialPreprocessor.prepare(materials);
    final textContext = prepared.map((p) => p.textChunk).join('\n\n');
    final images = prepared.expand((p) => p.images).toList();

    await _chatService.createSession(
      systemInstruction: ChatPrompts.getQuizGenerationInstruction(session.title, locale),
      temperature: 1.0,
    );

    final prompt = '''Generate a quiz with exactly $targetCount questions for "${session.title}".
    
<context>
$extractedQuestions
</context>

Study Materials:
$textContext''';

    final Stream<({String? text, String? thinking})> stream;
    if (images.isNotEmpty) {
      stream = _chatService.sendMessageWithImages(prompt, images);
    } else {
      stream = _chatService.sendMessage(prompt);
    }

    final questions = <Question>[];
    String currentBuffer = '';
    
    await for (final event in stream) {
      if (event.thinking != null) yield QuizThinkingToken(event.thinking!);
      if (event.text != null) {
        yield QuizTextToken(event.text!);
        currentBuffer += event.text!;
        
        // --- Robust Marker Parsing (Option 1) ---
        // We look for [Q]...[/Q] blocks. If a block is completed, we parse it.
        // Reason: On-device AI can sometimes drop characters in JSON tool calls, 
        // but marker-based text is extremely resilient to minor token corruption.
        while (currentBuffer.contains('[/Q]')) {
          final qEnd = currentBuffer.indexOf('[/Q]');
          final block = currentBuffer.substring(0, qEnd + 4);
          currentBuffer = currentBuffer.substring(qEnd + 4);
          
          final question = _parseMarkerBlock(block, questions.length);
          if (question != null) {
            questions.add(question);
            yield QuizQuestionGenerated(question, questions.length, targetCount);
          }
        }
      }
    }

    if (questions.isNotEmpty) {
      yield QuizGenerationComplete(questions);
    } else {
      yield QuizGenerationError('Failed to generate any valid questions.');
    }
  }

  /// Parses a block that may contain [CONTEXT]...[/CONTEXT] and MUST contain [Q]...[/Q]
  Question? _parseMarkerBlock(String block, int index) {
    String contextText = '';
    if (block.contains('[CONTEXT]') && block.contains('[/CONTEXT]')) {
      final start = block.indexOf('[CONTEXT]') + 9;
      final end = block.indexOf('[/CONTEXT]');
      contextText = block.substring(start, end).trim();
    }

    if (block.contains('[Q]') && block.contains('[/Q]')) {
      final start = block.indexOf('[Q]') + 3;
      final end = block.indexOf('[/Q]');
      String qText = block.substring(start, end).trim();
      
      // "Harden" the question by attaching the context directly
      if (contextText.isNotEmpty) {
        qText = '$contextText\n\n$qText';
      }

      return Question(
        quizId: -1,
        source: QuestionSource.generated,
        type: QuestionType.textAnswer,
        questionText: qText,
        options: const [],
        orderIndex: index,
      );
    }
    return null;
  }
}
