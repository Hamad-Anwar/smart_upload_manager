library;

import 'dart:async';
import 'dart:io';
import 'src/adapters/upload_adapter.dart';
import 'src/connectivity_monitor.dart';
import 'src/models/queue_summary.dart';
import 'src/models/task_priority.dart';
import 'src/models/upload_protocol.dart';
import 'src/models/upload_task.dart';
import 'src/notifications/notification_options.dart';
import 'src/persistence/queue_storage.dart';
import 'src/retry_policy.dart';
import 'src/upload_manager.dart';

export 'src/adapters/dio_adapter.dart';
export 'src/adapters/resumable_adapter.dart';
export 'src/adapters/s3_multipart_adapter.dart';
export 'src/adapters/simulated_adapter.dart';
export 'src/adapters/tus_adapter.dart';
export 'src/adapters/upload_adapter.dart';
export 'src/connectivity_monitor.dart';
export 'src/models/queue_summary.dart';
export 'src/models/task_priority.dart';
export 'src/models/upload_protocol.dart';
export 'src/models/upload_status.dart';
export 'src/models/upload_task.dart';
export 'src/notifications/notification_options.dart';
export 'src/notifications/upload_notification_manager.dart';
export 'src/persistence/file_queue_storage.dart';
export 'src/persistence/in_memory_queue_storage.dart';
export 'src/persistence/queue_storage.dart';
export 'src/retry_policy.dart';
export 'src/upload_manager.dart';
export 'src/upload_queue.dart';
export 'src/widgets/upload_progress_bar.dart';
export 'src/widgets/upload_task_tile.dart';

/// The primary public interface and singleton manager for `smart_upload_manager`.
///
/// Provides a developer-friendly API to enqueue files, track real-time upload progress,
/// configure retry strategies, and survive network drops and app restarts.
class SmartUploadManager {
  static SmartUploadManager? _instance;

  /// The underlying [UploadManager] coordinating queue execution.
  final UploadManager manager;

  SmartUploadManager._(this.manager);

  /// Access the global singleton instance.
  ///
  /// Automatically initializes with robust defaults on first use if
  /// [SmartUploadManager.initialize] was not explicitly called.
  static SmartUploadManager get instance {
    _instance ??= SmartUploadManager._(UploadManager());
    return _instance!;
  }

  /// Initializes the singleton instance with custom configuration.
  ///
  /// Example:
  /// ```dart
  /// await SmartUploadManager.initialize(
  ///   maxConcurrentUploads: 3,
  ///   retryPolicy: RetryPolicy(maxRetries: 5),
  ///   notificationConfig: NotificationConfig(enabled: true),
  /// );
  /// ```
  static Future<SmartUploadManager> initialize({
    QueueStorage? storage,
    ConnectivityMonitor? connectivityMonitor,
    RetryPolicy? retryPolicy,
    int maxConcurrentUploads = 2,
    HeaderProvider? headerProvider,
    NotificationConfig notificationConfig = const NotificationConfig(),
  }) async {
    final manager = UploadManager(
      storage: storage,
      connectivityMonitor: connectivityMonitor,
      retryPolicy: retryPolicy,
      maxConcurrentUploads: maxConcurrentUploads,
      headerProvider: headerProvider,
      notificationConfig: notificationConfig,
    );

    await manager.init();
    _instance = SmartUploadManager._(manager);
    return _instance!;
  }

  /// Creates a standalone, isolated queue instance (useful for multi-tenant or sandboxed queues).
  static Future<SmartUploadManager> createInstance({
    QueueStorage? storage,
    ConnectivityMonitor? connectivityMonitor,
    RetryPolicy? retryPolicy,
    int maxConcurrentUploads = 2,
    HeaderProvider? headerProvider,
    NotificationConfig notificationConfig = const NotificationConfig(),
  }) async {
    final manager = UploadManager(
      storage: storage,
      connectivityMonitor: connectivityMonitor,
      retryPolicy: retryPolicy,
      maxConcurrentUploads: maxConcurrentUploads,
      headerProvider: headerProvider,
      notificationConfig: notificationConfig,
    );

    await manager.init();
    return SmartUploadManager._(manager);
  }

