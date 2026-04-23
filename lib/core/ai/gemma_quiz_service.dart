import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart' as gemma;

import '../models/models.dart';
import 'gemma_inference_service.dart';
import 'material_preprocessor.dart';
import 'response_loop_guard.dart';
import 'quiz_generation_event.dart';

/// Service for agentic quiz generation with multi-turn tool calling.
///
/// Works with [GemmaInferenceService] to generate quizzes through
/// an agent loop: analyze → generate → review → finish.
class GemmaQuizService {
  GemmaQuizService(this._inference);

  final GemmaInferenceService _inference;

  static const String _quizSystemPrompt = '''
ROLE: You are a quiz generator for elementary students.

WORKFLOW:
1. Call set_questions_count(count) to set total - REMEMBER this number
2. Call add_question() for each question one at a time
3. Keep track: after each question, check if you've reached the set_questions_count
4. Call finish_run() ONLY after generating exactly the set_questions_count number of questions

OUTPUT RULES:
- CRITICAL: Every response MUST be a tool call. Never output quiz text directly.
- Plain question text only, no numbering (1., Question 1, A., a.)
- multipleChoice: REQUIRED 3-4 options parameter, no letters (A/B/C/D, a/b/c/d)

CONTENT RULES:
- MANDATORY: Use existing questions from materials/images verbatim when available
- If materials have images with questions, extract and use those questions first
- Only generate new questions when materials lack sufficient questions
- Reference images in questions when relevant (e.g., "In the diagram...")
- Cover different topics from materials, not just one concept
- No duplicate questions - if you submit a duplicate, you will receive an error and must generate a different question
- Simple, kid-friendly language matching material complexity

WORKFLOW ENFORCEMENT:
- MUST generate EXACTLY the number of questions set in set_questions_count
- MUST keep track of how many questions you've generated
- DO NOT call finish_run() until you've generated exactly set_questions_count questions
- If you set count to 15, you MUST generate 15 questions before finish_run

DO NOT:
- Output questions as free text
- Use numbering or option letters
- Repeat questions
- Use complex vocabulary beyond the materials
- Call finish_run() before generating all questions
''';

  static const _setQuestionCountTool = gemma.Tool(
    name: 'set_questions_count',
    description:
        'Count total count available questions on the materials. '
        'Call this before plan(). If not called, defaults to 10.',
    parameters: {
      'type': 'object',
      'properties': {
        'count': {
          'type': 'integer',
          'description': 'Total count available questions on the materials',
        },
      },
      'required': ['count'],
    },
  );

  static const _questionTool = gemma.Tool(
    name: 'add_question',
    description:
        'Submit one quiz question through a tool call. Use plain, unnumbered question text and plain option text without A./B. labels. '
        'If the materials contain existing questions, use the exact question text provided. '
        'You must call this once per question.',
    parameters: {
      'type': 'object',
      'properties': {
        'type': {
          'type': 'string',
          'enum': ['multipleChoice', 'textAnswer'],
        },
        'questionText': {
          'type': 'string',
          'description':
              'Plain question text only. Do not include numbering such as "1." or "Question 1".',
        },
        'options': {
          'type': 'array',
          'items': {'type': 'string'},
          'description':
              'Required for multipleChoice (3-4 items). Use plain option text only and omit labels like A./B./C./D. Omit for textAnswer.',
        },
        'topic': {
          'type': 'string',
          'description': 'What topic this tests (guidance only, not stored)',
        },
        'difficulty': {
          'type': 'string',
          'enum': ['easy', 'medium', 'hard'],
          'description': 'Difficulty level (guidance only, not stored)',
        },
      },
      'required': ['type', 'questionText'],
    },
  );

  static const _finishTool = gemma.Tool(
    name: 'finish_run',
    description:
        'Finalize and submit the complete quiz. Call this last when all questions are ready and no duplicates remain.',
    parameters: {
      'type': 'object',
      'properties': {},
    },
  );

  /// Agentic quiz generation with planning and finish_run.
  /// Flow: analyze → generate N questions → finish_run
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
    final guard = ResponseLoopGuard();

