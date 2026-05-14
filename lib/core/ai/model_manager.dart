import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../device/device_info.dart';
import 'auth_token_service.dart';
import 'llm_memory_calculator.dart';

/// ModelManager handles Gemma 4 model installation and status.
///
/// Supports two variants based on maxTokens calculation:
/// - Gemma 4 E4B: ~3.65GB (selected if device can support 8192+ tokens with E4B)
/// - Gemma 4 E2B: ~2.58GB (fallback when E4B would limit tokens below 8192)
///
/// Both use ModelType.gemma4 and .litertlm format for LiteRT-LM framework.
/// Capabilities: Text, Image, Audio, Function Calling, Thinking Mode
class ModelManager {
  static const modelReadyKey = 'model_ready';
  static const modelProgressKey = 'model_progress';
  static const modelVersionKey = 'model_version';
  static const modelVariantKey = 'model_variant';

  static const String variantE4B = 'e4b';
  static const String variantE2B = 'e2b';

  /// Minimum tokens required to select E4B variant
  static const int minTokensForE4B = 8192;

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

  static InferenceModel? _model;
  static int? _lastMaxTokens;
  static PreferredBackend? _lastPreferredBackend;
  static int? _lastMaxNumImages;
  static bool? _lastEnableSpeculativeDecoding;

  // Must match SmartDownloader._downloadGroup in flutter_gemma 0.13.x
  static const String _smartDownloaderGroup = 'smart_downloads';

  // Guard against multiple simultaneous install() calls
  static bool _isInstalling = false;

  @visibleForTesting
  static GemmaInstallModelBuilder installModelFactory =
      FlutterGemma.installModel;

  /// Select model variant based on maxTokens calculation.
  /// Uses exact RAM in MB to calculate if E4B can support at least [minTokensForE4B] tokens.
  /// Returns 'e4b' if E4B supports 8192+ tokens, otherwise 'e2b'.
  static String selectModelVariant(int ramMB) {
    try {
      final e4bMaxTokens = LLMMemoryCalculator.calculateMaxTokens(
        ramMB: ramMB,
        isE4B: true,
      );
      return e4bMaxTokens >= minTokensForE4B ? variantE4B : variantE2B;
    } catch (e) {
      // Insufficient RAM for E4B, fallback to E2B
      return variantE2B;
    }
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

    // No saved variant, select based on exact RAM and maxTokens calculation
    final ramMB = await DeviceInfo.getPhysicalRamMB();
    _selectedVariant = selectModelVariant(ramMB);
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
        debugPrint('🗑️ Removing FlutterGemma key: $key');
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
      debugPrint('🗑️ App directory: ${appDir.path}');
      final modelFile = File('${appDir.path}/$fileName');
      debugPrint('🗑️ Attempting to delete model from: ${modelFile.path}');
      debugPrint('🗑️ File exists: ${await modelFile.exists()}');
      if (await modelFile.exists()) {
        await modelFile.delete();
        debugPrint('🗑️ File deleted successfully');
        debugPrint(
            '🗑️ File exists after deletion: ${await modelFile.exists()}');
      } else {
        debugPrint('🗑️ File does not exist');
      }
    } catch (e) {
      debugPrint('🗑️ Deletion error: $e');
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
  static Stream<double> downloadModel({
    CancelToken? cancelToken,
    String? token,
  }) async* {
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
        token: token,
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

  static InferenceInstallationBuilder _buildGemmaInstaller(
    String modelUrl, {
    String? token,
  }) {
    return installModelFactory(
      modelType: ModelType.gemma4,
      fileType: ModelFileType.litertlm,
    ).fromNetwork(modelUrl, token: token);
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
    String? token,
  }) async {
    if (FlutterGemma.hasActiveModel()) {
      await markReady();
      return;
    }

    final modelUrl = await getModelUrl();
    final effectiveCancelToken = cancelToken ?? CancelToken();

    // Load token from AuthTokenService if not provided
    final authToken = token ?? await AuthTokenService.loadToken();

    final installer = _buildGemmaInstaller(
      modelUrl,
      token: authToken,
    ).withProgress((progress) {
      onProgress?.call(progress);
    }).withCancelToken(effectiveCancelToken);

    await installer.install();
    await markReady();
  }

  static Future<String> sizeLabel(bool ready) async {
    final size = await getModelSize();
    final variant = await getSelectedVariant();
    final variantName = variant == variantE2B ? 'E2B' : 'E4B';
    return ready ? '$size ready (Gemma 4 $variantName)' : 'Not downloaded';
  }

  /// Get the active model instance, creating it if necessary.
  /// If parameters differ from the last call, the previous model is automatically
  /// closed by the underlying plugin.
  static Future<InferenceModel> getModel({
    int maxTokens = 8192,
    PreferredBackend? preferredBackend = PreferredBackend.gpu,
    int? maxNumImages = 16,
    bool? enableSpeculativeDecoding = true,
  }) async {
    if (_model != null &&
        _lastMaxTokens == maxTokens &&
        _lastPreferredBackend == preferredBackend &&
        _lastMaxNumImages == maxNumImages &&
        _lastEnableSpeculativeDecoding == enableSpeculativeDecoding) {
      return _model!;
    }

    _model = await FlutterGemma.getActiveModel(
      maxTokens: maxTokens,
      preferredBackend: maxTokens < 4096 ? PreferredBackend.cpu : preferredBackend,
      supportImage: true,
      supportAudio: true,
      maxNumImages: maxNumImages,
      enableSpeculativeDecoding: enableSpeculativeDecoding,
    );

    _lastMaxTokens = maxTokens;
    _lastPreferredBackend = preferredBackend;
    _lastMaxNumImages = maxNumImages;
    _lastEnableSpeculativeDecoding = enableSpeculativeDecoding;

    return _model!;
  }
}

typedef GemmaInstallModelBuilder = InferenceInstallationBuilder Function({
  required ModelType modelType,
  ModelFileType fileType,
});
