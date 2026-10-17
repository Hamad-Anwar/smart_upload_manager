import '../models/upload_task.dart';

/// Abstract storage interface for persisting upload tasks across app restarts.
abstract class QueueStorage {
  /// Initializes the storage engine (opens files, creates directories/tables).
  Future<void> init();

  /// Loads all stored upload tasks.
  Future<List<UploadTask>> loadAll();

  /// Persists or updates a single task.
  Future<void> saveTask(UploadTask task);

  /// Persists a batch of tasks.
  Future<void> saveAll(List<UploadTask> tasks);

  /// Deletes a task by its [taskId].
  Future<void> deleteTask(String taskId);

  /// Clears all tasks from storage.
  Future<void> clearAll();

  /// Closes storage and releases any resources.
  Future<void> close();
}