  /// Ultra-simple one-line upload helper.
  ///
  /// Automatically enqueues the file, applies retries, tracks progress, and optionally
  /// triggers callbacks when progress changes, finishes, or errors.
  ///
  /// ```dart
  /// await SmartUploadManager.upload(
  ///   file: '/path/to/video.mp4', // accepts File or String filePath
  ///   url: 'https://api.example.com/uploads',
  ///   protocol: UploadProtocol.tus, // Strongly-typed enum!
  ///   onProgress: (progress, speed, eta) => print('${(progress * 100).toInt()}%'),
  ///   onSuccess: (task) => print('Done!'),
  /// );
  /// ```
  static Future<UploadTask> upload({
    /// The file to upload. Accepts either a [File] object or a [String] local file path.
    required dynamic file,

    /// Target HTTP endpoint URL (e.g. `'https://api.example.com/uploads'`).
    required String url,

    /// Transport protocol to use:
    /// - [UploadProtocol.standard]: Standard multipart/form-data or binary streaming.
    /// - [UploadProtocol.resumable]: Byte-range chunks via `Content-Range`.
    /// - [UploadProtocol.tus]: Open Tus.io protocol standard (v1.0.0).
    /// - [UploadProtocol.s3Multipart]: Direct AWS S3 multipart upload.
    /// - [UploadProtocol.simulated]: Mock transfer simulator for testing and offline demos.
    UploadProtocol protocol = UploadProtocol.standard,

    /// HTTP method used for the upload (e.g. `'POST'`, `'PUT'`, `'PATCH'`). Defaults to `'POST'`.
    String method = 'POST',

    /// Additional HTTP headers to send with the request (e.g. `{'Authorization': 'Bearer $token'}`).
    Map<String, String> headers = const {},

    /// Extra form fields or body parameters to send alongside the file (e.g. `{'caption': 'Vacation', 'album_id': '12'}`).
    Map<String, dynamic> data = const {},

    /// The form field name for the file in multipart requests. Defaults to `'file'`.
    String fileFieldName = 'file',

    /// Priority level for queue ordering:
    /// - [TaskPriority.low]: Background sync, non-urgent.
    /// - [TaskPriority.normal]: Standard priority (default).
    /// - [TaskPriority.high]: User-waiting actions.
    /// - [TaskPriority.critical]: Front-of-line priority.
    TaskPriority priority = TaskPriority.normal,

    /// Optional category or group tag for filtering tasks (e.g. `'avatars'`, `'videos'`, `'chat'`).
    String? tag,

    /// Custom application metadata attached to this task and persisted to disk (e.g. `{'userId': 'user_123', 'chatId': 'c_98'}`).
    Map<String, dynamic> metadata = const {},

    /// Maximum retry attempts for this specific upload, overriding the queue's default [RetryPolicy].
    int? maxRetries,

    /// Virtual file size in bytes when using [UploadProtocol.simulated] for testing or demos.
    int? simulatedFileSize,

    /// Direct callback receiving progress updates `(progress: 0.0 to 1.0, speed: bytes/sec, eta: Duration?)`.
    TaskProgressCallback? onProgress,

    /// Direct callback triggered when this specific upload completes successfully.
    TaskStatusCallback? onSuccess,

    /// Direct callback triggered if this specific upload fails.
    TaskErrorCallback? onError,
  }) {
    if (file is List) {
      return uploadMultiple(
        files: file,
        url: url,
        protocol: protocol,
        method: method,
        headers: headers,
        data: data,
        fileFieldName: fileFieldName == 'file' ? 'files' : fileFieldName,
        priority: priority,
        tag: tag,
        metadata: metadata,
        maxRetries: maxRetries,
        simulatedFileSize: simulatedFileSize,
        onProgress: onProgress,
        onSuccess: onSuccess,
        onError: onError,
      );
    }

    final path = file is File ? file.path : file.toString();
    return instance.add(
      filePath: path,
      url: url,
      protocol: protocol,
      method: method,
      headers: headers,
      data: data,
      fileFieldName: fileFieldName,
      priority: priority,
      tag: tag,
      metadata: metadata,
      maxRetries: maxRetries,
      simulatedFileSize: simulatedFileSize,
      onProgress: onProgress,
      onSuccess: onSuccess,
      onError: onError,
    );
  }

