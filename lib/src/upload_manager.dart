import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'adapters/dio_adapter.dart';
import 'adapters/resumable_adapter.dart';
import 'adapters/s3_multipart_adapter.dart';
import 'adapters/simulated_adapter.dart';
import 'adapters/tus_adapter.dart';
import 'adapters/upload_adapter.dart';
import 'connectivity_monitor.dart';
import 'models/queue_summary.dart';
import 'models/task_priority.dart';
import 'models/upload_protocol.dart';
import 'models/upload_status.dart';
import 'models/upload_task.dart';
import 'notifications/notification_options.dart';
import 'notifications/upload_notification_manager.dart';
import 'persistence/file_queue_storage.dart';
import 'persistence/queue_storage.dart';
import 'retry_policy.dart';
import 'upload_queue.dart';

/// Callback to asynchronously provide fresh headers or authentication tokens.
typedef HeaderProvider = Future<Map<String, String>> Function(UploadTask task);

/// Callback invoked on progress updates for a specific task.
typedef TaskProgressCallback = void Function(double progress, double speed, Duration? eta);

/// Callback invoked when a specific task completes successfully.
typedef TaskStatusCallback = void Function(UploadTask task);

/// Callback invoked when a specific task fails.
typedef TaskErrorCallback = void Function(UploadTask task, dynamic error);

/// The core management engine for resilient, persistent, offline-tolerant file uploads.
class UploadManager {
  final QueueStorage storage;
  final ConnectivityMonitor connectivityMonitor;
  final RetryPolicy retryPolicy;
  final int maxConcurrentUploads;
  final HeaderProvider? headerProvider;
  final UploadNotificationManager notificationManager;

  final UploadQueue _queue = UploadQueue();
  final Map<String, UploadAdapter> _adapters = {};
  final Map<String, CancelToken> _cancelTokens = {};
  final Map<String, Timer> _retryTimers = {};
  final Map<String, DateTime> _lastProgressTimes = {};
  final Map<String, int> _lastProgressBytes = {};

  final Map<String, TaskProgressCallback> _taskProgressCallbacks = {};
  final Map<String, TaskStatusCallback> _taskSuccessCallbacks = {};
  final Map<String, TaskErrorCallback> _taskErrorCallbacks = {};

  final StreamController<UploadTask> _progressController =
      StreamController<UploadTask>.broadcast();
  final StreamController<UploadTask> _statusController =
      StreamController<UploadTask>.broadcast();
  final StreamController<QueueSummary> _summaryController =
      StreamController<QueueSummary>.broadcast();

  StreamSubscription<bool>? _connectivitySub;
  bool _isConnected = true;
  bool _isInitialized = false;
  Completer<void>? _initCompleter;
  final Uuid _uuid = const Uuid();

  UploadManager({
    QueueStorage? storage,
    ConnectivityMonitor? connectivityMonitor,
    RetryPolicy? retryPolicy,
    this.maxConcurrentUploads = 2,
    this.headerProvider,
    NotificationConfig notificationConfig = const NotificationConfig(),
  })  : storage = storage ?? FileQueueStorage(),
        connectivityMonitor = connectivityMonitor ?? DefaultConnectivityMonitor(),
        retryPolicy = retryPolicy ?? const RetryPolicy(),
        notificationManager = UploadNotificationManager(config: notificationConfig) {
    // Register default adapters
    registerAdapter(DioUploadAdapter());
    registerAdapter(ResumableUploadAdapter());
    registerAdapter(TusUploadAdapter());
    registerAdapter(S3MultipartUploadAdapter());
    registerAdapter(SimulatedUploadAdapter());
  }

  /// Stream emitting real-time progress updates for individual tasks.
  Stream<UploadTask> get progressStream => _progressController.stream;

  /// Stream emitting task lifecycle state changes.
  Stream<UploadTask> get taskStatusStream => _statusController.stream;

  /// Stream emitting aggregate queue summary metrics.
  Stream<QueueSummary> get queueSummaryStream => _summaryController.stream;

