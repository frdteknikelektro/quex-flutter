import 'dart:async';
import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'chat_prompts.dart';
import 'gemma_chat_service.dart';
import 'material_preprocessor.dart';
import 'quiz_agent_skill.dart';
import 'quiz_generation_event.dart';

/// Service for generating quizzes using a robust marker-based protocol.
///
/// Replaces GemmaQuizService with a more reliable implementation that uses
/// GemmaChatService singleton and a custom streaming parser to avoid JSON corruption.
class QuizGenerationService {
  final QuizChatService _chatService;

  QuizGenerationService({QuizChatService? chatService})
      : _chatService = chatService ?? GemmaChatService.getInstance();

  bool get isInitialized => _chatService.isInitialized;

  Future<void> initialize() => _chatService.initialize();

  /// Session 1: Context-aware extraction of existing questions.
  Stream<QuizGenerationEvent> runExtractionSession({
    required Session session,
    required List<StudyMaterial> materials,
    String locale = 'en',
  }) async* {
    yield QuizExtractionStarted();
    yield QuizPlanAnnounced(QuizAgentSkill.workflowSteps(locale));

    final prepared = await MaterialPreprocessor.prepare(materials);
    final textContext = prepared.map((p) => p.textChunk).join('\n\n');
    final images = prepared.expand((p) => p.images).toList();

    await _chatService.createSession(
      systemInstruction: ChatPrompts.getQuizExtractionInstruction(locale),
      temperature: 0.7, // Lower temperature for accuracy in extraction
    );

    final prompt =
        'Extract questions for "${session.title}" from these materials:\n\n$textContext';

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
    yield QuizStepCompleted(0);
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

    final generatedText = StringBuffer();
    yield QuizPhaseStarted(QuizGenerationPhase.generation);
    await _chatService.createSession(
      systemInstruction:
          ChatPrompts.getQuizGenerationInstruction(session.title, locale),
      temperature: 0.3,
      topP: 0.8,
      topK: 40,
    );
    final generationPrompt = QuizAgentSkill.generationPrompt(
      sessionTitle: session.title,
      targetCount: targetCount,
      extractedQuestions: extractedQuestions,
      textContext: textContext,
    );
    final generationStream = images.isNotEmpty
        ? _chatService.sendMessageWithImages(generationPrompt, images)
        : _chatService.sendMessage(generationPrompt);
    await for (final event in generationStream) {
      if (event.thinking != null) yield QuizThinkingToken(event.thinking!);
      if (event.text != null) {
        generatedText.write(event.text!);
        yield QuizPhaseTextToken(
          QuizGenerationPhase.generation,
          event.text!,
        );
      }
    }
    yield QuizPhaseCompleted(QuizGenerationPhase.generation);
    yield QuizStepCompleted(1);

    final reviewedText = StringBuffer();
    yield QuizPhaseStarted(QuizGenerationPhase.review);
    await _chatService.createSession(
      systemInstruction: QuizAgentSkill.reviewInstruction(locale),
      temperature: 0.2,
      topP: 0.8,
      topK: 32,
    );
    final reviewPrompt = QuizAgentSkill.reviewPrompt(
      textContext: textContext,
      draftText: generatedText.toString(),
      targetCount: targetCount,
    );
    final reviewStream = images.isNotEmpty
        ? _chatService.sendMessageWithImages(reviewPrompt, images)
        : _chatService.sendMessage(reviewPrompt);
    await for (final event in reviewStream) {
      if (event.thinking != null) yield QuizThinkingToken(event.thinking!);
      if (event.text != null) {
        reviewedText.write(event.text!);
        yield QuizPhaseTextToken(
          QuizGenerationPhase.review,
          event.text!,
        );
      }
    }
    yield QuizPhaseCompleted(QuizGenerationPhase.review);
    yield QuizStepCompleted(2);

    final candidates = <QuizItemDraft>[
      ...parseStructuredDrafts(reviewedText.toString()),
      ...parseStructuredDrafts(generatedText.toString()),
    ];
    final parsedQuestions = _validQuestionsFromDrafts(candidates, targetCount);

    if (parsedQuestions.length < targetCount) {
      final missing = targetCount - parsedQuestions.length;
      final replacementText = StringBuffer();
      yield QuizPhaseStarted(QuizGenerationPhase.regeneration);
      await _chatService.createSession(
        systemInstruction:
            ChatPrompts.getQuizGenerationInstruction(session.title, locale),
        temperature: 0.3,
        topP: 0.8,
        topK: 40,
      );
      final replacementPrompt = QuizAgentSkill.generationPrompt(
        sessionTitle: session.title,
        targetCount: missing,
        extractedQuestions: extractedQuestions,
        textContext: textContext,
        reviewFeedback: _validationFeedback(candidates),
      );
      final replacementStream = images.isNotEmpty
          ? _chatService.sendMessageWithImages(replacementPrompt, images)
          : _chatService.sendMessage(replacementPrompt);
      await for (final event in replacementStream) {
        if (event.thinking != null) yield QuizThinkingToken(event.thinking!);
        if (event.text != null) {
          replacementText.write(event.text!);
          yield QuizPhaseTextToken(
            QuizGenerationPhase.regeneration,
            event.text!,
          );
        }
      }
      yield QuizPhaseCompleted(QuizGenerationPhase.regeneration);

      final replacementDrafts =
          parseStructuredDrafts(replacementText.toString());
      final replacementQuestions = _validQuestionsFromDrafts(
        replacementDrafts,
        missing,
        startIndex: parsedQuestions.length,
        existingQuestions: parsedQuestions,
      );
      parsedQuestions.addAll(replacementQuestions);
    }
    yield QuizStepCompleted(3);

    final questions = <Question>[];
    questions.addAll(parsedQuestions.take(targetCount));

    if (questions.isNotEmpty) {
      yield QuizGenerationComplete(questions);
    } else {
      yield QuizGenerationError('Failed to generate any valid questions.');
    }
  }

