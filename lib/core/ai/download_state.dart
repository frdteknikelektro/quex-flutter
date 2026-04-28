enum DownloadStatus { idle, downloading, cancelling, completed, failed, warming }

class ModelDownloadState {
  final DownloadStatus status;
  final double progress;
  final String? error;
  final String? modelVariant; // 'e4b' or 'e2b'

  const ModelDownloadState({
    required this.status,
    this.progress = 0.0,
    this.error,
    this.modelVariant,
  });

  static const ModelDownloadState idle = ModelDownloadState(status: DownloadStatus.idle);

  bool get isActive =>
      status == DownloadStatus.downloading ||
      status == DownloadStatus.cancelling ||
      status == DownloadStatus.warming;
  bool get isCompleted => status == DownloadStatus.completed;
  bool get hasFailed => status == DownloadStatus.failed;
  bool get isWarming => status == DownloadStatus.warming;

  ModelDownloadState copyWith({
    DownloadStatus? status,
    double? progress,
    String? error,
    String? modelVariant,
  }) {
    return ModelDownloadState(
      status: status ?? this.status,
      progress: progress ?? this.progress,
      error: error ?? this.error,
      modelVariant: modelVariant ?? this.modelVariant,
    );
  }
}
