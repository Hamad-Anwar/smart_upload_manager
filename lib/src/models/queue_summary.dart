import 'upload_task.dart';

/// Aggregated metrics and status for the entire upload queue.
class QueueSummary {
  /// Total count of all tasks known to the queue.
  final int totalTasks;

  /// Count of tasks currently uploading data.
  final int activeTasks;

  /// Count of tasks waiting to be processed.
  final int enqueuedTasks;

  /// Count of tasks that are paused.
  final int pausedTasks;

  /// Count of tasks that have finished uploading successfully.
  final int completedTasks;

  /// Count of tasks that failed and are awaiting retry or gave up.
  final int failedTasks;

  /// Count of tasks cancelled by the user.
  final int cancelledTasks;

  /// Sum of all file sizes in the queue in bytes.
  final int totalBytes;

  /// Total confirmed bytes uploaded across all tasks.
  final int uploadedBytes;

  /// Combined aggregate upload speed in bytes per second.
  final double aggregateSpeed;

  /// Whether network connectivity is currently available.
  final bool isConnected;

  const QueueSummary({
    this.totalTasks = 0,
    this.activeTasks = 0,
    this.enqueuedTasks = 0,
    this.pausedTasks = 0,
    this.completedTasks = 0,
    this.failedTasks = 0,
    this.cancelledTasks = 0,
    this.totalBytes = 0,
    this.uploadedBytes = 0,
    this.aggregateSpeed = 0.0,
    this.isConnected = true,
  });

  /// Aggregate progress across all tasks (0.0 to 1.0).
  double get overallProgress {
    if (totalBytes <= 0) return 0.0;
    return (uploadedBytes / totalBytes).clamp(0.0, 1.0);
  }

  /// Aggregate percentage (0 - 100).
  int get overallProgressPercent => (overallProgress * 100).round();

  /// Whether any task is actively uploading right now.
  bool get isUploading => activeTasks > 0;

  /// Total number of active and pending tasks in the queue.
  int get totalActiveAndPending => activeTasks + enqueuedTasks;

  /// Whether there are no active or pending tasks.
  bool get isIdle => activeTasks == 0 && enqueuedTasks == 0;

  /// Whether there are any paused tasks.
  bool get hasPaused => pausedTasks > 0;

  /// Whether there are any failed tasks.
  bool get hasFailed => failedTasks > 0;

  /// Human-readable aggregated upload speed.
  String get formattedSpeed => '${UploadTask.formatBytes(aggregateSpeed.round())}/s';

  /// Human-readable total uploaded size.
  String get formattedUploadedSize => UploadTask.formatBytes(uploadedBytes);

  /// Human-readable total queue size.
  String get formattedTotalSize => UploadTask.formatBytes(totalBytes);

  @override
  String toString() =>
      'QueueSummary(active: $activeTasks, pending: $enqueuedTasks, completed: $completedTasks, progress: $overallProgressPercent%)';
}
