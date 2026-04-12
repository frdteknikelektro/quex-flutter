import 'package:shared_preferences/shared_preferences.dart';

class ModelManager {
  static const modelReadyKey = 'model_ready';
  static const modelProgressKey = 'model_progress';
  static const modelVersionKey = 'model_version';
  static const currentVersion = 'quex-local-v1';

  static Future<bool> isReady() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(modelReadyKey) ?? false;
  }

  static Future<double> progress() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(modelProgressKey) ?? 0.0;
  }

  static Future<String> version() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(modelVersionKey) ?? currentVersion;
  }

  static Future<void> markReady({
    String version = currentVersion,
    double progress = 1.0,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(modelReadyKey, true);
    await prefs.setDouble(modelProgressKey, progress);
    await prefs.setString(modelVersionKey, version);
  }

  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(modelReadyKey, false);
    await prefs.setDouble(modelProgressKey, 0.0);
  }

  static Stream<double> simulateDownload() async* {
    for (var i = 1; i <= 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      yield i / 20;
    }
  }

  static String sizeLabel(bool ready) {
    return ready ? '1.5 GB ready' : 'Not downloaded';
  }
}
