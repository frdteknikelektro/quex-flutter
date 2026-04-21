# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Quex** — local-first AI study companion for kids. No cloud dependency; all AI runs on-device. Kids create study sessions, add materials (text, images, files), Quex generates quizzes and provides AI coaching chat. Runs Gemma 4 E4B locally (~3.65GB model) with rule-based fallback when model unavailable. Target: elementary-age students. Playful tone, kid-friendly UI.

Core flow: splash (model download) → profile selection → home → sessions with materials/quizzes/chat.

## Build & Run Commands

```bash
fvm flutter pub get          # install deps (FVM pinned to Flutter 3.41.6)
fvm flutter run              # run app
fvm flutter analyze          # lint
fvm flutter test             # run tests (currently minimal: one smoke test)
dart run build_runner build  # generates .g.dart for riverpod_generator (unused currently)
```

## Architecture

**State management**: Riverpod (`flutter_riverpod`). All providers in `lib/core/state/app_state.dart`. Pattern: `FutureProvider.family` for data fetching, `StateProvider` for UI state, `NotifierProvider` for complex state. DAOs instantiated directly inside providers (no DI container).

**Routing**: `go_router` (v14) in `lib/app/router.dart`. Flat route list with path parameters. Redirect guard enforces: splash → model download → profile selection → home. `_AppShell` uses `IndexedStack` with `NavigationBar`/`NavigationRail` (adaptive via `QuexBreakpoints`).

**Data layer**: Raw SQLite via `sqflite`. Single DB class in `lib/core/db/database.dart` (6 tables, v1 schema, WAL mode, FK on). 6 DAOs in `lib/core/db/daos.dart`. Models in `lib/core/models/models.dart` with hand-written `toMap()`/`fromMap()`/`copyWith()` — no freezed, no json_serializable.

**AI layer**: Dual-mode. `QuexAi` (static facade, rule-based fallback) + `GemmaInferenceService` (on-device Gemma 4 E4B via `flutter_gemma`). `ModelManager` handles model download from HuggingFace. `ModelDownloadNotifier` is the Riverpod state machine for download lifecycle. **Important**: `GemmaInferenceService` uses persistent session pattern — call `initQuestionTutorSession()` or `initCoachSession()` once per screen, then `sendQuestionTutorMessage()` or `sendCoachMessage()` for each user message. Do NOT create new session per message.

**Aggregation**: `SessionBundle` and `QuizBundle` compose related entities for screen consumption.

## Design System

Defined in `lib/app/theme.dart`:
- Material 3 with hand-tuned `ColorScheme` (not `fromSeed`). Brand colors: `primaryBlue` (#4A90E2), `warmRed` (#FF6B6B), `amber` (#FFB347)
- `QuexColors` ThemeExtension for brand accents: `Theme.of(context).extension<QuexColors>()`
- Typography: Nunito Sans via `google_fonts`
- Spacing tokens: `Sp.xs/sm/md/lg/xl` + `Sp.edge`/`Sp.page` EdgeInsets
- Border radius tokens: `Br.sm/md/lg/full`
- Responsive: `QuexBreakpoints.tablet` (840), `QuexBreakpoints.desktop` (1200)
- Component themes: Card (bordered, 24r, no elevation), Buttons (52h, 16r), Input (filled, 18r)

## Key Patterns

- Feature screens in `lib/features/<name>/` take IDs as constructor params, fetch data via Riverpod providers
- Shared widgets in `lib/widgets/quex_ui.dart`: `QuexPanel`, `QuexSectionHeader`, `QuexEmptyState`, `QuexMetricCard`, `QuexAvatar`, `QuexTonePill`
- All screens are `ConsumerWidget` or `ConsumerStatefulWidget` (Riverpod)
- Route constants in `Routes` class, navigation via `context.go()`/`context.push()`
- Default profiles seeded on DB creation: "Raina" (grade 3), "Kindi" (grade 2)
- `activeProfileId` persisted in `SharedPreferences`, loaded on startup
- **Gemma ownership token system**: Screens acquire service via `QuexAi.acquireGemmaService(token)`. If another screen takes ownership, previous session is invalidated. Check `service.hasActiveSession` before sending.
