/// Represents the possible lifecycle states of an upload task.
enum UploadStatus {
  /// The task is waiting in the queue to be processed.
  enqueued,

  /// The task is actively uploading data.
  running,

  /// The task is temporarily paused (e.g. user requested or waiting for network).
  paused,

  /// The task failed due to an error, but might still be retried if attempts remain.
  failed,

  /// The task has successfully uploaded and verified by the server.
  completed,

  /// The task was explicitly cancelled by the user.
  cancelled,
}

/// Extension methods for [UploadStatus] to simplify status checks.
extension UploadStatusX on UploadStatus {
  /// Whether the task is currently active or pending execution.
  bool get isInProgress =>
      this == UploadStatus.enqueued || this == UploadStatus.running;

  /// Whether the task has finished (either success, cancellation, or fatal failure).
  bool get isTerminal =>
      this == UploadStatus.completed || this == UploadStatus.cancelled;

  /// Whether the task can be paused.
  bool get canPause => this == UploadStatus.running || this == UploadStatus.enqueued;

  /// Whether the task can be resumed.
  bool get canResume => this == UploadStatus.paused || this == UploadStatus.failed;

  /// Human-readable label for UI.
  String get displayName {
    switch (this) {
      case UploadStatus.enqueued:
        return 'Enqueued';
      case UploadStatus.running:
        return 'Uploading';
      case UploadStatus.paused:
        return 'Paused';
      case UploadStatus.failed:
        return 'Failed';
      case UploadStatus.completed:
        return 'Completed';
      case UploadStatus.cancelled:
        return 'Cancelled';
    }
  }
}
