import 'dart:math';
import 'models/queue_summary.dart';
import 'models/task_priority.dart';
import 'models/upload_status.dart';
import 'models/upload_task.dart';

/// Priority-based in-memory task queue manager.
///
/// Ensures tasks are dequeued strictly by priority (critical > high > normal > low),
/// falling back to FIFO (earliest creation time) for equal priorities.
class UploadQueue {
  final Map<String, UploadTask> _tasks = {};

  /// Current count of all tasks in the queue.
  int get length => _tasks.length;

  /// Whether the queue is completely empty.
  bool get isEmpty => _tasks.isEmpty;

  /// Whether the queue contains tasks.
  bool get isNotEmpty => _tasks.isNotEmpty;

  /// Adds or updates a task in the queue.
  void add(UploadTask task) {
    _tasks[task.id] = task;
  }

  /// Adds a list of tasks (e.g. when restoring from persistence).
  void addAll(Iterable<UploadTask> tasks) {
    for (final task in tasks) {
      _tasks[task.id] = task;
    }
  }

  /// Retrieves a task by its [id], or null if not found.
  UploadTask? getTask(String id) => _tasks[id];

  /// Removes a task from the queue by its [id].
  UploadTask? remove(String id) => _tasks.remove(id);

  /// Clears all tasks from the queue.
  void clear() => _tasks.clear();

  /// Removes all completed and cancelled tasks.
  List<String> clearTerminalTasks() {
    final removedIds = <String>[];
    _tasks.removeWhere((id, task) {
      if (task.status.isTerminal) {
        removedIds.add(id);
        return true;
      }
      return false;
    });
    return removedIds;
  }

  /// Returns all tasks sorted logically:
  /// 1. Running tasks
  /// 2. Enqueued tasks by priority and age
  /// 3. Paused tasks
  /// 4. Failed tasks
  /// 5. Completed / Cancelled tasks
  List<UploadTask> getAllTasks() {
    final list = _tasks.values.toList();
    list.sort((a, b) {
      // 1. Running first (stably sorted FIFO by createdAt)
      if (a.status == UploadStatus.running && b.status == UploadStatus.running) {
        return a.createdAt.compareTo(b.createdAt);
      }
      if (a.status == UploadStatus.running) return -1;
      if (b.status == UploadStatus.running) return 1;

      // 2. Enqueued next (sorted by priority, then creation time FIFO)
      if (a.status == UploadStatus.enqueued && b.status == UploadStatus.enqueued) {
        final prioComp = b.priority.value.compareTo(a.priority.value);
        if (prioComp != 0) return prioComp;
        return a.createdAt.compareTo(b.createdAt);
      }
      if (a.status == UploadStatus.enqueued) return -1;
      if (b.status == UploadStatus.enqueued) return 1;

      // 3. Paused next (stably sorted FIFO by createdAt)
      if (a.status == UploadStatus.paused && b.status == UploadStatus.paused) {
        return a.createdAt.compareTo(b.createdAt);
      }
      if (a.status == UploadStatus.paused) return -1;
      if (b.status == UploadStatus.paused) return 1;

      // 4. Failed next (stably sorted FIFO by createdAt)
      if (a.status == UploadStatus.failed && b.status == UploadStatus.failed) {
        return a.createdAt.compareTo(b.createdAt);
      }
      if (a.status == UploadStatus.failed) return -1;
      if (b.status == UploadStatus.failed) return 1;

      // 5. Completed / Cancelled tasks (most recently completed or created first)
      final timeA = a.completedAt ?? a.createdAt;
      final timeB = b.completedAt ?? b.createdAt;
      return timeB.compareTo(timeA);
    });
    return list;
  }

  /// Returns pending enqueued tasks ordered by priority (highest first) and creation time (oldest first).
  List<UploadTask> getPendingTasks() {
    final pending = _tasks.values
        .where((t) => t.status == UploadStatus.enqueued)
        .toList();

    pending.sort((a, b) {
      final prioComp = b.priority.value.compareTo(a.priority.value);
      if (prioComp != 0) return prioComp;
      return a.createdAt.compareTo(b.createdAt);
    });

    return pending;
  }

  /// Returns tasks currently in [UploadStatus.running] state.
  List<UploadTask> getActiveTasks() {
    return _tasks.values
        .where((t) => t.status == UploadStatus.running)
        .toList();
  }

  /// Returns tasks currently in [UploadStatus.paused] state.
  List<UploadTask> getPausedTasks() {
    return _tasks.values
        .where((t) => t.status == UploadStatus.paused)
        .toList();
  }

  /// Returns tasks currently in [UploadStatus.completed] state.
  List<UploadTask> getCompletedTasks() {
    return _tasks.values
        .where((t) => t.status == UploadStatus.completed)
        .toList();
  }

  /// Returns tasks currently in [UploadStatus.failed] state.
  List<UploadTask> getFailedTasks() {
    return _tasks.values
        .where((t) => t.status == UploadStatus.failed)
        .toList();
  }

  /// Calculates a real-time snapshot summary of queue metrics.
  QueueSummary createSummary({bool isConnected = true}) {
    var activeCount = 0;
    var enqueuedCount = 0;
    var pausedCount = 0;
    var completedCount = 0;
    var failedCount = 0;
    var cancelledCount = 0;

    var totalBytes = 0;
    var uploadedBytes = 0;
    var aggregateSpeed = 0.0;

    for (final task in _tasks.values) {
      totalBytes += task.totalBytes;
      uploadedBytes += task.uploadedBytes;

      switch (task.status) {
        case UploadStatus.running:
          activeCount++;
          aggregateSpeed += task.speed;
          break;
        case UploadStatus.enqueued:
          enqueuedCount++;
          break;
        case UploadStatus.paused:
          pausedCount++;
          break;
        case UploadStatus.completed:
          completedCount++;
          break;
        case UploadStatus.failed:
          failedCount++;
          break;
        case UploadStatus.cancelled:
          cancelledCount++;
          break;
      }
    }

    return QueueSummary(
      totalTasks: _tasks.length,
      activeTasks: activeCount,
      enqueuedTasks: enqueuedCount,
      pausedTasks: pausedCount,
      completedTasks: completedCount,
      failedTasks: failedCount,
      cancelledTasks: cancelledCount,
      totalBytes: totalBytes,
      uploadedBytes: min(uploadedBytes, totalBytes > 0 ? totalBytes : uploadedBytes),
      aggregateSpeed: aggregateSpeed,
      isConnected: isConnected,
    );
  }
}
