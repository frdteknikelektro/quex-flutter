import 'dart:async';
import 'dart:typed_data';

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

  static const _planTool = gemma.Tool(
    name: 'plan',
    description:
        'Declare your complete plan before starting any work. Call once at the very beginning. '
        'List every step you intend to take in order and do not repeat the plan later.',
    parameters: {
      'type': 'object',
      'properties': {
        'steps': {
          'type': 'array',
          'items': {'type': 'string'},
          'description':
              'Ordered list of steps, e.g. ["Analyze materials", "Generate 10 questions", "Review quality", "Finish"]',
        },
      },
      'required': ['steps'],
    },
  );

  static const _completeStepTool = gemma.Tool(
    name: 'complete_step',
    description:
        'Mark a planned step as done. Call after finishing each step from your plan, in order.',
    parameters: {
      'type': 'object',
      'properties': {
        'index': {
          'type': 'integer',
          'description': '0-based index of the completed step from your plan',
        },
      },
      'required': ['index'],
    },
  );

  static const _analyzeTool = gemma.Tool(
    name: 'analyze_materials',
    description:
        'Analyze study materials and plan the quiz. Decide question count, topic coverage, difficulty mix, and avoid repeating the same concept.',
    parameters: {
      'type': 'object',
      'properties': {
        'question_count': {
          'type': 'integer',
          'minimum': 5,
          'maximum': 20,
          'description': 'How many questions to generate (5-20)',
        },
        'topics': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': 'Key topics identified in the materials',
        },
      },
      'required': ['question_count', 'topics'],
    },
  );

  static const _questionTool = gemma.Tool(
    name: 'generate_question',
    description:
        'Submit one quiz question. You must call this once per question and choose a new concept or sub-skill each time.',
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
          'description':
              'Required for multipleChoice (3-4 items). Omit for textAnswer.',
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

  static const _reviewTool = gemma.Tool(
    name: 'review_quiz',
    description:
        'Review generated questions for quality, coverage, repeated concepts, duplicate wording, and weak distractors before submitting.',
    parameters: {
      'type': 'object',
      'properties': {
        'issues_found': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': 'List of issues like duplicates or gaps',
        },
        'regenerate_indices': {
          'type': 'array',
          'items': {'type': 'integer'},
          'description': '0-based indices of questions to regenerate',
        },
        'ready_to_submit': {
          'type': 'boolean',
          'description': 'True if quiz is ready for finish_run',
        },
      },
      'required': ['ready_to_submit'],
    },
  );

  static const _finishTool = gemma.Tool(
    name: 'finish_run',
    description:
        'Finalize and submit the complete quiz. Call this last when all questions are ready and no duplicates remain.',
    parameters: {
      'type': 'object',
      'properties': {
        'summary': {
          'type': 'string',
          'description': 'One-sentence summary of what was created',
        },
        'total_questions': {
          'type': 'integer',
          'description': 'Final question count',
        },
      },
      'required': ['summary', 'total_questions'],
    },
  );

  /// Agentic quiz generation with planning, review, and finish_run.
  /// Flow: analyze → generate N questions → review → (regenerate if needed) → finish_run
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

    const systemInstruction =
        'You are a quiz generator agent for elementary students. '
        'Follow this silent sequence exactly: plan once, analyze the materials once, generate one question at a time, '
        'self-check each question against earlier questions before submitting it, review the whole quiz, regenerate only flagged items, then finish. '
        'Call plan() first with the full ordered workflow, then call complete_step(index) after each finished step. '
        'Every turn must be a tool call using one of the provided tools. '
        'Do not output free text, markdown, reasoning, or explanations. '
        'Generate only questions grounded in the provided materials. '
        'Never repeat the same question, paraphrase an earlier question, or ask the same concept twice unless the materials are too narrow and you must vary the angle. '
        'Use multipleChoice for factual recall with 3-4 options. '
        'Use textAnswer for short definitions or concise explanations. '
        'Match difficulty to grade level and keep wording simple, clear, and kid-friendly.';

    await _inference.createSession(
      systemInstruction: systemInstruction,
      isThinking: false,
      promptDialect: gemma.PromptDialect.gemma4,
      toolChoice: gemma.ToolChoice.required,
      tools: [
        _planTool,
        _completeStepTool,
        _analyzeTool,
        _questionTool,
        _reviewTool,
        _finishTool
      ],
      supportsFunctionCalls: true,
      supportImage: hasImages,
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

    // Phase 1: Analysis
    final initialPrompt =
        'Analyze these study materials for "${session.title}" (Grade ${session.gradeOverride}) '
        'and plan the quiz. ${maxQuestions != null ? "Target around $maxQuestions questions. " : ""}'
        'Prefer distinct concepts across the quiz and avoid repeating the same idea in a new form. '
        'Call analyze_materials now.\n\n$textContext';

    await _inference.addTextQuery(initialPrompt);

    int? plannedCount;
    List<String> plannedTopics = [];
    var waitingForAnalyze = true;
    var analyzeAttempts = 0;
    const maxAnalyzeAttempts = 5;

    while (waitingForAnalyze) {
      await for (final response in _inference.generateResponses()) {
        if (response is! gemma.FunctionCallResponse) {
          continue;
        }

        final error = guard.recordToolCall(response.name, response.args);
        if (error != null) {
          throw StateError(error);
        }

        switch (response.name) {
          case 'plan':
            final steps =
                (response.args['steps'] as List<dynamic>?)?.cast<String>() ??
                    [];
            await _inference.addToolResponse(
              toolName: 'plan',
              response: {'acknowledged': true},
            );
            yield QuizPlanAnnounced(steps);
            continue;
          case 'complete_step':
            final index = (response.args['index'] as num?)?.toInt() ?? 0;
            await _inference.addToolResponse(
              toolName: 'complete_step',
              response: {'acknowledged': true},
            );
            yield QuizStepCompleted(index);
            continue;
          case 'analyze_materials':
            plannedCount = (response.args['question_count'] as num?)?.toInt();
            final topics = response.args['topics'];
            if (topics is List) {
              plannedTopics = topics.cast<String>();
            }
            waitingForAnalyze = false;

            // Acknowledge analysis
            await _inference.addToolResponse(
              toolName: 'analyze_materials',
              response: {'acknowledged': true, 'planned_count': plannedCount},
            );

            if (plannedCount != null) {
              yield QuizPlanned(plannedCount, plannedTopics);
            }
            break;
        }
      }
      if (waitingForAnalyze) {
        analyzeAttempts++;
        if (analyzeAttempts >= maxAnalyzeAttempts) {
          throw StateError(
            'Quiz agent stopped without calling analyze_materials after '
            '$analyzeAttempts attempts.',
          );
        }
        // Retry prompt
        await _inference
            .addTextQuery('Please call analyze_materials to plan the quiz.');
      }
    }

    final questionCount = plannedCount ?? maxQuestions ?? 10;

    // Phase 2: Generation loop
    final questions = <Question>[];

    for (var i = 1; i <= questionCount; i++) {
      Question? parsed;
      var retries = 0;
      const maxQuestionAttempts = 3;

      while (parsed == null && retries < maxQuestionAttempts) {
        var gotCall = false;

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

            if (response is! gemma.FunctionCallResponse) {
              continue;
            }

            final error = guard.recordToolCall(response.name, response.args);
            if (error != null) {
              throw StateError(error);
            }

            switch (response.name) {
              case 'plan':
                final steps = (response.args['steps'] as List<dynamic>?)
                        ?.cast<String>() ??
                    [];
                await _inference.addToolResponse(
                  toolName: 'plan',
                  response: {'acknowledged': true},
                );
                yield QuizPlanAnnounced(steps);
                continue;
              case 'complete_step':
                final index = (response.args['index'] as num?)?.toInt() ?? 0;
                await _inference.addToolResponse(
                  toolName: 'complete_step',
                  response: {'acknowledged': true},
                );
                yield QuizStepCompleted(index);
                continue;
              case 'generate_question':
                gotCall = true;
                parsed =
                    _parseToolCallQuestion(response.args, orderIndex: i - 1);
                if (parsed == null) retries++;

                // Acknowledge generation
                await _inference.addToolResponse(
                  toolName: 'generate_question',
                  response: {
                    'acknowledged': true,
                    'index': i,
                    'valid': parsed != null,
                  },
                );
                continue;
            }
          }
        } catch (e) {
          debugPrint('Turn $i error: $e');
          retries++;
        }

        if (!gotCall) retries++;

        if (parsed == null && retries < maxQuestionAttempts) {
          await _inference.addTextQuery(
              'Please call generate_question for question $i of $questionCount.');
        }
      }

      if (parsed == null) {
        yield QuizGenerationError('Failed to generate question $i');
        return;
      }

      questions.add(parsed);
      yield QuizQuestionGenerated(parsed, i, questionCount);

      // Prompt for next question or review
      if (i < questionCount) {
        await _inference.addTextQuery(
            'Question $i recorded. Now generate question ${i + 1} of $questionCount.');
      }
    }

    // Phase 3: Review
    yield QuizUnderReview([]);
    await _inference.addTextQuery(
        'All $questionCount questions generated. Call review_quiz to check quality before finishing.');

    var reviewCycles = 0;
    const maxReviewCycles = 3;

    while (reviewCycles < maxReviewCycles) {
      List<int> regenerateIndices = [];
      final reviewIssues = <String>[];
      await for (final response in _inference.generateResponses()) {
        if (response is! gemma.FunctionCallResponse) {
          continue;
        }

        final error = guard.recordToolCall(response.name, response.args);
        if (error != null) {
          throw StateError(error);
        }

        switch (response.name) {
          case 'plan':
            final steps =
                (response.args['steps'] as List<dynamic>?)?.cast<String>() ??
                    [];
            await _inference.addToolResponse(
              toolName: 'plan',
              response: {'acknowledged': true},
            );
            yield QuizPlanAnnounced(steps);
            continue;
          case 'complete_step':
            final index = (response.args['index'] as num?)?.toInt() ?? 0;
            await _inference.addToolResponse(
              toolName: 'complete_step',
              response: {'acknowledged': true},
            );
            yield QuizStepCompleted(index);
            continue;
          case 'review_quiz':
            final ready = response.args['ready_to_submit'] as bool? ?? false;
            final issues = response.args['issues_found'];
            final indices = response.args['regenerate_indices'];

            if (issues is List) {
              reviewIssues.addAll(issues.cast<String>());
            }

            if (indices is List) {
              regenerateIndices =
                  indices.map((i) => (i as num).toInt()).toList();
            }

            if (reviewIssues.isNotEmpty) {
              yield QuizUnderReview(reviewIssues);
            }

            await _inference.addToolResponse(
              toolName: 'review_quiz',
              response: {
                'acknowledged': true,
                'ready': ready && regenerateIndices.isEmpty,
                'regenerate_count': regenerateIndices.length,
              },
            );

            if (ready && regenerateIndices.isEmpty) {
              break;
            }
            continue;
        }
      }

      if (regenerateIndices.isEmpty) break;

      // Regenerate flagged questions
      for (final idx in regenerateIndices) {
        if (idx < 0 || idx >= questions.length) continue;

        yield QuizRegenerating(idx);
        Question? replaced;
        var regenRetries = 0;

        while (replaced == null && regenRetries < 2) {
          await _inference.addTextQuery(
            'Regenerate question ${idx + 1}. Call generate_question with a different concept, not a paraphrase of an earlier question.',
          );

          await for (final response in _inference.generateResponses()) {
            if (response is! gemma.FunctionCallResponse) {
              continue;
            }

            final error = guard.recordToolCall(response.name, response.args);
            if (error != null) {
              throw StateError(error);
            }

            switch (response.name) {
              case 'plan':
                final steps = (response.args['steps'] as List<dynamic>?)
                        ?.cast<String>() ??
                    [];
                await _inference.addToolResponse(
                  toolName: 'plan',
                  response: {'acknowledged': true},
                );
                yield QuizPlanAnnounced(steps);
                continue;
              case 'complete_step':
                final index = (response.args['index'] as num?)?.toInt() ?? 0;
                await _inference.addToolResponse(
                  toolName: 'complete_step',
                  response: {'acknowledged': true},
                );
                yield QuizStepCompleted(index);
                continue;
              case 'generate_question':
                replaced =
                    _parseToolCallQuestion(response.args, orderIndex: idx);

                await _inference.addToolResponse(
                  toolName: 'generate_question',
                  response: {
                    'acknowledged': true,
                    'index': idx + 1,
                    'valid': replaced != null,
                  },
                );
                break;
            }
          }
          regenRetries++;
        }

        if (replaced != null) {
          questions[idx] = replaced;
          yield QuizQuestionGenerated(replaced, idx + 1, questions.length);
        }
      }

      reviewCycles++;
      if (reviewCycles < maxReviewCycles) {
        await _inference.addTextQuery('Review again after regeneration.');
      }
    }

    // Phase 4: Finish
    await _inference.addTextQuery('Call finish_run to complete the quiz.');

    var summary = '';

    await for (final response in _inference.generateResponses()) {
      if (response is! gemma.FunctionCallResponse) {
        continue;
      }

      final error = guard.recordToolCall(response.name, response.args);
      if (error != null) {
        throw StateError(error);
      }

      switch (response.name) {
        case 'plan':
          final steps =
              (response.args['steps'] as List<dynamic>?)?.cast<String>() ?? [];
          await _inference.addToolResponse(
            toolName: 'plan',
            response: {'acknowledged': true},
          );
          yield QuizPlanAnnounced(steps);
          continue;
        case 'complete_step':
          final index = (response.args['index'] as num?)?.toInt() ?? 0;
          await _inference.addToolResponse(
            toolName: 'complete_step',
            response: {'acknowledged': true},
          );
          yield QuizStepCompleted(index);
          continue;
        case 'finish_run':
          summary = (response.args['summary'] as String?) ?? '';

          await _inference.addToolResponse(
            toolName: 'finish_run',
            response: {'acknowledged': true},
          );
          break;
      }
    }

    yield QuizSubmitted(summary);
    yield QuizGenerationComplete(questions);
  }

  /// Scan materials for existing quiz questions.
  /// Returns verbatim question texts found, or empty list if none detected.
  Future<List<String>> detectQuestionsInMaterials({
    required List<StudyMaterial> materials,
  }) async {
    if (!_inference.isInitialized) {
      throw StateError('Service not initialized');
    }

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

    await _inference.createSession(
      systemInstruction: systemInstruction,
      temperature: 0.1,
      topK: 1,
      supportImage: hasImages,
      promptDialect: gemma.PromptDialect.gemma4,
      toolChoice: gemma.ToolChoice.auto,
    );

    final prompt = 'Extract all quiz questions from these materials. '
        'One per line, or NONE if none exist.\n\n$textContext';

    for (final prep in prepared) {
      for (final imgBytes in prep.images) {
        await _inference.addImageQuery(imgBytes);
      }
    }

    await _inference.addTextQuery(prompt);

    final response = await _inference.generateResponse();
    final raw = response is gemma.TextResponse ? response.token : '';

    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed.toUpperCase() == 'NONE') return [];

    return trimmed
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && line.toUpperCase() != 'NONE')
        .toList();
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
      final options = (args['options'] as List<dynamic>?)?.cast<String>() ?? [];

      if (type == QuestionType.multipleChoice && options.length < 2) {
        return null;
      }

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
}
