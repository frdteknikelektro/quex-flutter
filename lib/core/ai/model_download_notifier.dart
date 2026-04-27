import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_gemma/core/model_management/cancel_token.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../notifications/notification_service.dart';
import 'download_state.dart';
import 'model_manager.dart';

class ModelDownloadNotifier extends Notifier<ModelDownloadState> {
  StreamSubscription<double>? _subscription;
  CancelToken? _cancelToken;
  StreamSubscription<List<ConnectivityResult>>? _networkSubscription;
  int _lastNotifPercent = -1;

  @override
  ModelDownloadState build() {
    ref.onDispose(_cleanup);
    Future(_checkInitialState);
    return ModelDownloadState.idle;
  }

  Future<void> _checkInitialState() async {
    final ready = await ModelManager.isReady();
    final savedProgress = await ModelManager.progress();
    if (ready) {
      await ModelManager.activateModel();
      state = const ModelDownloadState(
        status: DownloadStatus.completed,
        progress: 1.0,
      );
    } else if (savedProgress > 0) {
      state = ModelDownloadState(
        status: DownloadStatus.idle,
        progress: savedProgress,
      );
    }
  }

  Future<void> start() async {
    if (state.isActive) return;

    // Skip if model is already downloaded (race condition with _checkInitialState)
    final ready = await ModelManager.isReady();
    if (ready) {
      state = const ModelDownloadState(
        status: DownloadStatus.completed,
        progress: 1.0,
      );
      return;
    }

    _cancelToken = CancelToken();
    _lastNotifPercent = -1;
    state = state.copyWith(status: DownloadStatus.downloading);

    await NotificationService.instance.requestPermissions();
    await NotificationService.instance
        .showDownloadProgress((state.progress * 100).round());

    // Listen for network changes
    _networkSubscription = Connectivity()
        .onConnectivityChanged
        .listen((results) async {
      if (state.isActive) {
        // Network changed during download - will attempt to resume
        await NotificationService.instance.showDownloadFailed(
          'Network interrupted. Attempting to resume download...',
        );
      }
    });

    _subscription = ModelManager.downloadModel(cancelToken: _cancelToken).listen(
      (progress) {
        state = state.copyWith(
          status: DownloadStatus.downloading,
          progress: progress,
        );
        _throttledNotifUpdate((progress * 100).round());
      },
      onDone: () async {
        final ready = await ModelManager.isReady();
        if (ready) {
          state = const ModelDownloadState(
            status: DownloadStatus.completed,
            progress: 1.0,
          );
          await NotificationService.instance.showDownloadComplete();
        }
      },
      onError: (Object error) async {
        await _networkSubscription?.cancel();
        _networkSubscription = null;
        if (state.status == DownloadStatus.cancelling) {
          await ModelManager.saveProgress(state.progress);
          state = ModelDownloadState(
            status: DownloadStatus.idle,
            progress: state.progress,
          );
          await NotificationService.instance.cancelDownloadNotification();
        } else {
          state = ModelDownloadState(
            status: DownloadStatus.failed,
            progress: state.progress,
            error: error.toString(),
          );
          await NotificationService.instance
              .showDownloadFailed(error.toString());
        }
      },
      cancelOnError: true,
    );
  }

  Future<void> cancel() async {
    if (!state.isActive) return;
    state = state.copyWith(status: DownloadStatus.cancelling);
    _cancelToken?.cancel();
    await ModelManager.cancelAllBackgroundTasks();
    await _networkSubscription?.cancel();
    _networkSubscription = null;
    await _subscription?.cancel();
    _subscription = null;
    await ModelManager.saveProgress(state.progress);
    state = ModelDownloadState(
      status: DownloadStatus.idle,
      progress: state.progress,
    );
    await NotificationService.instance.cancelDownloadNotification();
  }

  Future<void> retry() => start();

  Future<void> reset() async {
    if (state.isActive) {
      await cancel();
    }
    await ModelManager.reset();
    await ModelManager.deleteModel();
    state = ModelDownloadState.idle;
    await NotificationService.instance.cancelDownloadNotification();
  }

  void _throttledNotifUpdate(int percent) {
    if (percent - _lastNotifPercent >= 1 || percent >= 100) {
      _lastNotifPercent = percent;
      NotificationService.instance.showDownloadProgress(percent);
    }
  }

  Future<void> _cleanup() async {
    await _subscription?.cancel();
    _subscription = null;
    await _networkSubscription?.cancel();
    _networkSubscription = null;
  }
}

final modelDownloadProvider =
    NotifierProvider<ModelDownloadNotifier, ModelDownloadState>(
  ModelDownloadNotifier.new,
);
