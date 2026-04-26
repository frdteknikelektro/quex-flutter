import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'language_state.g.dart';

const _languagePreferenceKey = 'app_language';

@riverpod
class LanguageNotifier extends _$LanguageNotifier {
  @override
  String? build() {
    _loadLanguagePreference();
    return null; // null = auto-detect
  }

  Future<void> _loadLanguagePreference() async {
    final prefs = await SharedPreferences.getInstance();
    final savedLanguage = prefs.getString(_languagePreferenceKey);
    if (savedLanguage != null) {
      state = savedLanguage;
    }
  }

  Future<void> setLanguage(String? languageCode) async {
    state = languageCode;
    final prefs = await SharedPreferences.getInstance();
    if (languageCode == null) {
      await prefs.remove(_languagePreferenceKey);
    } else {
      await prefs.setString(_languagePreferenceKey, languageCode);
    }
  }
}

@riverpod
Locale locale(LocaleRef ref) {
  final languageCode = ref.watch(languageNotifierProvider);
  final deviceLocale = WidgetsBinding.instance.platformDispatcher.locale;

  if (languageCode == null) {
    // Auto-detect: use device locale if supported, otherwise fallback to English
    if (deviceLocale.languageCode == 'id') {
      return const Locale('id');
    }
    return const Locale('en');
  }

  // Use user-selected language
  return Locale(languageCode);
}
