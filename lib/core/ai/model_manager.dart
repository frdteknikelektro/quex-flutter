import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../device/device_info.dart';

/// ModelManager handles Gemma 4 model installation and status.
///
/// Supports two variants based on device RAM:
/// - Gemma 4 E4B: ~3.65GB (for devices with ≥9GB RAM)
/// - Gemma 4 E2B: ~2.58GB (for devices with <9GB RAM)
///
/// Both use ModelType.gemmaIt and .litertlm format for LiteRT-LM framework.
/// Capabilities: Text, Image, Audio, Function Calling, Thinking Mode
class ModelManager {
  static const modelReadyKey = 'model_ready';
  static const modelProgressKey = 'model_progress';
  static const modelVersionKey = 'model_version';
  static const modelVariantKey = 'model_variant';

  static const String variantE4B = 'e4b';
  static const String variantE2B = 'e2b';
  static const int ramThresholdGB = 7;

  // Gemma 4 E4B from litert-community (.litertlm format)
  static const String gemmaE4BModelUrl =
      'https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it.litertlm';
  static const String gemmaE4BFileName = 'gemma-4-E4B-it.litertlm';
  static const String gemmaE4BSize = '3.65 GB';

  // Gemma 4 E2B from litert-community (.litertlm format)
  static const String gemmaE2BModelUrl =
      'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm';
  static const String gemmaE2BFileName = 'gemma-4-E2B-it.litertlm';
  static const String gemmaE2BSize = '2.58 GB';

  static String? _selectedVariant;

  // Must match SmartDownloader._downloadGroup in flutter_gemma 0.13.x
  static const String _smartDownloaderGroup = 'smart_downloads';

  // Guard against multiple simultaneous install() calls
  static bool _isInstalling = false;

  @visibleForTesting
  static GemmaInstallModelBuilder installModelFactory =
      FlutterGemma.installModel;

  /// Select model variant based on device RAM.
  /// Returns 'e2b' for <9GB RAM, 'e4b' for ≥9GB RAM.
  static String selectModelVariant(int ramGB) {
    return ramGB < ramThresholdGB ? variantE2B : variantE4B;
  }

  /// Get the currently selected model variant.
  /// Returns saved variant from SharedPreferences, or selects based on RAM if not set.
  static Future<String> getSelectedVariant() async {
    if (_selectedVariant != null) {
      return _selectedVariant!;
    }

    final prefs = await SharedPreferences.getInstance();
    final savedVariant = prefs.getString(modelVariantKey);

    if (savedVariant != null) {
      _selectedVariant = savedVariant;
      return savedVariant;
    }

    // No saved variant, select based on RAM
    final ramGB = await _getDeviceRamGB();
    _selectedVariant = selectModelVariant(ramGB);
    await prefs.setString(modelVariantKey, _selectedVariant!);
    return _selectedVariant!;
  }

  /// Get model URL for the selected variant.
  static Future<String> getModelUrl() async {
    final variant = await getSelectedVariant();
    return variant == variantE2B ? gemmaE2BModelUrl : gemmaE4BModelUrl;
  }

  /// Get model filename for the selected variant.
  static Future<String> getModelFileName() async {
    final variant = await getSelectedVariant();
    return variant == variantE2B ? gemmaE2BFileName : gemmaE4BFileName;
  }

  /// Get model size label for the selected variant.
  static Future<String> getModelSize() async {
    final variant = await getSelectedVariant();
    return variant == variantE2B ? gemmaE2BSize : gemmaE4BSize;
  }

  static Future<int> _getDeviceRamGB() async {
    try {
      return await DeviceInfo.getPhysicalRamGB();
    } catch (e) {
      print('[ModelManager] Failed to get device RAM: $e');
      return 0; // Fallback to E2B
    }
  }

  static Future<bool> isReady() async {
    final prefs = await SharedPreferences.getInstance();
    final fileName = await getModelFileName();
    final isInstalled = await FlutterGemma.isModelInstalled(fileName);
    return prefs.getBool(modelReadyKey) ?? false || isInstalled;
  }

