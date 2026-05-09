# Reference UI Workflow

## Grounding

- Locate the target screen and its owning feature directory.
- Read nearby theme, localization, routing, state, and asset declarations before proposing UI changes.
- Check current worktree status and avoid reverting unrelated user edits.
- Inspect reference image dimensions with `sips -g pixelWidth -g pixelHeight` or equivalent.

## Difference Review

- Compare the current result against the target reference by subsystem: screen frame, background, header, cards, controls, art, spacing, color, typography, state, and responsive behavior.
- State differences concretely: "card height is taller" instead of "card is off".
- Mark user-approved deviations as intentional so they are not "fixed" later.

## Planning Decisions

Lock these before implementation when they materially change the result:

- Fidelity: pixel-close, inspired, or asset-only.
- Avatar/icon strategy: generated art, existing emoji/icon, or hybrid.
- Selection state: persistent active, tap-only, or static mockup match.
- Reference-only controls: functional, visual-only, or omitted.
- Asset split: full background, split decorative layers, or code-drawn shapes.

## Flutter Implementation Guidance

- Use a centered max-width panel when matching phone mockups on tablet/desktop.
- Use `Stack` for decorative layers and put content above with `Positioned.fill` or normal layout.
- Prefer fixed `mainAxisExtent`, `SizedBox`, and bounded asset heights for reference-sensitive cards and grids.
- Keep long text safe with `maxLines`, `overflow`, and stable button/card dimensions.
- Use `LayoutBuilder` for breakpoints, not viewport-scaled font sizes.
- Keep behavior intact unless the user requests product changes: providers, persistence, route destinations, and empty states should remain stable.

## Asset Workflow

- Put temporary crops and generated intermediates under `tmp/imagegen/` or another ignored scratch path.
- For imagegen, crop the relevant part of the reference and label it as a style/reference input.
- Generate distinct assets as separate jobs when they have different composition needs, such as top accents and bottom landscape.
- For transparent PNGs, use a chroma-key background or true transparency path, then verify alpha with `sips -g hasAlpha` and inspect the result.
- Save final app assets under `assets/images/<feature>/` and add that directory to `pubspec.yaml`.

## Validation

- Run `dart format` on touched Dart files.
- Run targeted `flutter analyze <file>` for the modified screen.
- Run `git diff --check` on touched files and asset declarations.
- If feasible, render the screen on phone and tablet dimensions and compare against the reference for spacing, clipping, and text overflow.