  /// Uploads multiple files simultaneously in a single HTTP request (e.g. multipart/form-data with multiple file fields).
  ///
  /// ```dart
  /// final task = await SmartUploadManager.uploadMultiple(
  ///   files: [file1, file2],
  ///   url: 'https://api.example.com/upload/multiple',
  ///   fileFieldName: 'files',
  ///   headers: {'x-api-key': '...'},
  /// );
  /// ```
  static Future<UploadTask> uploadMultiple({
    /// List of files to upload in one request. Accepts [File] objects or [String] file paths.
    required List<dynamic> files,

    /// Target HTTP endpoint URL.
    required String url,

    /// Transport protocol. Defaults to [UploadProtocol.standard].
    UploadProtocol protocol = UploadProtocol.standard,

    /// HTTP method (e.g., `'POST'`, `'PUT'`). Defaults to `'POST'`.
    String method = 'POST',

    /// Additional HTTP headers to attach to the request.
    Map<String, String> headers = const {},

    /// Additional form-data fields or body parameters.
    Map<String, dynamic> data = const {},

    /// Form field name used for files in multipart requests. Defaults to `'files'`.
    String fileFieldName = 'files',

    /// Priority level for queue ordering.
    TaskPriority priority = TaskPriority.normal,

    /// Optional category or group tag.
    String? tag,

    /// Custom application metadata attached to this task.
    Map<String, dynamic> metadata = const {},

    /// Maximum retry attempts override for this specific task.
    int? maxRetries,

    /// Virtual file size in bytes for simulation.
    int? simulatedFileSize,

    /// Direct callback receiving progress updates `(progress, speed, eta)`.
    TaskProgressCallback? onProgress,

    /// Direct callback triggered when this specific upload completes successfully.
    TaskStatusCallback? onSuccess,

    /// Direct callback triggered if this specific upload fails.
    TaskErrorCallback? onError,
  }) {
    final paths = files
        .map((f) => f is File ? f.path : f.toString())
        .where((p) => p.isNotEmpty)
        .toList();

    return instance.addMultiple(
      filePaths: paths,
      url: url,
      protocol: protocol,
      method: method,
      headers: headers,
      data: data,
      fileFieldName: fileFieldName,
      priority: priority,
      tag: tag,
      metadata: metadata,
      maxRetries: maxRetries,
      simulatedFileSize: simulatedFileSize,
      onProgress: onProgress,
      onSuccess: onSuccess,
      onError: onError,
    );
  }

