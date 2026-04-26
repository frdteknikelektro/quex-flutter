// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'language_state.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$localeHash() => r'f210aea0b919066dcdd9a0bdb88ed93995a9cf7a';

/// See also [locale].
@ProviderFor(locale)
final localeProvider = AutoDisposeProvider<Locale>.internal(
  locale,
  name: r'localeProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$localeHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef LocaleRef = AutoDisposeProviderRef<Locale>;
String _$languageNotifierHash() => r'f4672b3b62f83954c723f232bb90aad9932e0c70';

/// See also [LanguageNotifier].
@ProviderFor(LanguageNotifier)
final languageNotifierProvider =
    AutoDisposeNotifierProvider<LanguageNotifier, String?>.internal(
  LanguageNotifier.new,
  name: r'languageNotifierProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$languageNotifierHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$LanguageNotifier = AutoDisposeNotifier<String?>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member
