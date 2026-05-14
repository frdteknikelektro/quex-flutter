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
    if (result.isEmpty) {
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

If the <context> below has more than $targetCount questions, randomly pick $targetCount questions from it. 
If it has fewer than $targetCount, use all of them and generate new ones from the Study Materials until you have exactly $targetCount.

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
        
        // --- Robust Separator Parsing ---
        // We look for "---" separators. If a block is completed, we parse it.
        while (currentBuffer.contains('---')) {
          final qEnd = currentBuffer.indexOf('---');
          final block = currentBuffer.substring(0, qEnd).trim();
          currentBuffer = currentBuffer.substring(qEnd + 3);
          
          if (block.isNotEmpty) {
            final question = _parseMarkdownBlock(block, questions.length);
            if (question != null) {
              questions.add(question);
              yield QuizQuestionGenerated(question, questions.length, targetCount);
            }
          }
        }
      }
    }

    // Try to parse any remaining content as the last question
    if (currentBuffer.trim().isNotEmpty) {
      final question = _parseMarkdownBlock(currentBuffer.trim(), questions.length);
      if (question != null) {
        questions.add(question);
        yield QuizQuestionGenerated(question, questions.length, targetCount);
      }
    }

    if (questions.isNotEmpty) {
      yield QuizGenerationComplete(questions);
    } else {
      yield QuizGenerationError('Failed to generate any valid questions.');
    }
  }

  /// Parses a block that may contain question text and options in markdown format.
  Question? _parseMarkdownBlock(String block, int index) {
    final lines = block.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    if (lines.isEmpty) return null;

    String questionText = '';
    final options = <String>[];

    for (final line in lines) {
      if (line.startsWith('- ') || line.startsWith('* ')) {
        options.add(line.substring(2).trim());
      } else if (options.isEmpty) {
        if (questionText.isNotEmpty) questionText += '\n';
        questionText += line;
      }
    }

    if (questionText.isEmpty) return null;

    return Question(
      quizId: -1,
      source: QuestionSource.generated,
      type: options.isEmpty ? QuestionType.textAnswer : QuestionType.multipleChoice,
      questionText: questionText,
      options: options,
      orderIndex: index,
    );
  }
}