  /// Adds a new file or multiple files to the persistent upload queue.
  ///
  /// The upload begins as soon as network conditions and concurrency limits allow.
  Future<UploadTask> add({
    /// Local path of the file to be uploaded. Optional if [filePaths] is provided.
    String? filePath,

    /// List of file paths to upload together in one request.
    List<String>? filePaths,

    /// Target HTTP endpoint URL.
    required String url,

    /// Transport protocol ([UploadProtocol.standard], [UploadProtocol.tus], [UploadProtocol.resumable], [UploadProtocol.s3Multipart], etc.). Defaults to [UploadProtocol.standard].
    UploadProtocol protocol = UploadProtocol.standard,

    /// HTTP method (e.g., `'POST'`, `'PUT'`, `'PATCH'`). Defaults to `'POST'`.
    String method = 'POST',

    /// Additional HTTP headers to attach to the request.
    Map<String, String> headers = const {},

    /// Additional form-data fields or body parameters.
    Map<String, dynamic> data = const {},

    /// Form field name for the file in multipart requests. Defaults to `'file'`.
    String fileFieldName = 'file',

    /// Priority level ([TaskPriority.low], [TaskPriority.normal], [TaskPriority.high], [TaskPriority.critical]). Defaults to [TaskPriority.normal].
    TaskPriority priority = TaskPriority.normal,

    /// Optional category or group tag (e.g. `'avatars'`, `'documents'`).
    String? tag,

    /// Custom application metadata attached to this task and persisted to disk.
    Map<String, dynamic> metadata = const {},

    /// Custom registered adapter identifier if using [UploadProtocol.custom].
    String? customAdapterId,

    /// Legacy string adapter identifier for backwards compatibility.
    String? adapterType,

    /// Maximum retry attempts override for this specific task.
    int? maxRetries,

    /// Virtual file size in bytes for simulation.
    int? simulatedFileSize,

    /// Progress callback for this specific task `(progress, speed, eta)`.
    TaskProgressCallback? onProgress,

    /// Completion callback when this task finishes successfully.
    TaskStatusCallback? onSuccess,

    /// Error callback if this task fails.
    TaskErrorCallback? onError,
  }) {
    return manager.add(
      filePath: filePath,
      filePaths: filePaths,
      url: url,
      protocol: protocol,
      method: method,
      headers: headers,
      data: data,
      fileFieldName: fileFieldName,
      priority: priority,
      tag: tag,
      metadata: metadata,
      customAdapterId: customAdapterId,
      adapterType: adapterType,
      maxRetries: maxRetries,
      simulatedFileSize: simulatedFileSize,
      onProgress: onProgress,
      onSuccess: onSuccess,
      onError: onError,
    );
  }

  /// Adds multiple files to be uploaded in a single request.
  Future<UploadTask> addMultiple({
    required List<String> filePaths,
    required String url,
    UploadProtocol protocol = UploadProtocol.standard,
    String method = 'POST',
    Map<String, String> headers = const {},
    Map<String, dynamic> data = const {},
    String fileFieldName = 'files',
    TaskPriority priority = TaskPriority.normal,
    String? tag,
    Map<String, dynamic> metadata = const {},
    String? customAdapterId,
    String? adapterType,
    int? maxRetries,
    int? simulatedFileSize,
    TaskProgressCallback? onProgress,
    TaskStatusCallback? onSuccess,
    TaskErrorCallback? onError,
  }) {
    return manager.addMultiple(
      filePaths: filePaths,
      url: url,
      protocol: protocol,
      method: method,
      headers: headers,
      data: data,
      fileFieldName: fileFieldName,
      priority: priority,
      tag: tag,
      metadata: metadata,
      customAdapterId: customAdapterId,
      adapterType: adapterType,
      maxRetries: maxRetries,
      simulatedFileSize: simulatedFileSize,
      onProgress: onProgress,
      onSuccess: onSuccess,
      onError: onError,
    );
  }

  /// Watches a specific task's lifecycle and progress updates.
  Stream<UploadTask> watch(String taskId) => manager.watch(taskId);

  /// Stream emitting real-time progress for active upload tasks (0.0 to 1.0, speed, ETA).
  Stream<UploadTask> get progressStream => manager.progressStream;

  /// Stream emitting task lifecycle events (enqueued, running, paused, completed, failed, cancelled).
  Stream<UploadTask> get statusStream => manager.taskStatusStream;

  /// Stream emitting aggregate queue summary metrics.
  Stream<QueueSummary> get queueSummaryStream => manager.queueSummaryStream;

  /// Current queue summary snapshot.
  QueueSummary get summary => manager.summary;

  /// List of all tasks currently tracked by the queue.
  List<UploadTask> get allTasks => manager.allTasks;

  /// Retrieves a task by its [id].
  UploadTask? getTask(String id) => manager.getTask(id);

  /// Pauses an active or enqueued task.
  Future<void> pause(String taskId) => manager.pause(taskId);

  /// Pauses all active and pending uploads in the queue.
  Future<void> pauseAll() => manager.pauseAll();

  /// Resumes a paused or failed task.
  Future<void> resume(String taskId) => manager.resume(taskId);

  /// Resumes all paused and failed tasks in the queue.
  Future<void> resumeAll() => manager.resumeAll();

