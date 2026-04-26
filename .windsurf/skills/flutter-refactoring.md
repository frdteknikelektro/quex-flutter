---
description: Flutter refactoring patterns - extract widgets, decompose builds, extract constants, and localize strings
triggers:
  - "refactor flutter"
  - "extract widget"
  - "componentize"
  - "decompose build"
  - "extract constant"
  - "localize string"
  - "flutter refactor"
---

# Flutter Refactoring

Common Flutter refactoring patterns to improve code organization, reusability, and maintainability.

---

## Pattern 1: Extract Private Widget to Public Component

Convert private `_WidgetName` classes into reusable, documented public widgets.

### When to Use
- Large screen files with many private widget classes
- Widgets that could be reused across screens
- Need to add configurability to existing widgets

### Steps
1. **Rename and make public**: `_InputBar` → `ChatInputBar`
2. **Add `super.key`** to constructor
3. **Add Dartdoc** explaining purpose
4. **Add configurability** (optional): convert hardcoded values to parameters with defaults
5. **Organize with section headers** group related widgets
6. **Update all references**

### Example
```dart
// BEFORE
class _InputBar extends StatelessWidget {
  const _InputBar({required this.controller});
  
  @override
  Widget build(BuildContext context) {
    return TextField(controller: controller);
  }
}

// AFTER
// ================================================================
// UI WIDGETS - Input
// ================================================================

/// Main chat input bar with text field and send button.
class ChatInputBar extends StatelessWidget {
  const ChatInputBar({
    super.key,
    required this.controller,
  });
  
  final TextEditingController controller;
  
  @override
  Widget build(BuildContext context) {
    return TextField(controller: controller);
  }
}
```

---

## Pattern 2: Decompose Large Build Method

Break down massive `build()` methods into smaller private or public widget methods.

### When to Use
- `build()` method exceeds 50-100 lines
- Deeply nested widget trees (pyramid of doom)
- Repeated widget patterns in the same build

### Steps
1. **Identify logical sections** (header, body, footer, input area, etc.)
2. **Extract to private methods** returning `Widget`
3. **Name descriptively**: `_buildHeader()`, `_buildMessageList()`, `_buildInputArea()`
4. **Pass required parameters** explicitly

### Example
```dart
// BEFORE
@override
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(
      title: Text('Chat'),
      actions: [IconButton(...), IconButton(...)],
    ),
    body: Column(
      children: [
        Expanded(
          child: ListView.builder(
            itemCount: messages.length,
            itemBuilder: (context, index) {
              return ListTile(
                title: Text(messages[index].text),
                subtitle: Text(messages[index].time),
              );
            },
          ),
        ),
        TextField(
          controller: _controller,
          decoration: InputDecoration(
            suffixIcon: IconButton(...),
          ),
        ),
      ],
    ),
  );
}

// AFTER
@override
Widget build(BuildContext context) {
  return Scaffold(
    appBar: _buildAppBar(),
    body: Column(
      children: [
        Expanded(child: _buildMessageList()),
        _buildInputArea(),
      ],
    ),
  );
}

Widget _buildAppBar() {
  return AppBar(
    title: Text('Chat'),
    actions: [IconButton(...), IconButton(...)],
  );
}

Widget _buildMessageList() {
  return ListView.builder(
    itemCount: messages.length,
    itemBuilder: (context, index) => _buildMessageItem(messages[index]),
  );
}

Widget _buildMessageItem(Message msg) {
  return ListTile(
    title: Text(msg.text),
    subtitle: Text(msg.time),
  );
}

Widget _buildInputArea() {
  return TextField(
    controller: _controller,
    decoration: InputDecoration(suffixIcon: IconButton(...)),
  );
}
```

---

## Pattern 3: Extract Constants

Replace magic numbers and strings with named constants.

### When to Use
- Hardcoded numeric values (padding, sizes, durations)
- Repeated strings (route names, asset paths)
- Colors or styles used in multiple places

### Steps
1. **Create a constants file** or class: `lib/core/constants.dart`
2. **Define constants** with descriptive names
3. **Replace inline values** with constant references

