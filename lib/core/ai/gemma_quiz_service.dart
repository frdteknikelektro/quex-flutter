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
ROLE: Generate quiz questions from study materials.

OUTPUT FORMAT (STRICT):
# Quiz

Total: {questionCount} questions

---

{question text}

---

{question text}

---

END

RULES:
- Generate exactly the requested number of questions based on existing on materials or 15 if not exists
- Each question must be text-answer only (no multiple choice)
- Use plain question text, no numbering
- Separate questions with "---"
- End with "END" on its own line
- No duplicate questions
- Use the same language as the study materials
- Simple, clear language
''';


  /// Streamlined quiz generation with markdown output.
  /// Flow: single prompt → stream text → parse markdown → return questions
  Stream<QuizGenerationEvent> runQuizAgent({
    required Session session,
    required List<StudyMaterial> materials,
    int? maxQuestions,
  }) async* {
    if (!_inference.isInitialized) {
      throw StateError('Service not initialized');
    }

    final questionCount = maxQuestions ?? 10;
    final prepared = await MaterialPreprocessor.prepare(materials);
    final hasImages = prepared.any((p) => p.images.isNotEmpty);

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
    if (allImages.isNotEmpty) {
      debugPrint('[Quiz] Queuing ${allImages.length} images');
      await _inference.addImagesToQueue(allImages);
    }

    final initialPrompt =
        'Generate $questionCount quiz questions for "${session.title}" '
        'based on these study materials.\n\n$textContext';

    await _inference.addTextQuery(initialPrompt, prefix: true);

    yield QuizThinkingToken('');
    yield QuizGenerationStarted(questionCount);

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
        final questions = _parseMarkdownQuiz(fullResponse, questionCount);
        
        if (questions.length == questionCount) {
          yield QuizGenerationComplete(questions);
          return;
        } else {
          retryCount++;
          if (retryCount < maxRetries) {
            yield QuizGenerationError(
              'Generated ${questions.length} questions, expected $questionCount. Retrying...',
            );
            await _inference.addTextQuery(
              'Please generate exactly $questionCount questions. Ensure format: # Quiz, Total line, --- separators, END at end.',
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

  List<Question> _parseMarkdownQuiz(String markdown, int expectedCount) {
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
      
      questions.add(Question(
        quizId: -1,
        source: QuestionSource.generated,
        type: QuestionType.textAnswer,
        questionText: text,
        options: [],
        orderIndex: i,
      ));
    }
    
    return questions;
  }
}
