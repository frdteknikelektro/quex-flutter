import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart' as gemma;

import '../models/models.dart';
import 'gemma_inference_service.dart';
import 'material_preprocessor.dart';
import 'quiz_generation_event.dart';

/// Service for streamlined quiz generation with markdown output.
///
/// Works with [GemmaInferenceService] to generate quizzes through
/// a single prompt that returns questions in markdown format.
class GemmaQuizService {
  GemmaQuizService(this._inference);

  final GemmaInferenceService _inference;

  static const String _quizSystemPrompt = '''
ROLE: Generate quiz from study materials and existing questions.

RULES (STRICT):
- MUST use existing questions from <context> if provided
- If <context> is empty or NO existing questions, generate NEW questions from materials
- If item is already a question (with no answer), KEEP it as-is
  - Examples of questions to KEEP UNCHANGED:
    - "What is the capital of France?"
    - "How do you convert meters to kilometers?"
    - "The capital of France is ..." (fill-in-the-blank)
- If existing questions don't make sense or are unclear, REWRITE for clarity while preserving meaning
- If any item in the list is NOT a question, CONVERT it to a question
  - Statement: "The standard unit of weight is kg" → Question: "What is the standard unit of weight?"
  - Statement: "To use the conversion ladder multiple it by 10" → Question: "How do you use the conversion ladder?"
- If existing questions are COMPLETELY UNRELATED to the topic, IGNORE them and generate new ones
- If extracted items are just facts/statements that CANNOT be meaningfully converted to questions, SKIP them
- Use plain question text, NO numbering
- Separate questions with "---"
- MUST end with "END" on its own line
- NO duplicate questions
- Use the same language as the study materials
- Simple, clear language

OUTPUT FORMAT (STRICT):
# Quiz

Total: {questionCount} questions

---

{question text}

---

{question text}

---

END
''';

  static const String _extractionSystemPrompt = '''
ROLE: Extract existing quiz questions from study materials.

OUTPUT FORMAT (STRICT):
Extract all quiz questions found in the materials as a simple markdown paragraph.
For each question, include the question text and any options if present.

Example format:
What is the capital of France?
- London
- Paris
- Berlin
- Madrid

What is 2 + 2?
- 3
- 4
- 5
- 6

RULES:
- Extract only actual quiz questions, not general statements
- DO NOT include all answer options if present
- Use simple paragraph format, not a list
- Separate questions with newlines
- If no questions are found, respond with an empty string
- Preserve the original language of the questions
''';


  /// Two-step quiz generation: extract existing questions, then generate new quiz.
  /// Flow: Session 1 (extraction) → display → Session 2 (generation with context)
  Stream<QuizGenerationEvent> runQuizAgent({
    required Session session,
    required List<StudyMaterial> materials,
    int? maxQuestions,
  }) async* {
    if (!_inference.isInitialized) {
      throw StateError('Service not initialized');
    }

    final prepared = await MaterialPreprocessor.prepare(materials);
    final hasImages = prepared.any((p) => p.images.isNotEmpty);

    // Send materials as context
    final textContext = prepared
        .map((p) => p.textChunk)
        .where((t) => t.isNotEmpty)
        .join('\n\n');

    // Queue all images to be included with first user message
    final allImages = <Uint8List>[];
    for (final prep in prepared) {
      allImages.addAll(prep.images);
    }

    // Session 1: Extract existing questions
    yield* _runExtractionSession(
      session: session,
      textContext: textContext,
      images: allImages,
      hasImages: hasImages,
    );

    // Session 2 will be called by modal after user reviews extraction results
    // We need to store the extraction result for Session 2
    // This is handled by the modal capturing QuizExtractionComplete event
  }

  /// Session 1: Extract existing questions from materials
  Stream<QuizGenerationEvent> _runExtractionSession({
    required Session session,
    required String textContext,
    required List<Uint8List> images,
    required bool hasImages,
  }) async* {
    yield QuizExtractionStarted();

    await _inference.createSession(
      systemInstruction: _extractionSystemPrompt,
      isThinking: false,
      promptDialect: gemma.PromptDialect.gemma4,
      tools: const [],
      supportsFunctionCalls: false,
      supportImage: hasImages,
      temperature: 0.3,
      topK: 10,
    );

    // Queue images before text
    if (images.isNotEmpty) {
      debugPrint('[Quiz Extraction] Queuing ${images.length} images');
      await _inference.addImagesToQueue(images);
    }

    final extractionPrompt =
        'Extract all quiz questions from these study materials for "${session.title}".\n\n$textContext';

    await _inference.addTextQuery(extractionPrompt);

    final buffer = StringBuffer();
    await for (final response in _inference.generateResponses()) {
      if (response is gemma.ThinkingResponse) {
        yield QuizThinkingToken(response.content);
        continue;
      }

      if (response is gemma.TextResponse) {
        buffer.write(response.token);
        yield QuizTextToken(response.token);
        continue;
      }
    }

    final extracted = buffer.toString().trim();

    // Check if no questions found
    if (extracted.isEmpty || extracted.length < 10) {
      yield QuizExtractionEmpty();
    } else {
      yield QuizExtractionComplete(extracted);
    }

    // Close Session 1
    await _inference.closeSession();
  }

