import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quex/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('app boots with the Quex dashboard', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: QuexApp()));
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(ProviderScope), findsOneWidget);
  });
}
