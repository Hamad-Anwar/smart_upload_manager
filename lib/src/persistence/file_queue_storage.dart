import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/upload_task.dart';
import 'queue_storage.dart';

/// File-based implementation of [QueueStorage] that stores tasks in a JSON file.
///
/// Features:
/// - Atomic writes using temporary files to prevent data corruption during unexpected app termination.
/// - In-memory cache for fast lookups.
/// - Safe error handling with automatic recovery.
class FileQueueStorage implements QueueStorage {
  final String? customDirectoryPath;
  final String fileName;

  File? _file;
  final Map<String, UploadTask> _cache = {};
  Completer<void>? _writeLock;

  FileQueueStorage({
    this.customDirectoryPath,
    this.fileName = 'upload_queue.json',
  });

  @override
  Future<void> init() async {
    final Directory dir;
    if (customDirectoryPath != null) {
      dir = Directory(customDirectoryPath!);
    } else {
      dir = await getApplicationDocumentsDirectory();
    }

    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    _file = File(p.join(dir.path, fileName));
    await _loadFromDisk();
  }

  Future<void> _loadFromDisk() async {
    if (_file == null || !await _file!.exists()) return;

    try {
      final content = await _file!.readAsString();
      if (content.trim().isEmpty) return;

      final dynamic decoded = jsonDecode(content);
      if (decoded is List) {
        _cache.clear();
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            final task = UploadTask.fromJson(item);
            _cache[task.id] = task;
          }
        }
      }
    } catch (e) {
      // In case of corruption, create a backup file and start clean
      try {
        final backupFile = File('${_file!.path}.corrupt.${DateTime.now().millisecondsSinceEpoch}');
        await _file!.copy(backupFile.path);
      } catch (_) {}
      _cache.clear();
    }
  }

  @override
  Future<List<UploadTask>> loadAll() async {
    return _cache.values.toList();
  }

  @override
  Future<void> saveTask(UploadTask task) async {
    _cache[task.id] = task;
    await _flushToDisk();
  }

  @override
  Future<void> saveAll(List<UploadTask> tasks) async {
    for (final task in tasks) {
      _cache[task.id] = task;
    }
    await _flushToDisk();
  }

  @override
  Future<void> deleteTask(String taskId) async {
    if (_cache.remove(taskId) != null) {
      await _flushToDisk();
    }
  }

  @override
  Future<void> clearAll() async {
    _cache.clear();
    await _flushToDisk();
  }

  /// Atomically writes the current in-memory cache to disk.
  Future<void> _flushToDisk() async {
    if (_file == null) return;

    // Mutex to serialize writes
    while (_writeLock != null) {
      await _writeLock!.future;
    }
    _writeLock = Completer<void>();

    try {
      final jsonList = _cache.values.map((t) => t.toJson()).toList();
      final jsonString = jsonEncode(jsonList);

      final tmpFile = File('${_file!.path}.tmp');
      await tmpFile.writeAsString(jsonString, flush: true);

      // Atomic rename
      if (await tmpFile.exists()) {
        await tmpFile.rename(_file!.path);
      }
    } catch (_) {
      // Fallback: direct write if rename failed
      try {
        final jsonList = _cache.values.map((t) => t.toJson()).toList();
        await _file!.writeAsString(jsonEncode(jsonList), flush: true);
      } catch (_) {}
    } finally {
      final lock = _writeLock;
      _writeLock = null;
      lock?.complete();
    }
  }

  @override
  Future<void> close() async {
    _cache.clear();
  }
}