  /// Current queue summary snapshot.
  QueueSummary get summary => _queue.createSummary(isConnected: _isConnected);

  /// All tasks currently in the queue.
  List<UploadTask> get allTasks => _queue.getAllTasks();

  /// Registers a custom upload transport adapter.
  void registerAdapter(UploadAdapter adapter) {
    _adapters[adapter.id] = adapter;
  }

  /// Ensures storage and background monitors are initialized before operations.
  Future<void> _ensureInitialized() async {
    if (_isInitialized) return;
    if (_initCompleter != null) {
      await _initCompleter!.future;
      return;
    }
    await init();
  }

  /// Initializes storage, restores tasks, checks connectivity, and starts processing.
  Future<void> init() async {
    if (_isInitialized) return;
    _initCompleter = Completer<void>();

    try {
      await storage.init();
      await notificationManager.init();

      // Check connectivity
      _isConnected = await connectivityMonitor.isConnected;
      _connectivitySub = connectivityMonitor.onConnectivityChanged.listen(_onConnectivityChanged);

      // Restore stored tasks
      final loadedTasks = await storage.loadAll();
      final restoredTasks = <UploadTask>[];

      for (var task in loadedTasks) {
        // If task was running when app crashed/killed, recover it to enqueued
        if (task.status == UploadStatus.running) {
          task = task.copyWith(
            status: UploadStatus.enqueued,
            speed: 0.0,
            eta: null,
          );
          await storage.saveTask(task);
        }
        restoredTasks.add(task);
      }

      _queue.addAll(restoredTasks);
      _isInitialized = true;
      _emitSummary();

      // If online, process queue
      if (_isConnected) {
        _processQueue();
      }
    } finally {
      _initCompleter?.complete();
      _initCompleter = null;
    }
  }

  /// Watches a specific task's lifecycle and progress updates.
  Stream<UploadTask> watch(String taskId) {
    late StreamController<UploadTask> controller;
    StreamSubscription<UploadTask>? statusSub;
    StreamSubscription<UploadTask>? progSub;

    controller = StreamController<UploadTask>(
      onListen: () {
        final current = getTask(taskId);
        if (current != null) {
          controller.add(current);
        }
        statusSub = _statusController.stream
            .where((t) => t.id == taskId)
            .listen(controller.add);
        progSub = _progressController.stream
            .where((t) => t.id == taskId)
            .listen(controller.add);
      },
      onCancel: () {
        statusSub?.cancel();
        progSub?.cancel();
      },
    );

    return controller.stream;
  }