  static Future<double> progress() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(modelProgressKey) ?? 0.0;
  }

  static Future<String> version() async {
    final prefs = await SharedPreferences.getInstance();
    final variant = await getSelectedVariant();
    return prefs.getString(modelVersionKey) ?? 'gemma-4-$variant-litert';
  }

  static Future<void> markReady({
    String? version,
    double progress = 1.0,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(modelReadyKey, true);
    await prefs.setDouble(modelProgressKey, progress);
    if (version != null) {
      await prefs.setString(modelVersionKey, version);
    }
  }

  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(modelReadyKey, false);
    await prefs.setDouble(modelProgressKey, 0.0);
    await prefs.remove(modelVersionKey);
    await prefs.remove(modelVariantKey);
    _selectedVariant = null;

    // Clear any FlutterGemma-specific keys
    final keys = prefs.getKeys();
    for (final key in keys) {
      if (key.contains('gemma') ||
          key.contains('model') ||
          key.contains('install')) {
        print('🗑️ Removing FlutterGemma key: $key');
        await prefs.remove(key);
      }
    }
  }

  /// Delete the downloaded model file from storage.
  /// Call this to free up space (2.58GB for E2B, 3.65GB for E4B).
  static Future<void> deleteModel() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final fileName = await getModelFileName();
      print('🗑️ App directory: ${appDir.path}');
      final modelFile = File('${appDir.path}/$fileName');
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

  /// Download and install Gemma 4 model with progress callback.
  /// Returns a stream of download progress (0.0 to 1.0).
  /// Pass a [CancelToken] to support cancellation; cancelling the token
  /// also closes the stream.
  /// Times out after 60 seconds if no progress updates (e.g., stuck in resume pending).
  static Stream<double> downloadModel({CancelToken? cancelToken}) async* {
    if (_isInstalling) return;
    _isInstalling = true;
    try {
      late final StreamController<double> controller;
      final effectiveCancelToken = cancelToken ?? CancelToken();

      void onCancel() {
        effectiveCancelToken.cancel();
        if (!controller.isClosed) {
          controller.close();
        }
      }

      controller = StreamController<double>(onCancel: onCancel);

      activateModel(
        cancelToken: effectiveCancelToken,
        onProgress: (progress) {
          if (!controller.isClosed) {
            // SmartDownloader may report -1.0 as "no progress yet"
            final clamped = progress.clamp(0, 100);
            controller.add(clamped / 100.0);
          }
        },
      ).then((_) async {
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

      yield* controller.stream.timeout(
        const Duration(seconds: 60),
        onTimeout: (sink) {
          sink.addError(
            TimeoutException('Download timed out - no progress for 60 seconds'),
          );
          sink.close();
        },
      );
    } finally {
      _isInstalling = false;
    }
  }

  static InferenceInstallationBuilder _buildGemmaInstaller(String modelUrl) {
    return installModelFactory(
      modelType: ModelType.gemmaIt,
      fileType: ModelFileType.litertlm,
    ).fromNetwork(modelUrl);
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
  static Future<void> activateModel({
    CancelToken? cancelToken,
    void Function(int progress)? onProgress,
  }) async {
    if (FlutterGemma.hasActiveModel()) {
      await markReady();
      return;
    }

    final modelUrl = await getModelUrl();
    final effectiveCancelToken = cancelToken ?? CancelToken();
    final installer = _buildGemmaInstaller(modelUrl)
        .withProgress((progress) {
          onProgress?.call(progress);
        })
        .withCancelToken(effectiveCancelToken);

    await installer.install();
    await markReady();
  }

  static Future<String> sizeLabel(bool ready) async {
    final size = await getModelSize();
    final variant = await getSelectedVariant();
    final variantName = variant == variantE2B ? 'E2B' : 'E4B';
    return ready ? '$size ready (Gemma 4 $variantName)' : 'Not downloaded';
  }
}

typedef GemmaInstallModelBuilder = InferenceInstallationBuilder Function({
  required ModelType modelType,
  ModelFileType fileType,
});