  List<Question> _validQuestionsFromDrafts(
    List<QuizItemDraft> drafts,
    int limit, {
    int startIndex = 0,
    List<Question> existingQuestions = const [],
  }) {
    final questions = <Question>[];
    final seen = {
      for (final question in existingQuestions)
        _normalizedQuestion(question.questionText),
    };
    for (final draft in drafts) {
      final validation = validateDraft(draft);
      if (!validation.isValid) continue;
      final normalized = _normalizedQuestion(draft.questionText);
      if (!seen.add(normalized)) continue;

      questions.add(draft.toQuestion(startIndex + questions.length));
      if (questions.length == limit) break;
    }
    return questions;
  }

  String _validationFeedback(List<QuizItemDraft> drafts) {
    final issues = <String>[];
    for (final draft in drafts) {
      final validation = validateDraft(draft);
      if (validation.isValid) continue;
      issues.add('- "${draft.questionText}": ${validation.issues.join('; ')}');
      if (issues.length >= 8) break;
    }
    if (issues.isEmpty) {
      return '- Some previous drafts were rejected because they duplicated earlier questions or failed review.';
    }
    return issues.join('\n');
  }

  static String _normalizedQuestion(String text) {
    return text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  @visibleForTesting
  List<QuizItemDraft> parseStructuredDrafts(String text) {
    final structured = _parseBracketDrafts(text);
    if (structured.isNotEmpty) return structured;

    return _parseLegacyMarkdownDrafts(text);
  }

  @visibleForTesting
  QuizDraftValidation validateDraft(QuizItemDraft draft) {
    final issues = <String>[];
    final questionText = draft.questionText.trim();
    final options =
        draft.options.map((o) => o.trim()).where((o) => o.isNotEmpty).toList();

    if (questionText.length < 12) {
      issues.add('Question is too short.');
    }
    if (_containsAnswerKeyLabel(questionText)) {
      issues.add('Question text contains an answer key label.');
    }
    if (_containsAnswerLeak(questionText, options)) {
      issues.add('Question text appears to reveal an option.');
    }
    if (options.isNotEmpty) {
      if (options.length < 2) {
        issues.add('Multiple-choice question needs at least two options.');
      }
      if (draft.correctOptionIndex == null) {
        issues.add('Multiple-choice question is missing a correct option.');
      } else if (draft.correctOptionIndex! < 0 ||
          draft.correctOptionIndex! >= options.length) {
        issues.add('Correct option is outside the option list.');
      }
      if (_hasDuplicateOptions(options)) {
        issues.add('Options contain duplicates.');
      }
      if (options.any(_containsAnswerKeyLabel)) {
        issues.add('Options contain answer key labels.');
      }
      if (options.any(_isWeakOption)) {
        issues
            .add('Options contain weak choices such as all/none of the above.');
      }
    } else {
      final expectedAnswer = draft.expectedAnswer?.trim();
      if (expectedAnswer == null || expectedAnswer.isEmpty) {
        issues.add('Text-answer question is missing an expected answer.');
      }
    }
    if (draft.explanation.trim().length < 8) {
      issues.add('Explanation is missing or too short.');
    }
    if (draft.evidence.trim().length < 8) {
      issues.add('Evidence is missing or too short.');
    }

    return QuizDraftValidation(issues);
  }

  List<QuizItemDraft> _parseBracketDrafts(String text) {
    final blocks = text
        .split(RegExp(r'\[END\]', caseSensitive: false))
        .map((b) => b.trim())
        .where((b) => b.isNotEmpty);

    return blocks
        .map(_parseBracketDraft)
        .whereType<QuizItemDraft>()
        .toList(growable: false);
  }

  QuizItemDraft? _parseBracketDraft(String block) {
    final question = _section(block, 'QUESTION');
    if (question == null || question.trim().isEmpty) return null;

    final optionsText = _section(block, 'OPTIONS') ?? '';
    final options = optionsText
        .split('\n')
        .map(_cleanOptionLine)
        .where((o) => o.isNotEmpty)
        .toList(growable: false);
    final correct = _section(block, 'CORRECT');
    final correctOptionIndex = _parseCorrectOptionIndex(correct, options);

    return QuizItemDraft(
      questionText: question.trim(),
      options: options,
      correctOptionIndex: correctOptionIndex,
      expectedAnswer: _section(block, 'EXPECTED_ANSWER')?.trim(),
      explanation: _section(block, 'EXPLANATION')?.trim() ?? '',
      evidence: _section(block, 'EVIDENCE')?.trim() ?? '',
    );
  }

  String? _section(String block, String name) {
    final pattern = RegExp(
      r'\[' + RegExp.escape(name) + r'\]\s*([\s\S]*?)(?=\n\[[A-Z_]+\]|\s*$)',
      caseSensitive: false,
    );
    return pattern.firstMatch(block)?.group(1)?.trim();
  }

  int? _parseCorrectOptionIndex(String? correct, List<String> options) {
    if (correct == null || correct.trim().isEmpty) return null;

    final normalized = correct.trim();
    final letterMatch =
        RegExp(r'^[A-Z]', caseSensitive: false).firstMatch(normalized);
    if (letterMatch != null) {
      final code = letterMatch.group(0)!.toUpperCase().codeUnitAt(0);
      final index = code - 'A'.codeUnitAt(0);
      if (index >= 0 && index < options.length) return index;
    }

    final number = int.tryParse(normalized);
    if (number != null && number > 0 && number <= options.length) {
      return number - 1;
    }

    final answerText = _cleanOptionLine(normalized).toLowerCase();
    return options.indexWhere((option) => option.toLowerCase() == answerText);
  }

  List<QuizItemDraft> _parseLegacyMarkdownDrafts(String text) {
    return text
        .split('---')
        .map((block) => _parseMarkdownDraft(block.trim()))
        .whereType<QuizItemDraft>()
        .toList(growable: false);
  }

  QuizItemDraft? _parseMarkdownDraft(String block) {
    final lines = block
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return null;

    String questionText = '';
    final options = <String>[];

    for (final line in lines) {
      if (_containsAnswerKeyLabel(line)) continue;
      if (line.startsWith('- ') ||
          line.startsWith('* ') ||
          _optionPrefixPattern.hasMatch(line)) {
        options.add(_cleanOptionLine(line));
      } else if (options.isEmpty) {
        if (questionText.isNotEmpty) questionText += '\n';
        questionText += line;
      }
    }

    if (questionText.isEmpty) return null;

    return QuizItemDraft(
      questionText: questionText,
      options: options,
      explanation: 'Extracted from study material.',
      evidence: questionText,
    );
  }

  static final _optionPrefixPattern =
      RegExp(r'^\s*(?:[A-Z]|[0-9]+)[\).\:\-]\s+');
  static final _answerKeyPattern = RegExp(
    r'\b(correct answer|key answer|answer key|kunci jawaban|pembahasan|explanation|solution|answer|jawaban)\b\s*[:：]',
    caseSensitive: false,
  );

  static String _cleanOptionLine(String line) {
    return line
        .replaceFirst(RegExp(r'^\s*[-*]\s+'), '')
        .replaceFirst(_optionPrefixPattern, '')
        .trim();
  }

  static bool _containsAnswerKeyLabel(String text) =>
      _answerKeyPattern.hasMatch(text);

  static bool _hasDuplicateOptions(List<String> options) {
    final seen = <String>{};
    for (final option in options) {
      final normalized =
          option.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
      if (!seen.add(normalized)) return true;
    }
    return false;
  }

  static bool _isWeakOption(String option) {
    final normalized = option.toLowerCase().trim();
    return normalized == 'all of the above' ||
        normalized == 'none of the above' ||
        normalized == 'semua jawaban benar' ||
        normalized == 'semua benar' ||
        normalized == 'tidak ada yang benar';
  }

  static bool _containsAnswerLeak(String questionText, List<String> options) {
    final normalizedQuestion = questionText.toLowerCase();
    for (final option in options) {
      final normalizedOption = option.toLowerCase().trim();
      if (normalizedOption.length >= 12 &&
          normalizedQuestion.contains(normalizedOption)) {
        return true;
      }
    }
    return false;
  }
}

@visibleForTesting
class QuizItemDraft {
  final String questionText;
  final List<String> options;
  final int? correctOptionIndex;
  final String? expectedAnswer;
  final String explanation;
  final String evidence;

  const QuizItemDraft({
    required this.questionText,
    this.options = const [],
    this.correctOptionIndex,
    this.expectedAnswer,
    required this.explanation,
    required this.evidence,
  });

  Question toQuestion(int index) {
    return Question(
      quizId: -1,
      source: QuestionSource.generated,
      type: options.isEmpty
          ? QuestionType.textAnswer
          : QuestionType.multipleChoice,
      questionText: questionText,
      options: options,
      orderIndex: index,
    );
  }
}

@visibleForTesting
class QuizDraftValidation {
  final List<String> issues;

  const QuizDraftValidation(this.issues);

  bool get isValid => issues.isEmpty;
}
