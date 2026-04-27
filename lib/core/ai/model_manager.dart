import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ModelManager handles Gemma 4 E4B model installation and status.
///
/// Gemma 4 E4B specs (litert-community):
/// - Size: ~3.65GB
/// - ModelType: ModelType.gemma4It
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

  // Must match SmartDownloader._downloadGroup in flutter_gemma 0.13.x
  static const String _smartDownloaderGroup = 'smart_downloads';

  // Guard against multiple simultaneous install() calls
  static bool _isInstalling = false;

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
    await prefs.remove(modelVersionKey);
    
    // Clear any FlutterGemma-specific keys
    final keys = prefs.getKeys();
    for (final key in keys) {
      if (key.contains('gemma') || key.contains('model') || key.contains('install')) {
        print('🗑️ Removing FlutterGemma key: $key');
        await prefs.remove(key);
      }
    }
  }

  /// Delete the downloaded model file from storage.
  /// Call this to free up ~3.65GB of space.
  static Future<void> deleteModel() async {
    try {
      // FlutterGemma stores the model in the app's data directory
      // Path: /data/user/0/com.example.quex/app_flutter/gemma-4-E4B-it.litertlm
      final appDir = await getApplicationDocumentsDirectory();
      print('🗑️ App directory: ${appDir.path}');
      final modelFile = File('${appDir.path}/gemma-4-E4B-it.litertlm');
      print('🗑️ Attempting to delete model from: ${modelFile.path}');
      print('🗑️ File exists: ${await modelFile.exists()}');
      if (await modelFile.exists()) {
        await modelFile.delete();
        print('🗑️ File deleted successfully');
        print('🗑️ File exists after deletion: ${await modelFile.exists()}');
      } else {
        print('🗑️ File does not exist');
      }
    } catch (e) {
      print('🗑️ Deletion error: $e');
    }
  }

  /// Persist partial progress so it can be restored after a cancel/restart.
  static Future<void> saveProgress(double progress) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(modelProgressKey, progress);
  }

  /// Cancel all background download tasks spawned by SmartDownloader.
  /// Call this to stop the internal retry loops inside flutter_gemma.
  static Future<void> cancelAllBackgroundTasks() async {
    final downloader = FileDownloader();
    final tasks = await downloader.allTasks(group: _smartDownloaderGroup);
    if (tasks.isNotEmpty) {
      await downloader.cancelTasksWithIds(tasks.map((t) => t.taskId).toList());
    }
  }

  /// Download and install Gemma 4 E4B model with progress callback.
  /// Returns a stream of download progress (0.0 to 1.0).
  /// Pass a [CancelToken] to support cancellation; cancelling the token
  /// also closes the stream.
  /// Times out after 60 seconds if no progress updates (e.g., stuck in resume pending).
  static Stream<double> downloadModel({CancelToken? cancelToken}) async* {
    if (_isInstalling) return;
    _isInstalling = true;
    try {
      final stream = _installWithProgress(cancelToken: cancelToken);
      await for (final progress in stream.timeout(
        const Duration(seconds: 60),
        onTimeout: (sink) {
          sink.addError(TimeoutException('Download timed out - no progress for 60 seconds'));
          sink.close();
        },
      )) {
        yield progress;
      }
    } finally {
      _isInstalling = false;
    }
  }

  /// Internal method to install model with progress.
  static Stream<double> _installWithProgress({CancelToken? cancelToken}) {
    late final StreamController<double> controller;

    void onCancel() {
      cancelToken?.cancel();
      if (!controller.isClosed) {
        controller.close();
      }
    }

    controller = StreamController<double>(onCancel: onCancel);

    FlutterGemma.installModel(
      modelType: ModelType.gemma4It,
    ).fromNetwork(
      gemmaModelUrl,
    ).withProgress((progress) {
      if (!controller.isClosed) {
        // SmartDownloader may report -1.0 as "no progress yet"
        final clamped = progress.clamp(0, 100);
        controller.add(clamped / 100.0);
      }
    }).withCancelToken(cancelToken ?? CancelToken())
    .install().then((_) async {
      await markReady();
      if (!controller.isClosed) {
        controller.add(1.0);
        await controller.close();
      }
    }).catchError((Object error) {
      if (!controller.isClosed) {
        controller.addError(error);
        controller.close();
      }
    });

    return controller.stream;
  }

  /// Legacy simulate download for testing (fallback).
  static Stream<double> simulateDownload() async* {
    for (var i = 1; i <= 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      yield i / 20;
    }
  }

  /// Re-register already-downloaded model as active for this session.
  /// install() is idempotent — skips download if file exists, just sets active.
  static Future<void> activateModel() async {
    if (FlutterGemma.hasActiveModel()) return;
    await FlutterGemma.installModel(modelType: ModelType.gemma4It)
        .fromNetwork(gemmaModelUrl)
        .install();
  }

  static String sizeLabel(bool ready) {
    return ready ? '3.65 GB ready (Gemma 4 E4B)' : 'Not downloaded';
  }
}
