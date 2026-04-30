import 'llm_memory_calculator.dart';
import '../device/device_info.dart';
import 'model_manager.dart';

/// Service to auto-configure Gemma models based on device capabilities.
/// Provides calculated maxTokens as an upper bound (hard maximum).
class GemmaConfigService {
  static int? _cachedMaxTokens;

  /// Get the calculated maxTokens upper bound.
  /// Calculates once per session and caches the result.
  /// Returns the calculated optimal maxTokens or fallback if calculation fails.
  static Future<int> getMaxTokensUpperBound({int fallback = 8192}) async {
    if (_cachedMaxTokens != null) {
      return _cachedMaxTokens!;
    }

    try {
      final ramGB = await DeviceInfo.getPhysicalRamGB();
      if (ramGB <= 0) {
        _cachedMaxTokens = fallback;
        return fallback;
      }

      final ramMB = ramGB * 1024;
      final variant = await ModelManager.getSelectedVariant();
      final isE4B = variant == ModelManager.variantE4B;

      final maxTokens = LLMMemoryCalculator.calculateMaxTokens(
        ramMB: ramMB,
        isE4B: isE4B,
      );

      _cachedMaxTokens = maxTokens;
      return maxTokens;
    } catch (e) {
      print('[GemmaConfigService] Failed to calculate maxTokens: $e');
      _cachedMaxTokens = fallback;
      return fallback;
    }
  }

  /// Clear the cached maxTokens value.
  /// Call this to force recalculation on next getMaxTokensUpperBound() call.
  static void clearCache() {
    _cachedMaxTokens = null;
  }

  /// Get diagnostics information for debugging.
  static Future<Map<String, dynamic>> getDiagnostics() async {
    final ramGB = await DeviceInfo.getPhysicalRamGB();
    final ramMB = ramGB * 1024;
    final variant = await ModelManager.getSelectedVariant();

    return {
      'variant': variant,
      ...LLMMemoryCalculator.getDiagnostics(ramMB),
    };
  }

  /// Apply the upper bound to a requested maxTokens value.
  /// Returns the minimum of requested value and calculated upper bound.
  static Future<int> applyUpperBound(int? requestedMaxTokens, {int defaultValue = 8192}) async {
    final upperBound = await getMaxTokensUpperBound(fallback: defaultValue);
    final requested = requestedMaxTokens ?? defaultValue;
    return requested > upperBound ? upperBound : requested;
  }
}
