---
name: flutter-material-design
description: Create distinctive, production-grade Flutter interfaces using Material 3 design principles. Use this skill when the user asks to build Flutter screens, widgets, or UI components (examples include screens, cards, dialogs, forms, navigation, or when styling/beautifying any Flutter UI). Generates creative, polished Dart code with exceptional Material 3 aesthetics that avoids generic design.
license: Complete terms in LICENSE.txt
---

This skill guides creation of distinctive, production-grade Flutter interfaces using Material 3 design principles that avoid generic "AI slop" aesthetics. Implement real working Dart code with exceptional attention to aesthetic details and creative choices.

The user provides Flutter UI requirements: a screen, widget, component, or interface to build. They may include context about the purpose, audience, or technical constraints.

## Design Thinking

Before coding, understand the context and commit to a BOLD aesthetic direction:
- **Purpose**: What problem does this interface solve? Who uses it?
- **Tone**: Pick an extreme: brutally minimal, maximalist chaos, retro-futuristic, organic/natural, luxury/refined, playful/toy-like, editorial/magazine, brutalist/raw, art deco/geometric, soft/pastel, industrial/utilitarian, etc. There are so many flavors to choose from. Use these for inspiration but design one that is true to the aesthetic direction.
- **Constraints**: Technical requirements (framework, performance, accessibility).
- **Differentiation**: What makes this UNFORGETTABLE? What's the one thing someone will remember?

**CRITICAL**: Choose a clear conceptual direction and execute it with precision. Bold maximalism and refined minimalism both work - the key is intentionality, not intensity.

**Material 3 Design Considerations**:
- **Dynamic Color**: Use `ColorScheme.fromSeed()` for cohesive, generated color palettes that adapt to light/dark modes
- **Surface Hierarchy**: Leverage Material 3's surface containers (`surfaceContainerLow`, `surfaceContainer`, `surfaceContainerHigh`, `surfaceContainerHighest`) for elevation without shadows
- **Shape System**: Apply consistent corner radii through shape tokens (small, medium, large, full)
- **Typography Scale**: Use Material 3's type scale (`displayLarge` through `labelSmall`) with Google Fonts for distinctive character

Then implement working Flutter code that is:
- Production-grade and functional
- Visually striking and memorable
- Cohesive with a clear aesthetic point-of-view
- Meticulously refined in every detail

## Flutter Material 3 Aesthetics Guidelines

Focus on:

- **Typography**: Use the `google_fonts` package for distinctive typefaces. Apply Material 3's type scale consistently: `displayLarge/Small` for hero text, `headlineLarge/Small` for section titles, `titleLarge/Medium` for card headers, `bodyLarge/Medium` for content, `labelLarge` for buttons and chips. Avoid using the same weight everywhere—vary between w400 (normal), w600 (semi-bold), and w800 (extra-bold) for hierarchy.

- **Color & Theme**: Commit to a cohesive aesthetic using `ColorScheme.fromSeed()` for dynamic color generation. Use `Theme.of(context).colorScheme` consistently throughout. Material 3's tonal palette provides: `primary/secondary/tertiary` for actions, `surface` and `surfaceContainer*` levels for backgrounds, `outline/outlineVariant` for borders. Add brand accent colors via `ThemeExtension` for distinctive personality.

- **Motion**: Use Flutter's animation system for polished interactions. `AnimatedContainer` for smooth property changes, `AnimatedOpacity` for fades, `Hero` for shared element transitions. For page transitions, use `PageRouteBuilder` with custom curves. Apply `AnimatedList` or staggered animations for content reveals. Prefer `Curves.easeOutCubic` and `Curves.fastOutSlowIn` for natural motion.

- **Spatial Composition**: Leverage Flutter's layout widgets creatively. Use `Row`/`Column` with `Spacer`, `Expanded`, `Flexible` for fluid layouts. `Stack` with `Positioned` for overlapping elements. `GridView` with custom `SliverGridDelegate` for unexpected grid patterns. Apply generous padding using consistent spacing tokens (4, 8, 16, 24, 32). Use `LayoutBuilder` and `MediaQuery` for responsive breakpoints.

- **Components & Details**: Extend Material 3 components rather than reinventing:
  - **Cards**: Use `Card` with custom `shape` (rounded corners 16-24dp), `color` from surface containers, subtle borders with `outlineVariant`
  - **Buttons**: `FilledButton` for primary actions, `OutlinedButton` for secondary, `TextButton` for tertiary. Consistent 48-52dp height, 16dp+ corner radius
  - **Inputs**: `TextField` with filled decoration, rounded borders (18dp), subtle background from `surfaceContainerHighest`
  - **Chips**: `ChoiceChip`, `FilterChip` with consistent pill shapes (full radius) for toggles
  - **Navigation**: `NavigationBar` with indicator animations, `NavigationRail` for tablet/desktop
  - **Dialogs**: `AlertDialog` with rounded corners (28dp), consistent padding

NEVER use generic AI-generated aesthetics like default Material 2 blue themes, inconsistent border radii across components, default Roboto without consideration, or cookie-cutter designs that lack context-specific character.

Interpret creatively within Material 3's system. Vary between light and dark themes, different seed colors for dynamic palettes, different Google Fonts pairings. Create custom widget compositions that extend Material components with your own design language.

**IMPORTANT**: Match implementation complexity to the aesthetic vision. Maximalist designs need elaborate `CustomPainter` work, `ShaderMask` effects, and complex animations. Minimalist designs need restraint, precise spacing, and careful attention to Material 3's surface hierarchy and typography. Elegance comes from executing the vision well within the design system.

Remember: Claude is capable of extraordinary creative work. Don't hold back, show what can truly be created when thinking outside the box and committing fully to a distinctive vision.

## Flutter Implementation Patterns

### Theme Setup
```dart
ThemeData _theme(Brightness brightness) {
  final base = ThemeData(brightness: brightness, useMaterial3: true);
  final colorScheme = ColorScheme.fromSeed(
    seedColor: brandColor,
    brightness: brightness,
  );
  return base.copyWith(
    colorScheme: colorScheme,
    textTheme: GoogleFonts.nunitoSansTextTheme(base.textTheme),
    // Component themes for consistency
    cardTheme: CardThemeData(
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
  );
}
```

### Widget Structure
- Extract reusable components as `StatelessWidget` with `const` constructors
- Use `ConsumerWidget` (Riverpod) or `BlocBuilder` for state-dependent UI
- Access theme via `final scheme = Theme.of(context).colorScheme;`
- Apply consistent spacing with `const SizedBox(height: 16)` tokens

### Responsive Design
```dart
final isCompact = MediaQuery.of(context).size.width < 600;
return isCompact ? _MobileLayout() : _DesktopLayout();
```

### State Management UI
- Show loading with `CircularProgressIndicator()` centered
- Handle errors with user-friendly messages and retry actions
- Use `AnimatedSwitcher` for smooth state transitions
