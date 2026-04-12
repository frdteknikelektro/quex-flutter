enum DownloadStatus { idle, downloading, cancelling, completed, failed }

class ModelDownloadState {
  final DownloadStatus status;
  final double progress;
  final String? error;

  const ModelDownloadState({
    required this.status,
    this.progress = 0.0,
    this.error,
  });

  static const ModelDownloadState idle = ModelDownloadState(status: DownloadStatus.idle);

  bool get isActive =>
      status == DownloadStatus.downloading || status == DownloadStatus.cancelling;
  bool get isCompleted => status == DownloadStatus.completed;
  bool get hasFailed => status == DownloadStatus.failed;

  ModelDownloadState copyWith({
    DownloadStatus? status,
    double? progress,
    String? error,
  }) {
    return ModelDownloadState(
      status: status ?? this.status,
      progress: progress ?? this.progress,
      error: error ?? this.error,
    );
  }
}
