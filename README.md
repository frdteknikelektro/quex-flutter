# Quex

A local-first AI study companion for kids. No cloud dependency — all AI runs on-device using Google's Gemma 4 models.

Kids create study sessions, add materials (text, images, files), and Quex generates quizzes and provides AI coaching chat. Target: elementary-age students with a playful, kid-friendly UI.

## Features

- **On-Device AI**: Runs Gemma 4 E4B (~3.65GB) or E2B (~2.58GB) locally via LiteRT-LM
- **Multimodal**: Supports text, image, audio, function calling, and thinking mode
- **Profile System**: Netflix-style profile selection with multiple kid profiles
- **Study Sessions**: Create sessions, add materials, take AI-generated quizzes
- **AI Chat**: Persistent coaching chat with context-aware tutoring
- **Local-First**: All data stored in SQLite; works offline

## Requirements

- Flutter 3.41.6 (via FVM)
- Android 6.0+ / iOS 14.0+
- ~4GB free storage (for E4B model variant)

## Setup

### 1. Install Dependencies

```bash
fvm flutter pub get
```

### 2. HuggingFace Token (Optional)

The models (Gemma 4 E4B/E2B from litert-community) are **publicly accessible** and don't require a token. However, you can configure one for higher rate limits.

```bash
# Copy the template
cp config.json.example config.json

# Edit config.json and add your token
{"HUGGINGFACE_TOKEN": "hf_your_token_here"}
```

Get your token at: https://huggingface.co/settings/tokens

## Run

**Without token (default):**
```bash
fvm flutter run
```

**With token:**
```bash
fvm flutter run --dart-define-from-file=config.json
```

## Build

```bash
# Android
fvm flutter build apk --release --dart-define-from-file=config.json
fvm flutter build appbundle --release --dart-define-from-file=config.json

# iOS
fvm flutter build ios --release --dart-define-from-file=config.json
```

## Architecture

| Layer | Technology |
|-------|------------|
| **State** | Riverpod |
| **Routing** | go_router |
| **Database** | SQLite (sqflite) |
| **AI** | flutter_gemma + LiteRT-LM |
| **UI** | Material 3 + custom design tokens |

## Model Variants

Based on device RAM, Quex automatically selects:

| Variant | Size | Requirements | Use Case |
|---------|------|--------------|----------|
| **E4B** | ~3.65GB | 8192+ tokens | High-quality inference |
| **E2B** | ~2.58GB | <8192 tokens | Lower RAM devices |

## Project Structure

```
lib/
├── app/              # Theme, router, shell
├── core/             # State, DB, AI services
│   ├── ai/           # ModelManager, AuthTokenService
│   ├── db/           # DAOs, Database
│   └── state/        # Riverpod providers
├── features/         # Screens by feature
│   ├── chat/
│   ├── home/
│   ├── profile/
│   ├── profile_selection/
│   └── splash/       # Model download
└── widgets/          # Shared UI components
```

## License

MIT
