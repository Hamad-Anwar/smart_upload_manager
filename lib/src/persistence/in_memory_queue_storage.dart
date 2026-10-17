import '../models/upload_task.dart';
import 'queue_storage.dart';

/// In-memory implementation of [QueueStorage], useful for unit tests or ephemeral queues.
class InMemoryQueueStorage implements QueueStorage {
  final Map<String, UploadTask> _tasks = {};

  @override
  Future<void> init() async {}

  @override
  Future<List<UploadTask>> loadAll() async {
    return _tasks.values.toList();
  }

  @override
  Future<void> saveTask(UploadTask task) async {
    _tasks[task.id] = task;
  }

  @override
  Future<void> saveAll(List<UploadTask> tasks) async {
    for (final task in tasks) {
      _tasks[task.id] = task;
    }
  }

  @override
  Future<void> deleteTask(String taskId) async {
    _tasks.remove(taskId);
  }

  @override
  Future<void> clearAll() async {
    _tasks.clear();
  }

  @override
  Future<void> close() async {
    _tasks.clear();
  }
}