  /// Adds a new file upload task to the queue and starts processing.
  Future<UploadTask> add({
    /// Local path of the file to upload (optional if [filePaths] is provided).
    String? filePath,

    /// List of file paths to upload in a single request (e.g. multipart/form-data).
    List<String>? filePaths,

    /// Target HTTP endpoint URL.
    required String url,

    /// HTTP method (e.g. `'POST'`, `'PUT'`, `'PATCH'`). Defaults to `'POST'`.
    String method = 'POST',

    /// Additional HTTP headers to send with the request.
    Map<String, String> headers = const {},

    /// Additional form-data fields or body parameters.
    Map<String, dynamic> data = const {},

    /// The form field name for the file in multipart requests. Defaults to `'file'`.
    String fileFieldName = 'file',

    /// Priority level ([TaskPriority.low], [TaskPriority.normal], [TaskPriority.high], [TaskPriority.critical]). Defaults to [TaskPriority.normal].
    TaskPriority priority = TaskPriority.normal,

    /// Optional category or group tag for filtering tasks.
    String? tag,

    /// Custom application metadata attached to this task and persisted to disk.
    Map<String, dynamic> metadata = const {},

    /// Transport protocol ([UploadProtocol.standard], [UploadProtocol.tus], [UploadProtocol.resumable], [UploadProtocol.s3Multipart], etc.).
    UploadProtocol protocol = UploadProtocol.standard,

    /// Custom registered adapter identifier if using [UploadProtocol.custom].
    String? customAdapterId,

    /// Legacy string adapter identifier for backwards compatibility.
    String? adapterType,

    /// Maximum retry attempts override for this specific task.
    int? maxRetries,

    /// Virtual file size in bytes when using [UploadProtocol.simulated].
    int? simulatedFileSize,

    /// Direct callback receiving progress updates `(progress, speed, eta)`.
    TaskProgressCallback? onProgress,

    /// Direct callback triggered when this specific upload completes successfully.
    TaskStatusCallback? onSuccess,

    /// Direct callback triggered if this specific upload fails.
    TaskErrorCallback? onError,
  }) async {
    await _ensureInitialized();

    final effectivePaths = (filePaths != null && filePaths.isNotEmpty)
        ? filePaths
        : (filePath != null && filePath.isNotEmpty ? [filePath] : <String>[]);

    int totalBytes = 0;
    if (simulatedFileSize != null && simulatedFileSize > 0) {
      totalBytes = simulatedFileSize;
    } else {
      for (final p in effectivePaths) {
        final f = File(p);
        if (await f.exists()) {
          totalBytes += await f.length();
        }
      }
    }

    final task = UploadTask(
      id: _uuid.v4(),
      filePath: effectivePaths.isNotEmpty ? effectivePaths.first : '',
      filePaths: effectivePaths,
      url: url,
      method: method,
      headers: headers,
      data: data,
      fileFieldName: fileFieldName,
      priority: priority,
      status: UploadStatus.enqueued,
      totalBytes: totalBytes,
      tag: tag,
      metadata: metadata,
      protocol: protocol,
      customAdapterId: customAdapterId,
      adapterType: adapterType,
      maxRetries: maxRetries,
    );

    if (onProgress != null) _taskProgressCallbacks[task.id] = onProgress;
    if (onSuccess != null) _taskSuccessCallbacks[task.id] = onSuccess;
    if (onError != null) _taskErrorCallbacks[task.id] = onError;

    _queue.add(task);
    await storage.saveTask(task);

    _statusController.add(task);
    _emitSummary();

    if (_isConnected) {
      _processQueue();
    }

    return task;
  }

  /// Adds an upload task containing multiple files in a single HTTP multipart request.
  Future<UploadTask> addMultiple({
    required List<String> filePaths,
    required String url,
    String method = 'POST',
    Map<String, String> headers = const {},
    Map<String, dynamic> data = const {},
    String fileFieldName = 'files',
    TaskPriority priority = TaskPriority.normal,
    String? tag,
    Map<String, dynamic> metadata = const {},
    UploadProtocol protocol = UploadProtocol.standard,
    String? customAdapterId,
    String? adapterType,
    int? maxRetries,
    int? simulatedFileSize,
    TaskProgressCallback? onProgress,
    TaskStatusCallback? onSuccess,
    TaskErrorCallback? onError,
  }) =>
      add(
        filePaths: filePaths,
        url: url,
        method: method,
        headers: headers,
        data: data,
        fileFieldName: fileFieldName,
        priority: priority,
        tag: tag,
        metadata: metadata,
        protocol: protocol,
        customAdapterId: customAdapterId,
        adapterType: adapterType,
        maxRetries: maxRetries,
        simulatedFileSize: simulatedFileSize,
        onProgress: onProgress,
        onSuccess: onSuccess,
        onError: onError,
      );

  /// Pauses an active or enqueued task.
  Future<void> pause(String taskId) async {
    await _ensureInitialized();
    final task = _queue.getTask(taskId);
    if (task == null || !task.status.canPause) return;

    _retryTimers[taskId]?.cancel();
    _retryTimers.remove(taskId);

    final adapter = _getAdapterForTask(task);
    await adapter.pause(taskId);

    final cancelToken = _cancelTokens.remove(taskId);
    if (cancelToken != null && !cancelToken.isCancelled) {
      cancelToken.cancel('Paused by user');
    }

    final updated = task.copyWith(
      status: UploadStatus.paused,
      speed: 0.0,
      eta: null,
    );
    _queue.add(updated);
    await storage.saveTask(updated);

    _statusController.add(updated);
    _emitSummary(updated);
    _processQueue();
  }

