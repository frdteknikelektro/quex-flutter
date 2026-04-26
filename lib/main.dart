import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quex/generated/l10n/app_localizations.dart';

import 'app/router.dart';
import 'app/theme.dart';
import 'core/notifications/notification_service.dart';
import 'core/state/language_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Flutter Gemma
  // Use WebStorageMode.streaming for large models (E4B 4GB+)
  // Use WebStorageMode.cacheApi for smaller models (default, faster)
  await FlutterGemma.initialize(
    webStorageMode: WebStorageMode.streaming,
  );

  await NotificationService.instance.initialize();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const ProviderScope(child: QuexApp()));
}

class QuexApp extends ConsumerWidget {
  const QuexApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);

    return MaterialApp.router(
      title: 'Quex',
      debugShowCheckedModeBanner: false,
      theme: QuexTheme.lightTheme,
      darkTheme: QuexTheme.darkTheme,
      themeMode: ThemeMode.system,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: appRouter,
    );
  }
}
