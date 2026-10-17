import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_upload_manager/smart_upload_manager.dart';

void main() {
  group('QueueStorage', () {
    test('InMemoryQueueStorage saves and loads correctly', () async {
      final storage = InMemoryQueueStorage();
      await storage.init();

      final task = UploadTask(
        id: 't1',
        filePath: '/tmp/f.txt',
        url: 'https://example.com',
      );

      await storage.saveTask(task);
      var loaded = await storage.loadAll();
      expect(loaded.length, 1);
      expect(loaded.first.id, 't1');

      await storage.deleteTask('t1');
      loaded = await storage.loadAll();
      expect(loaded, isEmpty);
    });

    test('FileQueueStorage persists across instance reloads with atomic writes', () async {
      final tempDir = await Directory.systemTemp.createTemp('upload_storage_test_');

      try {
        final storage1 = FileQueueStorage(customDirectoryPath: tempDir.path);
        await storage1.init();

        final t1 = UploadTask(
          id: 'task-persistent-1',
          filePath: '/storage/video.mp4',
          url: 'https://api.example.com/video',
          priority: TaskPriority.high,
          totalBytes: 5000,
          uploadedBytes: 1500,
        );

        final t2 = UploadTask(
          id: 'task-persistent-2',
          filePath: '/storage/photo.jpg',
          url: 'https://api.example.com/photo',
          priority: TaskPriority.normal,
        );

        await storage1.saveAll([t1, t2]);
        await storage1.close();

        // Reload fresh storage instance from same disk directory
        final storage2 = FileQueueStorage(customDirectoryPath: tempDir.path);
        await storage2.init();

        final reloaded = await storage2.loadAll();
        expect(reloaded.length, 2);

        final reloadedT1 = reloaded.firstWhere((t) => t.id == 'task-persistent-1');
        expect(reloadedT1.uploadedBytes, 1500);
        expect(reloadedT1.priority, TaskPriority.high);

        // Delete t2
        await storage2.deleteTask('task-persistent-2');
        final remaining = await storage2.loadAll();
        expect(remaining.length, 1);
        expect(remaining.first.id, 'task-persistent-1');

        await storage2.close();
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    });
  });
}
