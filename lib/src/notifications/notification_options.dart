import '../models/queue_summary.dart';
import '../models/upload_task.dart';

/// Configuration options for upload progress notifications.
class NotificationConfig {
  /// Pre-configured constant to completely disable all notifications.
  static const disabled = NotificationConfig(enabled: false);

  /// Whether notification progress is enabled.
  final bool enabled;

  /// Android notification channel ID.
  final String channelId;

  /// Android notification channel name.
  final String channelName;

  /// Android notification channel description.
  final String channelDescription;

  /// Notification icon identifier (e.g. '@mipmap/ic_launcher' on Android).
  final String? smallIcon;

  /// Whether to display a single aggregated summary notification for all active uploads.
  final bool showSummaryNotification;

  /// Throttling interval to prevent updating the OS notification service too frequently.
  final Duration throttleInterval;

  /// Notification ID for the summary notification.
  final int summaryNotificationId;

  /// Whether sound is enabled for notification alerts (start, completion, failure).
  final bool playSound;

  /// Whether to display a prominent banner alert with sound when an upload starts.
  final bool alertOnStart;

  /// Custom formatter for notification title.
  final String Function(UploadTask? task, QueueSummary summary)? titleFormatter;

  /// Custom formatter for notification body.
  final String Function(UploadTask? task, QueueSummary summary)? bodyFormatter;

  const NotificationConfig({
    this.enabled = true,
    this.channelId = 'smart_upload_channel',
    this.channelName = 'Upload Progress',
    this.channelDescription =
        'Displays ongoing file upload progress and status',
    this.smallIcon,
    this.showSummaryNotification = true,
    this.throttleInterval = const Duration(milliseconds: 500),
    this.summaryNotificationId = 98765,
    this.playSound = true,
    this.alertOnStart = true,
    this.titleFormatter,
    this.bodyFormatter,
  });

  /// Default notification title generator.
  String defaultTitle(UploadTask? task, QueueSummary summary) {
    if (summary.isUploading) {
      final totalInFlight = summary.totalActiveAndPending;
      if (totalInFlight == 1 && task != null) {
        return 'Uploading ${task.fileName}';
      }
      if (summary.enqueuedTasks > 0) {
        return 'Uploading $totalInFlight files (${summary.activeTasks} active)';
      }
      return 'Uploading ${summary.activeTasks} files';
    }
    if (summary.hasPaused && summary.isIdle) {
      if (summary.pausedTasks == 1 && task != null) {
        return 'Upload Paused: ${task.fileName}';
      }
      return 'Upload Paused (${summary.pausedTasks} files)';
    }
    if (summary.hasFailed && summary.isIdle) {
      return 'Upload Failed';
    }
    if (summary.enqueuedTasks > 0) {
      return 'Upload Enqueued';
    }
    if (summary.completedTasks > 0 &&
        summary.isIdle &&
        !summary.hasPaused &&
        !summary.hasFailed) {
      return summary.completedTasks == 1
          ? 'Upload Complete'
          : 'Uploads Completed';
    }
    return 'File Uploads';
  }

  /// Default notification body generator with progress, speed, and remaining file counts.
  String defaultBody(UploadTask? task, QueueSummary summary) {
    if (summary.isUploading) {
      final percent = summary.overallProgressPercent;
      final speed = summary.formattedSpeed;
      final remaining = summary.enqueuedTasks;
      final remainingText = remaining > 0 ? ' • $remaining pending' : '';
      if (summary.activeTasks == 1 &&
          summary.enqueuedTasks == 0 &&
          task != null) {
        return '${task.formattedUploadedSize} of ${task.formattedTotalSize} ($percent%) • $speed';
      }
      return '${summary.formattedUploadedSize} of ${summary.formattedTotalSize} ($percent%) • $speed$remainingText';
    }
    if (summary.hasPaused && summary.isIdle) {
      if (summary.pausedTasks == 1 && task != null) {
        return '${task.fileName} is paused. Tap to resume.';
      }
      return '${summary.pausedTasks} uploads paused. Tap to resume.';
    }
    if (summary.hasFailed && summary.isIdle) {
      return '${summary.failedTasks} ${summary.failedTasks == 1 ? "task" : "tasks"} failed to upload.';
    }
    if (summary.enqueuedTasks > 0) {
      return 'Starting upload...';
    }
    if (summary.completedTasks > 0 &&
        summary.isIdle &&
        !summary.hasPaused &&
        !summary.hasFailed) {
      if (summary.completedTasks == 1 && task != null) {
        return '${task.fileName} uploaded successfully.';
      }
      return 'All ${summary.completedTasks} files uploaded successfully.';
    }
    return '';
  }
}
