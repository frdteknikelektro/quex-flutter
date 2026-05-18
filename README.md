# Quex

**Quex is a local-first AI study companion for kids.** It turns a photo of a worksheet, textbook page, or notes into a quiz, then explains mistakes in plain language with on-device Gemma 4.

Built for [The Gemma 4 Good Hackathon](https://www.kaggle.com/competitions/gemma-4-good-hackathon/overview), targeting **Main Track + Future of Education + LiteRT / AI Edge**.

## 🎬 Demo Video

[![Quex - AI Study companions for kids](https://i.ytimg.com/vi/XkzYFKY4NgM/hqdefault.jpg)](https://www.youtube.com/watch?v=XkzYFKY4NgM)

Watch: [Quex - AI Study companions for kids](https://www.youtube.com/watch?v=XkzYFKY4NgM)  
Duration: **2:50**

The video opens with the Indonesian home-study gap, then shows Quex running on a tablet with Gemma 4 E2B/E4B, child profiles, quiz practice, wrong/correct feedback, and parent-child study context.

## 📱 APK Demo

Download the Android prototype APK:

[Quex APK on Google Drive](https://drive.google.com/file/d/1FwWAoeTvO0FAUn7hI_Ax-rMta77uOAi0/view?usp=drive_link)

Judge notes:

- First launch downloads a Gemma 4 LiteRT-LM model.
- Gemma 4 E2B is about **2.58 GB**.
- Gemma 4 E4B is about **3.65 GB**.
- After the model is downloaded, the core quiz and tutoring flow runs locally on device.

## 🖼️ Screenshots

Screenshots live in `docs/screenshot/`.

| | | |
|---|---|---|
| ![Quex screenshot 1](docs/screenshot/screenshot-01.jpeg) | ![Quex screenshot 2](docs/screenshot/screenshot-02.jpeg) | ![Quex screenshot 3](docs/screenshot/screenshot-03.jpeg) |
| ![Quex screenshot 4](docs/screenshot/screenshot-04.jpeg) | ![Quex screenshot 5](docs/screenshot/screenshot-05.jpeg) | ![Quex screenshot 6](docs/screenshot/screenshot-06.jpeg) |
| ![Quex screenshot 7](docs/screenshot/screenshot-07.jpeg) | ![Quex screenshot 8](docs/screenshot/screenshot-08.jpeg) | ![Quex screenshot 9](docs/screenshot/screenshot-09.jpeg) |

## 🌍 Problem

In many homes, the hardest part of studying is not the lesson itself. It is getting timely help when a child gets stuck.

Two numbers define the gap:

- **28%** of Indonesian students had problems at least once a week finding someone who could help them with schoolwork during remote learning. Source: [OECD PISA 2022 Indonesia country note](https://www.oecd.org/en/publications/pisa-2022-results-volume-i-and-ii-country-notes_ed6fbcc5-en/indonesia_c2e1ae0e-en.html).
- **53.8%** of surveyed Indonesian parents cited work demands as the main reason they could not accompany children studying at home. Source: [Konde / The Conversation Indonesia survey coverage](https://www.konde.co/2020/09/survey-beban-pendampingan-belajar-anak/).

Quex is built for that ordinary moment: the child already has the worksheet, but the parent is busy and the internet may not be reliable.

## 👨‍👩‍👧 Who It Helps

Quex is designed for Indonesian elementary families:

- Children studying from printed worksheets, textbook pages, or notes.
- Parents who want to help but cannot always sit beside the child.
- Homes where connectivity, privacy, or device sharing makes cloud tutoring fragile.

This is not a broad "AI tutor for everyone." It is offline worksheet-to-practice help for kids at home.

## ✨ What Quex Does

- Create a child profile.
- Create a study session for a subject, chapter, or worksheet.
- Add material as text, photos, or files.
- Generate a multiple-choice quiz from that exact material.
- Let the child answer, see feedback, and retry.
- Open a tutor chat for short, kid-friendly explanations.
- Keep study history locally.

## 🧠 Why Gemma 4

Quex maps directly to Gemma 4 edge capabilities:

- **Multimodal input:** children can photograph real pages instead of typing everything out.
- **On-device inference:** quiz generation and explanations run without a cloud API after model setup.
- **Edge variants:** the app selects Gemma 4 E2B or E4B based on device memory.
- **Persistent sessions:** tutoring uses ongoing context rather than isolated one-shot prompts.
- **Structured behavior:** the quiz pipeline validates model output before storing questions.

## 🔒 Offline & Privacy

Quex is local-first:

- Study sessions, materials, quizzes, questions, and chat history are stored in SQLite.
- Lightweight app state is stored in SharedPreferences.
- Core tutoring does not require sending a child’s worksheet to a hosted LLM API.
- The model download requires connectivity once; the study loop is designed to work offline afterward.

## 🏗️ Architecture

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

Core technology:

- Flutter 3.41.6 via FVM
- Riverpod
- go_router
- sqflite
- flutter_gemma
- Gemma 4 E2B/E4B LiteRT-LM

## 📊 Proof Points

- Public demo video: [YouTube](https://www.youtube.com/watch?v=XkzYFKY4NgM)
- Testable APK: [Google Drive](https://drive.google.com/file/d/1FwWAoeTvO0FAUn7hI_Ax-rMta77uOAi0/view?usp=drive_link)
- Public source repository: [GitHub](https://github.com/frdteknikelektro/quex-flutter)
- On-device Gemma 4 E2B/E4B model selection
- Local SQLite persistence
- Persistent tutoring sessions
- Multimodal material path for photos and text

## 🚀 Quick Start

```bash
cd quex-flutter
fvm flutter pub get
fvm flutter run
```

Optional Hugging Face token setup:

```bash
cp config.json.example config.json
# Add your token to config.json
fvm flutter run --dart-define-from-file=config.json
```

## 🧪 Tests

```bash
fvm flutter analyze
fvm flutter test
```

## ⚠️ Limitations

- First-run setup requires a multi-GB Gemma 4 model download.
- Dense worksheet photos can still be challenging because LiteRT-LM does not expose a visual token budget setting.
- Multi-image workflows depend on the current `flutter_gemma` upload path.
- Thinking mode and long-context tool calling are still rough edges for this tutoring workflow.

## 📚 More Detail

- [WRITEUP.md](WRITEUP.md) is the Kaggle writeup draft.
- [TECHNICAL.md](TECHNICAL.md) is the implementation appendix.

## 📄 License

Apache 2.0. See [LICENSE](LICENSE).
