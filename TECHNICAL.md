# Quex Technical Notes

This document is the implementation appendix for Quex. The README is the judge-facing pitch; this file explains how the app is built, what is working well, and where the current Gemma 4 integration still has rough edges.

## System overview

Quex is a local-first study companion for elementary-age kids. The core loop is:

1. Create or open a child profile.
2. Create a study session for a subject or chapter.
3. Add study material as text, photos, or documents.
4. Generate a quiz from that material.
5. Open a question and use the tutor chat to explain mistakes.
6. Persist the session locally so the history stays on-device.

The app is built with Flutter, Riverpod, `go_router`, `sqflite`, and `flutter_gemma`.

## Runtime architecture

### App flow

- Splash screen handles model download and readiness state.
- Profile selection gates access to the main app.
- Home shows recent study sessions.
- Session detail is the hub for materials, quizzes, and tutoring.
- Quiz and chat flows are separate screens with their own AI prompts.

### Data flow

- Study data is stored in SQLite.
- Lightweight state such as active profile and model state is stored in SharedPreferences.
- AI interactions run on-device through Gemma 4 via LiteRT-LM.

## Persistence model

The main SQLite schema currently includes:

- `profiles`
- `sessions`
- `materials`
- `quizzes`
- `questions`
- `question_messages`
- `chat_messages`

The schema is managed by `QuexDatabase` and accessed through DAOs in `lib/core/db/daos.dart`.

Notable behavior:

- Foreign keys are enabled.
- WAL mode is enabled.
- Profile deletion cascades to sessions, materials, quizzes, questions, and chat history.
- Questions and chat messages are stored separately so quiz review and free-form coaching can be handled independently.

## AI pipeline

### Model selection and download

`ModelManager` selects between Gemma 4 E4B and E2B based on available device memory. The app downloads the selected LiteRT-LM model from Hugging Face and marks it ready once installed.

### Material preparation

`MaterialPreprocessor` converts stored study materials into a multimodal-ready form:

- text materials become plain text chunks
- photo materials are reloaded as image bytes
- documents are skipped in the current preprocessor path

This means the app can already assemble multiple stored images into a single multimodal context, even though the underlying library support still needs to be strengthened for a cleaner upload path.

### Quiz generation

`QuizGenerationService` uses a two-session workflow:

- Session 1 extracts or drafts candidate questions from the materials.
- Session 2 turns that draft into a final quiz.

The parser is intentionally defensive because LLM output can be messy. It validates drafts before converting them into stored `Question` rows.

### Tutor chat

`QuestionChatService` wraps the question tutor experience. It:

- prewarms a session when possible
- injects study materials once
- keeps a question context active for the turn
- uses the `evaluate_understanding` tool to score correct answers

`GemmaChatService` is the lower-level wrapper around `flutter_gemma` chat sessions.

## What works well today

From the current product and code, these are the strongest parts of the experience:

- Voice input modal is responsive and pleasant to use.
- Multilanguage support is solid enough to make the app usable in Indonesian and English.
- Vision is strong for the intended study workflow.
- Offline-first behavior is credible because the app does not depend on a cloud API for core tutoring.
- The app can use the same local model for quiz generation and explanation.

## Current Gemma 4 feedback

These are the main integration issues we have observed while building Quex. They are useful feedback for improving Gemma 4 and the Flutter integration layer:

- LiteRT-LM currently does not expose a visual token budget setting. That makes detailed image workflows harder to tune when a page has a lot of visual density.
- `flutter_gemma` still needs a better multi-image upload path. A more complete upstream fix is tracked in [DenisovAV/flutter_gemma#262](https://github.com/DenisovAV/flutter_gemma/pull/262), and this project already contributed to that work.
- Thinking mode in Gemma 4 is still hard to steer consistently for this tutoring use case.
- Tool calling becomes unreliable in long-context sessions and can corrupt the output stream.

These are not deal-breakers for Quex, but they are the main gaps that affect reliability in production tutoring flows.

## Why Gemma 4 still fits Quex

Despite the rough edges above, Gemma 4 is still a strong fit for this app because:

- Vision quality is good for worksheets, textbook pages, and photographed study materials.
- Voice and language support are good for kid-friendly tutoring.
- The model is responsive enough for an interactive study loop.
- The on-device story matters more than raw benchmark performance in this product category.

Quex is less about abstract model capability and more about whether a child can take a picture, get a quiz, hear an explanation, and keep going without internet.

## Where to look in the code

- `lib/core/ai/model_manager.dart`
- `lib/core/ai/gemma_chat_service.dart`
- `lib/core/ai/question_chat_service.dart`
- `lib/core/ai/quiz_generation_service.dart`
- `lib/core/ai/material_preprocessor.dart`
- `lib/core/db/database.dart`
- `lib/core/db/daos.dart`
- `lib/app/router.dart`
