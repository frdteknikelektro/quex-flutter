# Quex Technical Notes

This document is the implementation appendix for Quex. The README is the judge-facing pitch; this file explains how the app is built, where Gemma 4 is used, and what reliability limits are known.

## 🏗️ System Overview

Quex is a local-first study companion for elementary-age kids. The core loop is:

1. Create or open a child profile.
2. Create a study session for a subject or chapter.
3. Add study material as text, photos, or documents.
4. Generate a quiz from that material.
5. Open a question and use tutor chat to explain mistakes.
6. Persist the session locally so the history stays on device.

The app is built with Flutter, Riverpod, `go_router`, `sqflite`, and `flutter_gemma`.

## 📱 Runtime Flow

### App flow

- Splash screen handles model download and readiness state.
- Profile selection gates access to the main app.
- Home shows recent study sessions.
- Session detail is the hub for materials, quizzes, and tutoring.
- Quiz and chat flows are separate screens with their own prompts and persistence paths.

### Data flow

- Study data is stored in SQLite.
- Lightweight state such as active profile and model state is stored in SharedPreferences.
- AI interactions run on device through Gemma 4 via LiteRT-LM.

## 💾 Persistence Model

The main SQLite schema includes:

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

## 🧠 AI Pipeline

### Model selection and download

`ModelManager` selects between Gemma 4 E4B and E2B based on available device memory.

- E4B is selected when the device can support the target token budget.
- E2B is used as the lower-memory fallback.
- Both models use LiteRT-LM format.
- The first-run model download is large: about 3.65 GB for E4B and 2.58 GB for E2B.

### Material preparation

`MaterialPreprocessor` converts stored study materials into a multimodal-ready form:

- Text materials become plain text chunks.
- Photo materials are reloaded as image bytes.
- Document materials are skipped in the current preprocessor path.

The app can assemble multiple stored images into model context, though the underlying multi-image path still needs improvement for production reliability.

### Quiz generation

`QuizGenerationService` uses a staged workflow:

1. Extract existing questions or useful candidate material.
2. Review extracted questions and identify missing topic coverage.
3. Generate final multiple-choice quiz drafts.
4. Parse and validate drafts before storing `Question` rows.

The parser is intentionally defensive because model output can be messy. It rejects malformed questions, duplicate options, weak options, leaked answer labels, and missing correct-answer metadata.

### Tutor chat

`QuestionChatService` wraps the question tutor experience. It:

- Prewarms a session when possible.
- Injects study materials once.
- Keeps the active quiz question in context.
- Uses short, child-friendly tutor prompts.
- Keeps question chat separate from broader study coaching.

`GemmaChatService` is the lower-level wrapper around `flutter_gemma` chat sessions. It handles session creation, streaming text, thinking tokens, image/audio support, and function-call buffering.

## 🔒 Offline and Privacy Behavior

Quex is local-first after model setup:

- Study data remains in SQLite on the device.
- Model inference runs locally through Gemma 4 LiteRT-LM.
- The app does not require a hosted LLM API for the core study loop.
- Network access is needed for model download and optional setup, not for ordinary post-download tutoring.

## 📊 Current Strengths

- The product loop is focused: photo → quiz → feedback → explanation.
- Gemma 4 E2B/E4B is used in the actual runtime path.
- Vision is useful for photographed worksheets and textbook pages.
- Indonesian and English localization make the app fit the target audience.
- Persistent sessions make tutoring feel more natural than one-shot prompting.
- Local persistence makes the submission credible as an offline-first product prototype.

## ⚠️ Known Limitations

- First-run setup requires a multi-GB model download.
- LiteRT-LM currently does not expose a visual token budget setting.
- `flutter_gemma` still needs a better multi-image upload path; related upstream work is tracked in [DenisovAV/flutter_gemma#262](https://github.com/DenisovAV/flutter_gemma/pull/262).
- Thinking mode is hard to steer consistently for short child-friendly responses.
- Tool calling becomes unreliable in long-context sessions and can corrupt the output stream.
- Document materials are not fully included in the current `MaterialPreprocessor` path.

## 🧪 Tests and Checks

Run the standard checks before submission:

```bash
fvm flutter analyze
fvm flutter test
```

The most submission-relevant test areas are:

- Image normalization for worksheet photos.
- Quiz generation parsing and validation.
- Gemma chat stream handling.
- Session detail UI behavior.
- Processing modal and memory game UI stability.

## 📂 Where to Look

- `lib/core/ai/model_manager.dart`
- `lib/core/ai/gemma_chat_service.dart`
- `lib/core/ai/question_chat_service.dart`
- `lib/core/ai/quiz_generation_service.dart`
- `lib/core/ai/material_preprocessor.dart`
- `lib/core/db/database.dart`
- `lib/core/db/daos.dart`
- `lib/app/router.dart`
