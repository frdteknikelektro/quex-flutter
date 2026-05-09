---
name: flutter-reference-ui
description: Redesign and review Flutter screens from visual references, screenshots, or mockups. Use when Codex needs to compare a current Flutter UI against a target image, list visual differences, plan or implement reference-matching layout changes, generate or crop decorative bitmap assets, register assets in pubspec.yaml, or validate a Flutter UI against screenshot/reference fidelity.
---

# Flutter Reference UI

Use this skill to make Flutter UI work traceable to a visual reference instead of relying on vague "make it nicer" judgment.

## Workflow

1. Inspect the target Flutter screen, adjacent widgets, app theme, localization, existing assets, and routing/state behavior before changing code.
2. Inspect each supplied reference image: dimensions, relevant crop area, visual hierarchy, spacing, typography, color, card geometry, and decorative assets.
3. If reviewing, list concrete visual differences first. Separate intentional deviations from defects.
4. Ask the user to lock high-impact deviations that are product choices: exact fidelity, avatar/icon style, persistent vs transient states, asset generation scope, and whether reference-only UI elements should become functional.
5. Prefer local app patterns, theme tokens, providers, and existing routes unless the reference explicitly requires a deviation.
6. For bitmap art, use imagegen or deterministic cropping/post-processing as appropriate. Save project-bound assets under the repo asset tree and register them in `pubspec.yaml`.
7. Implement with stable dimensions: max-width wrappers, `LayoutBuilder`, `Stack` decoration layers, fixed card metrics where reference fidelity matters, and responsive constraints for phone/tablet.
8. Validate with `dart format`, targeted `flutter analyze`, `git diff --check`, and screenshot/manual layout checks when the app can be rendered.

## References

- Read `references/reference-ui-workflow.md` when the task involves matching a Flutter screen to a screenshot/mockup or when asset generation/cropping is needed.

## Bundled Assets

- `assets/design.png` is the canonical Quex design board reference.
- For the profile-selection screen in that board, the useful crop is approximately `x=386, y=27, w=340, h=651`.