### Example
```dart
// constants.dart
class AppConstants {
  // Spacing
  static const double paddingSmall = 8.0;
  static const double paddingMedium = 16.0;
  static const double paddingLarge = 24.0;
  
  // Durations
  static const Duration animationDuration = Duration(milliseconds: 300);
  static const Duration debounceDuration = Duration(milliseconds: 500);
  
  // Sizes
  static const double iconSizeSmall = 16.0;
  static const double iconSizeMedium = 24.0;
  static const double iconSizeLarge = 32.0;
  
  // Asset paths
  static const String logoAsset = 'assets/images/logo.png';
  static const String placeholderAsset = 'assets/images/placeholder.png';
}

// Usage
Padding(
  padding: const EdgeInsets.all(AppConstants.paddingMedium),
  child: Icon(Icons.star, size: AppConstants.iconSizeMedium),
)
```

---

## Pattern 4: Extract Strings for Localization

Move user-facing strings to `.arb` files for internationalization.

### When to Use
- Hardcoded strings in UI (labels, messages, hints)
- App needs multi-language support
- Strings used in multiple places

### Steps
1. **Identify strings** in the target file
2. **Add to `.arb` files** (create keys, add to all locale files)
3. **Regenerate localizations** (`flutter gen-l10n`)
4. **Replace strings** with `AppLocalizations.of(context)!.key`

### Example
```dart
// BEFORE
Text('Hello World')
Text('Send')
Text('Are you sure you want to delete this item?')

// l10n/app_en.arb
{
  "helloWorld": "Hello World",
  "sendButton": "Send",
  "deleteConfirmation": "Are you sure you want to delete this item?"
}

// l10n/app_id.arb
{
  "helloWorld": "Halo Dunia",
  "sendButton": "Kirim",
  "deleteConfirmation": "Apakah Anda yakin ingin menghapus item ini?"
}

// AFTER
final l10n = AppLocalizations.of(context)!;
Text(l10n.helloWorld)
Text(l10n.sendButton)
Text(l10n.deleteConfirmation)
```

---

## Pattern 5: Extract Duplicate Logic to Methods/Functions

Consolidate repeated code patterns into reusable methods.

### When to Use
- Same logic repeated 2+ times
- Complex calculations or formatting
- Common UI patterns

### Example
```dart
// BEFORE - Duplicated date formatting
Text(DateFormat('MMMM d, yyyy').format(message.date))
Text(DateFormat('MMMM d, yyyy').format(event.date))

// AFTER - Extracted method
String formatDate(DateTime date) {
  return DateFormat('MMMM d, yyyy').format(date);
}

Text(formatDate(message.date))
Text(formatDate(event.date))

// OR extension method
extension DateTimeFormatting on DateTime {
  String toDisplayString() => DateFormat('MMMM d, yyyy').format(this);
}

Text(message.date.toDisplayString())
```

---

## Pattern 6: Simplify Conditional Widgets

Replace verbose conditionals with cleaner patterns.

### Before
```dart
if (condition)
  Widget1()
else
  Widget2()

// Or
condition ? Widget1() : Widget2()
```

### After - Using Collection-If
```dart
[
  if (condition) Widget1(),
  if (!condition) Widget2(),
]
```

### After - Using `Visibility` or `AnimatedSwitcher`
```dart
Visibility(
  visible: condition,
  child: Widget1(),
)

// Or for smooth transitions
AnimatedSwitcher(
  duration: Duration(milliseconds: 200),
  child: condition ? Widget1(key: ValueKey('1')) : Widget2(key: ValueKey('2')),
)
```

---

## Quick Checklist

When refactoring any Flutter code:

- [ ] **Extract widgets** > 50 lines into private/public components
- [ ] **Decompose build** methods into logical sections
- [ ] **Extract constants** for magic numbers/strings
- [ ] **Localize strings** for user-facing text
- [ ] **Add documentation** to public APIs
- [ ] **Update all references** after renaming
- [ ] **Test** the refactored code works identically

---

## Best Practices

1. **Refactor incrementally** - one pattern at a time
2. **Keep public API minimal** - expose only what's needed
3. **Name descriptively** - the name should explain the purpose
4. **Maintain behavior** - refactoring shouldn't change functionality
5. **Add tests first** if the code lacks coverage, then refactor
