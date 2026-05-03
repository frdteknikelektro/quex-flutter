# 🦆 Quex

An on-device AI study companion I built for my two kids - because sometimes my wife and I are both working, and they have an exam tomorrow we don't know how to help with.

*The name? My kids came up with it: **Quex** = **Qu**ick **Ex**am.*

## The Problem I Faced

My wife and I both work. Sometimes she does shift work, sometimes I'm racing a deadline. When exam time comes, we want to help our kids - but we're exhausted, or we simply don't understand the material ourselves. We've felt that guilt: our kids stressing about tomorrow's test while we're stuck in a meeting.

I wanted a solution that would let my children focus specifically on the material that will be tested tomorrow - not random practice, not generic lessons, but *their actual worksheets and textbook pages*. NotebookLM can do something like this, but it's built for adults doing research, not kids cramming for an exam. Too many steps, too many buttons, too much complexity.

So I built what I wish existed: a patient tutor that lives on the phone, knows exactly what my kids are studying, and explains it as many times as needed - no WiFi required, no monthly fees, no complicated setup. Snap a photo, get a quiz, start studying.

## What Quex Does

**For elementary-age kids who need to study their own materials:**

- Create a study session for "Science Chapter 3" or "Math Fractions"
- Take a photo of the textbook page or worksheet
- Quex generates a quiz from that specific material
- Get a question wrong? Ask "Why?" and the AI explains
- Works on the car ride to school, at grandma's house with no WiFi, anywhere

Each kid has their own profile. They pick their avatar, their grade level, their study sessions. No mixing up little brother's multiplication with big sister's science project.

## ✨ Features

| What parents/kids see | What's under the hood |
|---|---|
| Netflix-style profile selection for multiple kids | Riverpod state management with persistent session tracking |
| Take photos of worksheets, textbooks, notes | Multimodal Gemma 4 E4B processes images + text together |
| AI generates custom quizzes from uploaded materials | LiteRT-LM inference running locally, no cloud API calls |
| Ask "Why?" and get patient explanations | Persistent Gemma session with conversation context |
| Works on a 5-year-old Android phone without WiFi | 4-bit quantized Gemma 4 (~2.58–3.65GB), SQLite storage |
| No ads, no subscriptions, no data collection | Apache 2.0 open source, on-device only |

## 🧠 How We Use Gemma 4

**Model:** Gemma 4 E4B (~3.65GB) or E2B (~2.58GB) depending on device capabilities  
**Inference:** LiteRT-LM for on-device execution via `flutter_gemma`  
**Quantization:** 4-bit for edge deployment on consumer phones  
**Capabilities leveraged:**
- Multimodal understanding (vision + text) — kids photograph worksheets, AI reads them
- Long context window — maintains conversation history for tutoring continuity
- Native function calling — enables structured quiz generation and answer validation
- Apache 2.0 license — matching our open-source approach

**Why this matters for our use case:** Gemma 4 runs on a mid-range Android phone from 2019 without internet. A family in a rural area with spotty connectivity can download once and have a permanent tutor. A parent working double shifts doesn't need to pay for a subscription their kids outgrow.

## 🚀 Quick Start

```bash
# 1. Clone and enter directory
cd quex-flutter

# 2. Install Flutter dependencies (uses FVM for version pinning)
fvm flutter pub get

# 3. Run on device or emulator
# No API keys needed — models are publicly accessible
fvm flutter run
```

**Requirements:**
- Flutter 3.41.6 (via FVM)
- Android 6.0+ / iOS 14.0+
- ~4GB free storage for E4B model variant

**Optional:** Configure HuggingFace token for higher rate limits during model download:
```bash
cp config.json.example config.json
# Edit config.json with your token
fvm flutter run --dart-define-from-file=config.json
```

## 📁 Repository Structure

```
lib/
├── app/                    # Theme, router, responsive shell
├── core/
│   ├── ai/                 # ModelManager, GemmaInferenceService
│   │   ├── model_manager.dart          # HuggingFace download
│   │   ├── gemma_inference_service.dart # Persistent session handling
│   │   └── download_state.dart         # Download progress state machine
│   ├── db/                 # SQLite with DAO pattern
│   │   ├── database.dart     # 6-table schema
│   │   └── daos.dart         # Data access objects
│   └── state/              # Riverpod providers
├── features/               # Feature-first screen organization
│   ├── chat/               # AI coaching chat
│   ├── home/               # Study sessions list
│   ├── material/           # Upload/view materials
│   ├── profile/            # Active profile management
│   ├── profile_selection/  # Netflix-style profile grid
│   ├── quiz/               # Quiz generation and taking
│   ├── session_detail/     # Session with materials/quizzes
│   └── splash/             # Model download flow
└── widgets/              # Shared UI components
```

**Key architectural patterns:**
- **Persistent Gemma sessions:** Screens acquire service ownership via tokens; sessions persist across messages within a screen
- **Offline-first:** SQLite with WAL mode; all data local, sync optional
- **Responsive:** Navigation adapts from mobile (bottom bar) to tablet/desktop (rail) via `QuexBreakpoints`
- **State management:** `FutureProvider.family` for async data, `NotifierProvider` for complex UI state

## 💡 Why This Matters

It's for my kids, who need help with fractions when I'm in a meeting. It's for my wife, who works shift work and shouldn't feel guilty about not being there for homework time. It's for families who can't afford tutoring subscriptions that cost more than their phone.

Gemma 4 makes this possible because it runs on the hardware people already have. No cloud means no data bills, no privacy concerns, no "service unavailable" when you need it most. Just a quiet, patient tutor that explains things as many times as your kid needs.

Not replacing parents. Just filling the gaps when we can't be there.

---

**Built for the Gemma 4 Good Hackathon** — Kaggle × Google DeepMind  
*Competition: [kaggle.com/competitions/gemma-4-good-hackathon](https://www.kaggle.com/competitions/gemma-4-good-hackathon)*

## 📄 License

Apache 2.0 — See [LICENSE](LICENSE)