  /// Pauses all active and enqueued tasks.
  Future<void> pauseAll() async {
    await _ensureInitialized();
    final active = _queue.getActiveTasks();
    final pending = _queue.getPendingTasks();

    for (final task in [...active, ...pending]) {
      await pause(task.id);
    }
  }

  /// Resumes a paused or failed task.
  Future<void> resume(String taskId) async {
    await _ensureInitialized();
    final task = _queue.getTask(taskId);
    if (task == null || !task.status.canResume) return;

    final updated = task.copyWith(
      status: UploadStatus.enqueued,
      error: null,
      speed: 0.0,
      eta: null,
    );
    _queue.add(updated);
    await storage.saveTask(updated);

    _statusController.add(updated);
    _emitSummary();

    if (_isConnected) {
      _processQueue();
    }
  }

  /// Resumes all paused and failed tasks.
  Future<void> resumeAll() async {
    await _ensureInitialized();
    final paused = _queue.getPausedTasks();
    final failed = _queue.getFailedTasks();

    for (final task in [...paused, ...failed]) {
      await resume(task.id);
    }
  }

  /// Cancels an upload task and marks it as cancelled.
  Future<void> cancel(String taskId) async {
    await _ensureInitialized();
    final task = _queue.getTask(taskId);
    if (task == null || task.status.isTerminal) return;

    _retryTimers[taskId]?.cancel();
    _retryTimers.remove(taskId);

    final adapter = _getAdapterForTask(task);
    await adapter.cancel(taskId);

    final cancelToken = _cancelTokens.remove(taskId);
    if (cancelToken != null && !cancelToken.isCancelled) {
      cancelToken.cancel('Cancelled by user');
    }

    final updated = task.copyWith(
      status: UploadStatus.cancelled,
      speed: 0.0,
      eta: null,
    );
    _queue.add(updated);
    await storage.saveTask(updated);

    _statusController.add(updated);
    _emitSummary(updated);
    _processQueue();
  }

  /// Cancels all active and pending tasks.
  Future<void> cancelAll() async {
    await _ensureInitialized();
    final tasks = _queue.getAllTasks().where((t) => !t.status.isTerminal);
    for (final task in tasks) {
      await cancel(task.id);
    }
  }

  /// Retries a failed or cancelled task immediately.
  Future<void> retry(String taskId) async {
    await _ensureInitialized();
    final task = _queue.getTask(taskId);
    if (task == null) return;

    _retryTimers[taskId]?.cancel();
    _retryTimers.remove(taskId);

    final updated = task.copyWith(
      status: UploadStatus.enqueued,
      retryCount: 0,
      error: null,
      speed: 0.0,
      eta: null,
    );
    _queue.add(updated);
    await storage.saveTask(updated);

    _statusController.add(updated);
    _emitSummary();

    if (_isConnected) {
      _processQueue();
    }
  }

  /// Retries all currently failed tasks.
  Future<void> retryAllFailed() async {
    await _ensureInitialized();
    final failed = _queue.getFailedTasks();
    for (final task in failed) {
      await retry(task.id);
    }
  }

  /// Deletes a task from the queue and persistent storage.
  Future<void> deleteTask(String taskId) async {
    await _ensureInitialized();
    await cancel(taskId);
    _queue.remove(taskId);
    _taskProgressCallbacks.remove(taskId);
    _taskSuccessCallbacks.remove(taskId);
    _taskErrorCallbacks.remove(taskId);
    await storage.deleteTask(taskId);
    _emitSummary();
  }

  /// Removes all completed and cancelled tasks from memory and storage.
  Future<void> clearCompleted() async {
    await _ensureInitialized();
    final removedIds = _queue.clearTerminalTasks();
    for (final id in removedIds) {
      _taskProgressCallbacks.remove(id);
      _taskSuccessCallbacks.remove(id);
      _taskErrorCallbacks.remove(id);
      await storage.deleteTask(id);
    }
    _emitSummary();
  }

  /// Retrieves a task by [id].
  UploadTask? getTask(String id) => _queue.getTask(id);

