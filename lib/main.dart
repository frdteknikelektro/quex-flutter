import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'app/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Flutter Gemma
  // Use WebStorageMode.streaming for large models (E4B 4GB+)
  // Use WebStorageMode.cacheApi for smaller models (default, faster)
  await FlutterGemma.initialize(
    webStorageMode: WebStorageMode.streaming,
  );

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const ProviderScope(child: QuexApp()));
}

class QuexApp extends StatelessWidget {
  const QuexApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Quex',
      debugShowCheckedModeBanner: false,
      theme: QuexTheme.lightTheme,
      darkTheme: QuexTheme.darkTheme,
      themeMode: ThemeMode.system,
      routerConfig: appRouter,
    );
  }
}
