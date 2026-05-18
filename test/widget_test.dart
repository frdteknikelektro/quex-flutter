import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quex/core/ai/download_state.dart';
import 'package:quex/core/ai/model_download_notifier.dart';
import 'package:quex/core/state/app_state.dart';
import 'package:quex/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class ReadyModelDownloadNotifier extends ModelDownloadNotifier {
  @override
  ModelDownloadState build() {
    return const ModelDownloadState(
      status: DownloadStatus.completed,
      progress: 1.0,
      modelVariant: 'e2b',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('app boots with the Quex dashboard', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          modelDownloadProvider.overrideWith(ReadyModelDownloadNotifier.new),
          sessionProfileSetProvider.overrideWith((ref) => false),
        ],
        child: const QuexApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(ProviderScope), findsOneWidget);
  });
}