  // -------------------------------------------------------------
  // Internal Queue Execution Engine
  // -------------------------------------------------------------

  void _onConnectivityChanged(bool connected) {
    _isConnected = connected;
    _emitSummary();

    if (!_isConnected) {
      // Pause or hold active uploads gracefully
      final active = _queue.getActiveTasks();
      for (final task in active) {
        _cancelTokens[task.id]?.cancel('Network connection lost');
        final updated = task.copyWith(
          status: UploadStatus.enqueued,
          speed: 0.0,
          eta: null,
        );
        _queue.add(updated);
        storage.saveTask(updated);
        _statusController.add(updated);
      }
      _emitSummary();
    } else {
      // Network restored: resume queued uploads
      _processQueue();
    }
  }

  void _processQueue() {
    if (!_isConnected) return;

    final activeCount = _queue.getActiveTasks().length;
    final availableSlots = maxConcurrentUploads - activeCount;

    if (availableSlots <= 0) return;

    final pending = _queue.getPendingTasks();
    final tasksToStart = pending.take(availableSlots);

    for (final task in tasksToStart) {
      _startUpload(task);
    }
  }

  Future<void> _startUpload(UploadTask initialTask) async {
    var task = initialTask;
    final cancelToken = CancelToken();
    _cancelTokens[task.id] = cancelToken;

    // Transition to running
    task = task.copyWith(
      status: UploadStatus.running,
      speed: 0.0,
      eta: null,
    );
    _queue.add(task);
    await storage.saveTask(task);
    _statusController.add(task);
    _emitSummary(task);

    final adapter = _getAdapterForTask(task);

    // Refresh headers/tokens if provider supplied
    if (headerProvider != null) {
      try {
        final freshHeaders = await headerProvider!(task);
        task = task.copyWith(headers: {...task.headers, ...freshHeaders});
      } catch (e) {
        debugPrint('Token / header provider error: $e');
      }
    }

    _lastProgressTimes[task.id] = DateTime.now();
    _lastProgressBytes[task.id] = task.uploadedBytes;

    try {
      final response = await adapter.upload(
        task: task,
        onProgress: (sent, total) => _handleProgress(task.id, sent, total),
        cancelToken: cancelToken,
      );

      if (response.isSuccess) {
        final current = _queue.getTask(task.id) ?? task;
        final completed = current.copyWith(
          status: UploadStatus.completed,
          uploadedBytes: totalBytesOrFallback(current.totalBytes, current.uploadedBytes),
          completedAt: DateTime.now(),
          speed: 0.0,
          eta: null,
          response: response.data,
        );
        _queue.add(completed);
        await storage.saveTask(completed);
        _statusController.add(completed);
        _emitSummary(completed);

        // Trigger task success callback
        _taskSuccessCallbacks.remove(task.id)?.call(completed);
        _taskProgressCallbacks.remove(task.id);
        _taskErrorCallbacks.remove(task.id);
      } else {
        throw DioException(
          requestOptions: RequestOptions(path: task.url),
          response: Response(
            statusCode: response.statusCode,
            data: response.data,
            requestOptions: RequestOptions(path: task.url),
          ),
          type: DioExceptionType.badResponse,
        );
      }
    } catch (e) {
      if (cancelToken.isCancelled) {
        return;
      }
      await _handleFailure(task, e);
    } finally {
      _cancelTokens.remove(task.id);
      _lastProgressTimes.remove(task.id);
      _lastProgressBytes.remove(task.id);
      _processQueue();
    }
  }

  int totalBytesOrFallback(int total, int uploaded) =>
      total > 0 ? total : uploaded;

