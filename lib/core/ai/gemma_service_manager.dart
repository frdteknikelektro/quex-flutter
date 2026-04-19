import 'dart:async';

import 'gemma_inference_service.dart';

typedef GemmaServiceFactory = GemmaInferenceService Function();

class GemmaServiceManager {
  GemmaServiceManager({
    GemmaServiceFactory? serviceFactory,
  }) : _serviceFactory = serviceFactory ?? GemmaInferenceService.new;

  static final GemmaServiceManager instance = GemmaServiceManager();

  final GemmaServiceFactory _serviceFactory;

  Future<void> _tail = Future<void>.value();

  GemmaInferenceService? _currentService;
  Object? _currentOwnerToken;

  GemmaInferenceService? get current => _currentService;
  Object? get currentOwnerToken => _currentOwnerToken;
  bool get isReady => _currentService?.isInitialized ?? false;

  bool isCurrentOwner(Object ownerToken) =>
      identical(_currentOwnerToken, ownerToken);

  Future<GemmaInferenceService> acquire(Object ownerToken) {
    return _enqueue(() async {
      final currentService = _currentService;
      if (currentService != null &&
          identical(_currentOwnerToken, ownerToken) &&
          currentService.isInitialized) {
        return currentService;
      }

      if (currentService != null) {
        await currentService.dispose();
        _currentService = null;
        _currentOwnerToken = null;
      }

      final service = _serviceFactory();
      await service.initialize();
      _currentService = service;
      _currentOwnerToken = ownerToken;
      return service;
    });
  }

  Future<void> release(Object ownerToken) {
    return _enqueue(() async {
      if (!identical(_currentOwnerToken, ownerToken)) return;

      final service = _currentService;
      _currentService = null;
      _currentOwnerToken = null;

      if (service != null) {
        await service.dispose();
      }
    });
  }

  Future<void> reset() {
    return _enqueue(() async {
      final service = _currentService;
      _currentService = null;
      _currentOwnerToken = null;
      if (service != null) {
        await service.dispose();
      }
    });
  }

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      }
    });
    return completer.future;
  }
}