    await _inference.createSession(
      systemInstruction: _quizSystemPrompt,
      isThinking: false,
      promptDialect: gemma.PromptDialect.gemma4,
      toolChoice: gemma.ToolChoice.required,
      tools: [
        _setQuestionCountTool,
        _questionTool,
        _finishTool
      ],
      supportsFunctionCalls: true,
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

    // Single continuous agent loop
    final initialPrompt =
        'Generate a quiz for "${session.title}" (Grade ${session.gradeOverride}) '
        'based on these study materials. '
        'Call set_questions_count(count) first to count available questions, then add questions.\n\n$textContext';

    await _inference.addTextQuery(initialPrompt, prefix: true);

    yield QuizThinkingToken('');

    // State tracking
    var questionCount = maxQuestions ?? 10;
    var finishCalled = false;
    final questions = <Question>[];
    var currentQuestionIndex = 0;

    // Outer loop for multiple turns
    while (!finishCalled) {
      // Check session state before generating
      if (!_inference.hasActiveSession) {
        throw StateError('Session was closed during generation. Please retry.');
      }

      // Inner loop for single turn responses
      try {
        await for (final response in _inference.generateResponses()) {
          if (response is gemma.ThinkingResponse) {
            yield QuizThinkingToken(response.content);
            continue;
          }

          if (response is gemma.TextResponse) {
            final error = guard.recordTextToken(response.token);
            if (error != null) {
              throw StateError(error);
            }
            yield QuizTextToken(response.token);
            continue;
          }

          // Handle both single and parallel function calls
          final toolCalls = <gemma.FunctionCallResponse>[];
          if (response is gemma.FunctionCallResponse) {
            toolCalls.add(response);
          } else if (response is gemma.ParallelFunctionCallResponse) {
            toolCalls.addAll(response.calls);
          } else {
            continue;
          }

          for (final toolResponse in toolCalls) {
            final error = guard.recordToolCall(toolResponse.name, toolResponse.args);
            if (error != null) {
              throw StateError(error);
            }

            switch (toolResponse.name) {
              case 'set_questions_count':
                final count = (toolResponse.args['count'] as num?)?.toInt() ?? 10;
                questionCount = count == 0 ? 10 : count;
                await _inference.addToolResponse(
                  toolName: 'set_questions_count',
                  response: {'count': questionCount, 'success': true},
                );
                yield QuizPlanned(questionCount, []);
                yield QuizGenerationStarted(questionCount);
                break;

              case 'add_question':
                Question? parsed;
                var retries = 0;
                const maxQuestionAttempts = 3;

                while (parsed == null && retries < maxQuestionAttempts) {
                  parsed = _parseToolCallQuestion(
                    toolResponse.args,
                    orderIndex: currentQuestionIndex,
                  );
                  if (parsed == null) retries++;
                }

                if (parsed == null) {
                  yield QuizGenerationError('Failed to generate question');
                  await _inference.addToolResponse(
                    toolName: 'add_question',
                    response: {'success': false, 'error': 'Invalid question format. Please try again with correct format.'},
                  );
                } else {
                  // Check for duplicate question text
                  final questionText = parsed.questionText;
                  final isDuplicate = questions.any((q) => 
                    q.questionText.toLowerCase() == questionText.toLowerCase()
                  );
                  
                  if (isDuplicate) {
                    await _inference.addToolResponse(
                      toolName: 'add_question',
                      response: {'success': false, 'error': 'Duplicate question. This question already exists. Please generate a different question.'},
                    );
                  } else {
                    questions.add(parsed);
                    currentQuestionIndex++;
                    await _inference.addToolResponse(
                      toolName: 'add_question',
                      response: {
                        'index': currentQuestionIndex,
                        'total': questionCount,
                        'success': true,
                      },
                    );
                    yield QuizQuestionGenerated(
                      parsed,
                      currentQuestionIndex,
                      questionCount,
                    );
                  }
                }
                break;

              case 'finish_run':
                if (finishCalled) {
                  continue;
                }
                finishCalled = true;

                await _inference.addToolResponse(
                  toolName: 'finish_run',
                  response: {'success': true},
                );
                break;
            }
          }
        }
      } catch (e) {
        final errorStr = e.toString();
        if (errorStr.contains('No active chat') || 
            errorStr.contains('Session not created') ||
            errorStr.contains('Session is cancelled')) {
          throw StateError('Session was closed during generation. Please retry.');
        }
        rethrow;
      }
    }

    yield QuizSubmitted();
    yield QuizGenerationComplete(questions);
  }

  Question? _parseToolCallQuestion(
    Map<String, dynamic> args, {
    required int orderIndex,
  }) {
    try {
      final typeStr = args['type'] as String? ?? 'multipleChoice';
      final type = typeStr == 'textAnswer'
          ? QuestionType.textAnswer
          : QuestionType.multipleChoice;
      final questionText = _cleanQuestionText(args['questionText'] as String?);
      if (questionText == null) return null;

      final rawOptions = (args['options'] as List<dynamic>?) ?? const [];
      final options = <String>[];
      for (final option in rawOptions) {
        if (option is! String) return null;
        final cleaned = _cleanOptionText(option);
        if (cleaned == null) return null;
        options.add(cleaned);
      }

      if (type == QuestionType.multipleChoice &&
          (options.length < 3 || options.length > 4)) {
        return null;
      }

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

  String? _cleanQuestionText(String? value) {
    if (value == null) return null;
    final cleaned = value
        .replaceFirst(
          RegExp(r'^\s*(?:question\s*)?\d+[\s.)\-:]+', caseSensitive: false),
          '',
        )
        .trim();
    return cleaned.isEmpty ? null : cleaned;
  }

  String? _cleanOptionText(String? value) {
    if (value == null) return null;
    final cleaned = value
        .replaceFirst(
          RegExp(r'^\s*(?:\(?[A-Da-d]\)?|\(?[1-4]\)?)[\s.)\-:]+'),
          '',
        )
        .trim();
    return cleaned.isEmpty ? null : cleaned;
  }
}
