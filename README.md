# Quex

Quex is a local-first AI study companion for kids. It turns a photo of a worksheet, textbook page, or notes into a quiz, then explains mistakes in plain language without needing WiFi or a cloud API.

Built for the Gemma 4 Good Hackathon.

## Demo video

[Placeholder](#)

## Why this project exists

Parents are often unavailable when homework turns into exam prep. They are busy, tired, or may not remember the topic well enough to help right away.

Quex fills that gap:

- A child studies from the exact material they already have.
- The app creates practice questions from that material.
- The child gets explanations, hints, and retries on device.
- Everything stays local, so it still works offline.

Two numbers show why the project matters:

- 28% of Indonesian students can't find anyone to help them with schoolwork at home.
- 53.8% of Indonesian parents couldn't accompany their children's study time because of work.

## Proof points

- Runs on-device with Gemma 4 E4B or E2B in LiteRT-LM format.
- Selects the model variant based on available device memory.
- Persists study data locally with SQLite.
- Uses persistent tutoring sessions instead of one-shot prompts.
- Keeps the core study flow usable when connectivity is poor or unavailable.

## What Quex does

- Create a study session for a subject, chapter, or worksheet.
- Take a photo of a textbook page or worksheet.
- Generate a quiz from that material.
- Ask follow-up questions like "Why?" or "Help me understand."
- Keep a separate profile for each child.
- Store study history locally in SQLite.

## Why it is a strong Gemma 4 fit

Quex is built around capabilities that map directly to Gemma 4:

- Multimodal input: children can photograph real pages instead of typing everything out.
- On-device inference: quizzes and explanations run locally.
- Persistent tutoring: the app keeps session context across turns.
- Function calling: the tutor flow can produce structured quiz and evaluation behavior.
- Offline-first design: useful in homes with poor connectivity or shared devices.

## Demo flow

The current product story is intentionally simple:

1. A parent or child opens Quex.
2. A study session is created for the subject or chapter.
3. The child photographs the page.
4. Quex generates a quiz from the uploaded material.
5. The child answers a question.
6. If they are wrong, Quex explains the concept again.
7. The child retries until it clicks.

That flow is the core submission. It is more convincing than adding many unrelated features.

## Key features

- Profile-based study sessions for multiple kids
- Text, image, and file material support
- Quiz generation from the exact source material
- Streaming chat for tutoring and explanations
- Local persistence with SQLite
- Adaptive navigation for mobile and larger screens
- On-device Gemma 4 model download and selection

## Visuals

These are the existing repo images available right now. Replace them with real app screenshots once you capture them from the current build.

![Quex duck mascot](assets/images/splash/duck_mascot.png)
![Quex splash accents](assets/images/splash/sky_accents.png)
![Profile selection art](assets/images/profile_selection/profile_selection_top_accents.png)

## How it works

### AI layer

- Gemma 4 E4B or E2B is downloaded from Hugging Face in LiteRT-LM format.
- The app selects the best variant based on available device memory.
- `flutter_gemma` provides on-device inference.
- The tutor and coach flows use persistent sessions rather than one-shot prompts.

### Storage layer

- Study sessions, profiles, materials, and quiz state are stored locally in SQLite.
- Shared preferences keep lightweight app state such as the active profile and model status.

### App structure

```
lib/
├── app/                    # Theme, router, responsive shell
├── core/
│   ├── ai/                 # ModelManager, chat services, prompts, download state
│   ├── db/                 # SQLite schema and DAOs
│   └── state/              # Riverpod providers
├── features/
│   ├── chat/               # Study coach chat
│   ├── home/               # Study sessions list
│   ├── material/           # Upload and view materials
│   ├── profile/            # Active profile management
│   ├── profile_selection/  # Kid profile picker
│   ├── quiz/               # Quiz generation and quiz flow
│   ├── session_detail/     # Session view with materials and quizzes
│   └── splash/             # Model download flow
└── widgets/                # Shared UI components
```

## Technology

- Flutter 3.41.6 via FVM
- Riverpod for state management
- go_router for navigation
- sqflite for local persistence
- flutter_gemma for on-device Gemma 4 inference
- Material 3 with a custom theme

## Requirements

- Flutter 3.41.6
- Android 6.0+ or iOS 14.0+
- Enough free storage for the selected model variant

Model sizes:

- Gemma 4 E4B: about 3.65 GB
- Gemma 4 E2B: about 2.58 GB

## Quick start

```bash
# Clone and enter the repo
cd quex-flutter

# Install dependencies
fvm flutter pub get

# Run the app
fvm flutter run
```

Optional Hugging Face token setup:

```bash
cp config.json.example config.json
# Add your token to config.json
fvm flutter run --dart-define-from-file=config.json
```

## Design notes

The product is designed for elementary-age kids:

- Simple profile selection
- Short prompts and simple explanations
- Kid-friendly interaction patterns
- No ads, no subscription, no cloud dependency

The pitch is not "an AI chatbot for education." It is "a quiet tutor that helps a child study the exact page they already have, even when the internet is unavailable."

## Repository structure

For implementation guidance and build notes, see [TECHNICAL.md](TECHNICAL.md). For the Kaggle submission draft, see [WRITEUP.md](WRITEUP.md).

## License

Apache 2.0. See [LICENSE](LICENSE).
