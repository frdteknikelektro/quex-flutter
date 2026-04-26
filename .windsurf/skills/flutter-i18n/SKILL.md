---
name: flutter-i18n
description: Standard Operating Procedure for internationalization (i18n) and localization (l10n) in the Quex Flutter project using flutter_localizations and intl packages. Use this skill when adding multi-language support, externalizing strings, or handling locale-specific formatting.
---

This skill defines the canonical patterns for internationalization in Quex using Flutter's built-in i18n stack: `flutter_localizations` (SDK) + `intl` package + ARB-based code generation.

---

## 1. Project Configuration

### Dependencies (Already in pubspec.yaml)
```yaml
dependencies:
  flutter_localizations:
    sdk: flutter
  intl: ^0.20.2

flutter:
  generate: true  # Enables ARB code generation
```

### l10n.yaml Configuration
Create `l10n.yaml` in project root (if not exists):
```yaml
arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
```

This configures:
- ARB files location: `lib/l10n/`
- English template: `app_en.arb`
- Generated class: `AppLocalizations` in `lib/l10n/app_localizations.dart`

---

## 2. Adding Translations

### Create ARB Files
Place in `lib/l10n/`:

**app_en.arb** (template - English):
```json
{
  "helloWorld": "Hello World!",
  "@helloWorld": {
    "description": "The conventional newborn programmer greeting"
  },
  "welcomeMessage": "Welcome to Quex, {name}!",
  "@welcomeMessage": {
    "description": "Greeting message with user name",
    "placeholders": {
      "name": {
        "type": "String",
        "example": "Alex"
      }
    }
  }
}
```

**app_es.arb** (Spanish translation):
```json
{
  "helloWorld": "¡Hola Mundo!",
  "welcomeMessage": "¡Bienvenido a Quex, {name}!"
}
```

**Note**: Translation files only need the key-value pairs. Metadata (`@key`) is optional in non-template files.

### Generate Code
Run `flutter pub get` or `flutter gen-l10n` to generate `AppLocalizations` class.

---

## 3. MaterialApp Configuration

In `lib/app/app_shell.dart` or main app widget:

```dart
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';

MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  // OR manually specify:
  // localizationsDelegates: [
  //   AppLocalizations.delegate,
  //   GlobalMaterialLocalizations.delegate,
  //   GlobalWidgetsLocalizations.delegate,
  //   GlobalCupertinoLocalizations.delegate,
  // ],
  // supportedLocales: [
  //   Locale('en'),
  //   Locale('es'),
  // ],
  // ...
)
```

**Use `AppLocalizations.localizationsDelegates` and `AppLocalizations.supportedLocales`** — these are auto-generated from your ARB files.

---

## 4. Using Translations in Widgets

```dart
import 'l10n/app_localizations.dart';

Text(AppLocalizations.of(context)!.helloWorld)

// With placeholders
Text(AppLocalizations.of(context)!.welcomeMessage('Alex'))
```

**Pattern**: Always check for null (`!`) since `AppLocalizations.of(context)` can return null if not configured.

---

## 5. Date/Number Formatting with intl

The `intl` package provides locale-aware formatting:

```dart
import 'package:intl/intl.dart';

// Date formatting
final now = DateTime.now();
final formatted = DateFormat.yMMMd(Localizations.localeOf(context).languageCode).format(now);

// Number formatting
final currency = NumberFormat.currency(locale: Localizations.localeOf(context).toString(), symbol: '\$');
final price = currency.format(1234.56);
```

**Use `Localizations.localeOf(context)`** to get the current locale for formatting.

---

## 6. Adding New Languages

1. Create new ARB file: `app_{lang_code}.arb` (e.g., `app_id.arb` for Indonesian)
2. Add translations for all keys from the template
3. Run `flutter gen-l10n`
4. The new locale is automatically added to `AppLocalizations.supportedLocales`

**Supported locales in Quex**: English (en), Spanish (es) — add more as needed.

---

## 7. Locale Override (Testing)

To test a specific locale in a section of the app:

```dart
Localizations.override(
  context: context,
  locale: const Locale('es'),
  child: Builder(
    builder: (context) {
      return Text(AppLocalizations.of(context)!.helloWorld);
    },
  ),
)
```

Useful for previewing translations without changing device locale.

---

## 8. Best Practices

- **Externalize ALL user-facing strings** to ARB files — no hardcoded text in widgets
- **Use descriptive keys** that reflect context (e.g., `profileSettingsTitle` not `title1`)
- **Add metadata** (`@key` with `description`) in the template file for context
- **Use placeholders** for dynamic content instead of string concatenation
- **Keep translations in sync** — when adding keys to template, add to all language files
- **Test RTL layouts** if supporting Arabic/Hebrew (use `Directionality` widget)

---

## 9. Common Patterns

### Pluralization
```json
{
  "itemCount": "{count, plural, =0{No items} =1{One item} other{{count} items}}",
  "@itemCount": {
    "description": "Number of items with plural forms",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  }
}
```

### Gender
```json
{
  "greeting": "{gender, select, male{He is online} female{She is online} other{They are online}}",
  "@greeting": {
    "placeholders": {
      "gender": {
        "type": "String"
      }
    }
  }
}
```

---

## 10. Key Files

| File | Role |
|------|------|
| `pubspec.yaml` | Dependencies and `flutter: generate: true` |
| `l10n.yaml` | ARB configuration (arb-dir, template-arb-file) |
| `lib/l10n/app_en.arb` | English template with metadata |
| `lib/l10n/app_*.arb` | Translation files for other languages |
| `lib/l10n/app_localizations.dart` | Auto-generated `AppLocalizations` class |
| `lib/app/app_shell.dart` | MaterialApp with localizationsDelegates |

---

## Reference Sources

- [Flutter Internationalization Docs](https://docs.flutter.dev/ui/internationalization) — Official guide
- [intl package](https://pub.dev/packages/intl) — Date/number formatting API
- [ARB Format](https://github.com/google/app-resource-bundle) — App Resource Bundle spec