  void _handleProgress(String taskId, int sent, int total) {
    final current = _queue.getTask(taskId);
    if (current == null || current.status != UploadStatus.running) return;

    final now = DateTime.now();
    final lastTime = _lastProgressTimes[taskId] ?? now;
    final lastBytes = _lastProgressBytes[taskId] ?? current.uploadedBytes;

    final elapsedMs = now.difference(lastTime).inMilliseconds;
    double speed = current.speed;
    Duration? eta;

    if (elapsedMs > 250) {
      final bytesDiff = sent - lastBytes;
      if (bytesDiff > 0) {
        final instantSpeed = (bytesDiff / (elapsedMs / 1000.0));
        speed = speed == 0 ? instantSpeed : (speed * 0.7 + instantSpeed * 0.3);
      }
      _lastProgressTimes[taskId] = now;
      _lastProgressBytes[taskId] = sent;

      final remainingBytes = total - sent;
      if (speed > 0 && remainingBytes > 0) {
        eta = Duration(seconds: (remainingBytes / speed).round());
      }
    }

    final updated = current.copyWith(
      uploadedBytes: sent,
      totalBytes: total > 0 ? total : current.totalBytes,
      speed: speed,
      eta: eta ?? current.eta,
    );

    _queue.add(updated);
    _progressController.add(updated);

    // Trigger per-task progress callback
    _taskProgressCallbacks[taskId]?.call(updated.progress, updated.speed, updated.eta);

    // Throttled notification update
    notificationManager.updateProgress(
      summary: summary,
      activeTask: updated,
    );
  }

  Future<void> _handleFailure(UploadTask task, dynamic error) async {
    final current = _queue.getTask(task.id) ?? task;
    final nextRetryCount = current.retryCount + 1;
    final shouldRetry = retryPolicy.shouldRetry(
      error,
      current.retryCount,
      maxRetriesOverride: current.maxRetries,
    );

    if (!_isConnected) {
      final offlineTask = current.copyWith(
        status: UploadStatus.enqueued,
        error: 'Waiting for network connection...',
        speed: 0.0,
        eta: null,
      );
      _queue.add(offlineTask);
      await storage.saveTask(offlineTask);
      _statusController.add(offlineTask);
      _emitSummary();
      return;
    }

    if (shouldRetry) {
      final delay = retryPolicy.calculateDelay(nextRetryCount);
      final scheduled = current.copyWith(
        status: UploadStatus.enqueued,
        retryCount: nextRetryCount,
        error: 'Retrying in ${delay.inSeconds}s (${error.toString()})',
        speed: 0.0,
        eta: null,
      );
      _queue.add(scheduled);
      await storage.saveTask(scheduled);
      _statusController.add(scheduled);
      _emitSummary();

      _retryTimers[task.id] = Timer(delay, () {
        _retryTimers.remove(task.id);
        _processQueue();
      });
    } else {
      final failed = current.copyWith(
        status: UploadStatus.failed,
        error: error.toString(),
        speed: 0.0,
        eta: null,
      );
      _queue.add(failed);
      await storage.saveTask(failed);
      _statusController.add(failed);
      _emitSummary(failed);

      // Trigger error callback
      _taskErrorCallbacks[task.id]?.call(failed, error);
    }
  }

  UploadAdapter _getAdapterForTask(UploadTask task) {
    if (_adapters.containsKey(task.adapterType)) {
      return _adapters[task.adapterType]!;
    }
    return _adapters['dio']!;
  }

  void _emitSummary([UploadTask? activeTask]) {
    final sum = summary;
    _summaryController.add(sum);
    final active = activeTask ?? (_queue.getActiveTasks().isNotEmpty ? _queue.getActiveTasks().first : null);
    notificationManager.updateProgress(summary: sum, activeTask: active);
  }

  /// Closes the manager and releases streams, adapters, and listeners.
  Future<void> dispose() async {
    _connectivitySub?.cancel();
    for (final timer in _retryTimers.values) {
      timer.cancel();
    }
    _retryTimers.clear();

    for (final token in _cancelTokens.values) {
      if (!token.isCancelled) {
        token.cancel('UploadManager disposed');
      }
    }
    _cancelTokens.clear();

    for (final adapter in _adapters.values) {
      await adapter.dispose();
    }

    _taskProgressCallbacks.clear();
    _taskSuccessCallbacks.clear();
    _taskErrorCallbacks.clear();

    notificationManager.dispose();
    await _progressController.close();
    await _statusController.close();
    await _summaryController.close();
    await storage.close();
  }
}
