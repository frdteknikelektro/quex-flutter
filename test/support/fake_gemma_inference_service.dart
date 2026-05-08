import 'package:flutter_gemma/flutter_gemma.dart' as gemma;

import 'package:quex/core/ai/gemma_inference_service.dart';

class FakeGemmaInferenceService extends GemmaInferenceService {
  int initializeCalls = 0;
  int disposeCalls = 0;
  int closeSessionCalls = 0;
  bool _ready = false;

  @override
  bool get isInitialized => _ready;

  @override
  Future<void> initialize({
    int? maxTokens,
    gemma.PreferredBackend preferredBackend = gemma.PreferredBackend.cpu,
    bool enableSpeculativeDecoding = true,
  }) async {
    initializeCalls++;
    _ready = true;
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    await super.dispose();
    _ready = false;
  }

  @override
  Future<void> closeSession() async {
    closeSessionCalls++;
    await super.closeSession();
    _ready = false;
  }
}