  /// Cancels an upload task.
  Future<void> cancel(String taskId) => manager.cancel(taskId);

  /// Cancels all active and pending uploads in the queue.
  Future<void> cancelAll() => manager.cancelAll();

  /// Retries a failed or cancelled task immediately.
  Future<void> retry(String taskId) => manager.retry(taskId);

  /// Retries all currently failed tasks in the queue.
  Future<void> retryAllFailed() => manager.retryAllFailed();

  /// Deletes a task from the queue and storage.
  Future<void> deleteTask(String taskId) => manager.deleteTask(taskId);

  /// Clears all completed and cancelled tasks from the queue.
  Future<void> clearCompleted() => manager.clearCompleted();

  /// Registers a custom transport adapter (e.g. S3, Tus, custom REST).
  void registerAdapter(UploadAdapter adapter) =>
      manager.registerAdapter(adapter);

  /// Requests or checks notification permissions from the OS.
  Future<bool> requestNotificationPermission() =>
      manager.notificationManager.requestPermissions();

  /// Displays an immediate test notification to verify OS notification permissions and display.
  Future<void> sendTestNotification() =>
      manager.notificationManager.sendTestNotification();

  /// Disposes the queue and cleans up resources.
  Future<void> dispose() => manager.dispose();
}

/// Backwards compatibility alias for [SmartUploadManager].
typedef ReliableUploadQueue = SmartUploadManager;

/// Convenience extension on [File] for ultra-simple uploads.
extension SmartUploadFileX on File {
  /// Enqueues this file directly into the upload queue.
  ///
  /// ```dart
  /// final file = File('/path/to/video.mp4');
  /// final task = await file.upload(
  ///   url: 'https://api.example.com/uploads',
  ///   protocol: UploadProtocol.tus,
  /// );
  /// ```
  Future<UploadTask> upload({
    /// Target HTTP endpoint URL (e.g. `'https://api.example.com/uploads'`).
    required String url,

    /// Transport protocol ([UploadProtocol.standard], [UploadProtocol.tus], [UploadProtocol.resumable], [UploadProtocol.s3Multipart], etc.).
    UploadProtocol protocol = UploadProtocol.standard,

    /// HTTP method (e.g., `'POST'`, `'PUT'`, `'PATCH'`). Defaults to `'POST'`.
    String method = 'POST',

    /// Additional HTTP headers to send with the request (e.g. `{'Authorization': 'Bearer $token'}`).
    Map<String, String> headers = const {},

    /// Extra form fields or body parameters.
    Map<String, dynamic> data = const {},

    /// Form field name for the file in multipart requests. Defaults to `'file'`.
    String fileFieldName = 'file',

    /// Priority level ([TaskPriority.low], [TaskPriority.normal], [TaskPriority.high], [TaskPriority.critical]). Defaults to [TaskPriority.normal].
    TaskPriority priority = TaskPriority.normal,

    /// Optional category or group tag (e.g. `'avatars'`, `'videos'`).
    String? tag,

    /// Custom application metadata attached to this task.
    Map<String, dynamic> metadata = const {},

    /// Maximum retry attempts override for this specific upload.
    int? maxRetries,

    /// Virtual file size in bytes when using [UploadProtocol.simulated] for testing or demos.
    int? simulatedFileSize,

    /// Direct callback receiving progress updates `(progress, speed, eta)`.
    TaskProgressCallback? onProgress,

    /// Direct callback triggered when this specific upload completes successfully.
    TaskStatusCallback? onSuccess,

    /// Direct callback triggered if this specific upload fails.
    TaskErrorCallback? onError,
  }) {
    return SmartUploadManager.upload(
      file: path,
      url: url,
      protocol: protocol,
      method: method,
      headers: headers,
      data: data,
      fileFieldName: fileFieldName,
      priority: priority,
      tag: tag,
      metadata: metadata,
      maxRetries: maxRetries,
      simulatedFileSize: simulatedFileSize,
      onProgress: onProgress,
      onSuccess: onSuccess,
      onError: onError,
    );
  }
}
