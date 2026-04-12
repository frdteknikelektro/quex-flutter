import 'dart:async';

import 'package:flutter_gemma/core/model_management/cancel_token.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ModelManager handles Gemma 4 E4B model installation and status.
///
/// Gemma 4 E4B specs (litert-community):
/// - Size: ~6.6GB
/// - ModelType: ModelType.gemmaIt
/// - Capabilities: Text, Image, Audio, Function Calling, Thinking Mode
/// - Format: .litertlm for LiteRT-LM framework
class ModelManager {
  static const modelReadyKey = 'model_ready';
  static const modelProgressKey = 'model_progress';
  static const modelVersionKey = 'model_version';
  static const currentVersion = 'gemma-4-e4b-litert';

  // Gemma 4 E4B from litert-community (.litertlm format)
  static const String gemmaModelUrl =
      'https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it.litertlm';

  static Future<bool> isReady() async {
    final prefs = await SharedPreferences.getInstance();
    final isInstalled = await FlutterGemma.isModelInstalled('gemma-4-E4B-it.litertlm');
    return prefs.getBool(modelReadyKey) ?? false || isInstalled;
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

  /// Download and install Gemma 4 E4B model with progress callback.
  /// Returns a stream of download progress (0.0 to 1.0).
  static Stream<double> downloadModel({CancelToken? cancelToken}) async* {
    await for (final progress in _installWithProgress(cancelToken: cancelToken)) {
      yield progress;
    }
  }

  /// Internal method to install model with progress.
  static Stream<double> _installWithProgress({CancelToken? cancelToken}) async* {
    final controller = StreamController<double>();

    FlutterGemma.installModel(
      modelType: ModelType.gemmaIt,
    ).fromNetwork(
      gemmaModelUrl,
    ).withProgress((progress) {
      controller.add(progress / 100.0); // Convert 0-100 to 0.0-1.0
    }).install().then((_) async {
      await markReady();
      controller.add(1.0);
      controller.close();
    }).catchError((error) {
      controller.addError(error);
      controller.close();
    });

    await for (final progress in controller.stream) {
      yield progress;
    }
  }

  /// Legacy simulate download for testing (fallback).
  static Stream<double> simulateDownload() async* {
    for (var i = 1; i <= 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      yield i / 20;
    }
  }

  static String sizeLabel(bool ready) {
    return ready ? '6.6 GB ready (Gemma 4 E4B)' : 'Not downloaded';
  }
}
