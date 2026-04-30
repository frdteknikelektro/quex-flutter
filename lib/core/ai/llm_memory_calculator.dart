/// Standalone LLM Memory Calculator for Gemma 4 models
/// Calculates optimal maxTokens based on device RAM with 70% budget
class LLMMemoryCalculator {
  // Architecture constants from HuggingFace config.json
  static const int _e2bWeightsMB = 2642; // 2.58 GB file
  static const int _e4bWeightsMB = 3738; // 3.65 GB file

  // KV cache: 2(K+V) × layers × kv_heads × head_dim × 2 bytes
  static const int _e2bBytesPerToken = 35840; // 2×35×1×256×2
  static const int _e4bBytesPerToken = 86016; // 2×42×2×256×2

  static const int _maxPositionEmbeddings = 131072;
  static const double _budgetPercent = 0.70;
  static const int _roundTo = 64;

  static int calculateMaxTokens({
    required int ramMB,
    required bool isE4B,
    int? hardCap,
  }) {
    final budgetMB = (ramMB * _budgetPercent).floor();
    final weightsMB = isE4B ? _e4bWeightsMB : _e2bWeightsMB;
    final availableForKV_MB = budgetMB - weightsMB;

    if (availableForKV_MB <= 0) {
      throw Exception(
        'Insufficient RAM: need ${weightsMB}MB for weights, '
        'have ${budgetMB}MB budget (70% of ${ramMB}MB)',
      );
    }

    final availableForKV_B = availableForKV_MB * 1024 * 1024;
    final bytesPerToken = isE4B ? _e4bBytesPerToken : _e2bBytesPerToken;
    final rawTokens = availableForKV_B ~/ bytesPerToken;
    final roundedTokens = (rawTokens ~/ _roundTo) * _roundTo;

    var finalTokens =
        roundedTokens > _maxPositionEmbeddings
            ? _maxPositionEmbeddings
            : roundedTokens;

    if (hardCap != null && finalTokens > hardCap) {
      finalTokens = hardCap;
    }

    return finalTokens < 512 ? 512 : finalTokens;
  }

  static Map<String, dynamic> getDiagnostics(int ramMB) {
    final budgetMB = (ramMB * _budgetPercent).floor();

    return {
      'totalRamMB': ramMB,
      'budgetPercent': '${(_budgetPercent * 100).toInt()}%',
      'budgetMB': budgetMB,
      'e2bWeightsMB': _e2bWeightsMB,
      'e4bWeightsMB': _e4bWeightsMB,
      'e2bRecommended': calculateMaxTokens(ramMB: ramMB, isE4B: false),
      'e4bRecommended': calculateMaxTokens(ramMB: ramMB, isE4B: true),
      'e2bBytesPerToken': _e2bBytesPerToken,
      'e4bBytesPerToken': _e4bBytesPerToken,
    };
  }
}