  /// Session 2: Generate quiz with extracted questions as context
  Stream<QuizGenerationEvent> runGenerationSession({
    required Session session,
    required String textContext,
    required List<Uint8List> images,
    required bool hasImages,
    String? extractedQuestions,
  }) async* {
    await _inference.createSession(
      systemInstruction: _quizSystemPrompt,
      isThinking: false,
      promptDialect: gemma.PromptDialect.gemma4,
      tools: const [],
      supportsFunctionCalls: false,
      supportImage: hasImages,
      temperature: 0.6,
      topK: 40,
    );

    // Queue images before text
    if (images.isNotEmpty) {
      debugPrint('[Quiz Generation] Queuing ${images.length} images');
      await _inference.addImagesToQueue(images);
    }

    // Build prompt with extracted questions context
    String contextInfo = '';
    if (extractedQuestions == null || extractedQuestions.isEmpty) {
      contextInfo = '<context>\nNo existing questions were found in the materials.\n</context>';
    } else {
      contextInfo = '<context>\n$extractedQuestions\n</context>';
    }

    final generationPrompt =
        'Quiz for "${session.title}" '
        'based on these study materials.\n\n$contextInfo\n\n$textContext';

    await _inference.addTextQuery(generationPrompt, prefix: true);

    yield QuizThinkingToken('');
    yield QuizGenerationStarted(0);

    // Retry logic for parsing failures
    const maxRetries = 3;
    var retryCount = 0;
    var fullResponse = '';

    while (retryCount < maxRetries) {
      // Check session state before generating
      if (!_inference.hasActiveSession) {
        throw StateError('Session was closed during generation. Please retry.');
      }

      fullResponse = '';

      try {
        await for (final response in _inference.generateResponses()) {
          if (response is gemma.ThinkingResponse) {
            yield QuizThinkingToken(response.content);
            continue;
          }

          if (response is gemma.TextResponse) {
            fullResponse += response.token;
            yield QuizTextToken(response.token);
            continue;
          }
        }

        // Try to parse the response
        final questions = _parseMarkdownQuiz(fullResponse);

        if (questions.isNotEmpty) {
          yield QuizGenerationComplete(questions);
          return;
        } else {
          retryCount++;
          if (retryCount < maxRetries) {
            yield QuizGenerationError(
              'No questions generated. Retrying...',
            );
            await _inference.addTextQuery(
              'Please generate quiz questions. Ensure format: # Quiz, Total line, --- separators, END at end.',
            );
          }
        }
      } catch (e) {
        final errorStr = e.toString();
        if (errorStr.contains('No active chat') ||
            errorStr.contains('Session not created') ||
            errorStr.contains('Session is cancelled')) {
          throw StateError('Session was closed during generation. Please retry.');
        }

        retryCount++;
        if (retryCount < maxRetries) {
          yield QuizGenerationError('Parse error: $e. Retrying...');
          await _inference.addTextQuery(
            'Failed to parse. Please ensure format: # Quiz, Total line, --- separators, END at end.',
          );
        } else {
          rethrow;
        }
      }
    }

    yield QuizGenerationError('Failed to generate quiz after $maxRetries attempts');
  }

  List<Question> _parseMarkdownQuiz(String markdown) {
    final questions = <Question>[];
    
    // Remove header, total line, and end marker
    final withoutHeader = markdown.replaceFirst(RegExp(r'^# Quiz\s*', multiLine: true), '');
    final withoutTotal = withoutHeader.replaceFirst(RegExp(r'^Total:.*questions?\s*$', multiLine: true), '');
    final withoutEnd = withoutTotal.replaceFirst(RegExp(r'^END\s*$', multiLine: true), '');
    
    // Split by ---
    final parts = withoutEnd.split(RegExp(r'\n---\n', multiLine: true));
    
    for (var i = 0; i < parts.length; i++) {
      final text = parts[i].trim();
      if (text.isEmpty) continue;
      
      questions.add(const Question(
        quizId: -1,
        source: QuestionSource.generated,
        type: QuestionType.textAnswer,
        questionText: '',
        options: [],
        orderIndex: 0,
      ).copyWith(
        questionText: text,
        orderIndex: i,
      ));
    }
    
    return questions;
  }
}
