import 'gemma_inference_service.dart';

class GemmaServiceHost {
  GemmaServiceHost({GemmaInferenceService? service})
      : _service = service ?? GemmaInferenceService();

  final GemmaInferenceService _service;
  Future<GemmaInferenceService>? _initializing;

  GemmaInferenceService get service => _service;

  bool get isInitialized => _service.isInitialized;

  Future<GemmaInferenceService> ensureInitialized() {
    if (_service.isInitialized) {
      return Future.value(_service);
    }

    final current = _initializing;
    if (current != null) return current;

    final future = _service.initialize().then((_) => _service);
    _initializing = future;
    future.whenComplete(() {
      _initializing = null;
    });
    return future;
  }

  Future<void> dispose() {
    return _service.dispose();
  }
}
