import 'package:flutter_test/flutter_test.dart';
import 'package:smart_upload_manager/smart_upload_manager.dart';

void main() {
  group('UploadTask', () {
    test('calculates progress and percentage accurately', () {
      final task = UploadTask(
        id: '1',
        filePath: '/tmp/test_video.mp4',
        url: 'https://example.com/upload',
        totalBytes: 1000,
        uploadedBytes: 250,
      );

      expect(task.progress, 0.25);
      expect(task.progressPercent, 25);
      expect(task.fileName, 'test_video.mp4');
    });

    test('serializes and deserializes to JSON correctly', () {
      final now = DateTime.now();
      final task = UploadTask(
        id: 'task-123',
        filePath: '/storage/doc.pdf',
        url: 'https://example.com/api',
        method: 'PUT',
        headers: {'Authorization': 'Bearer test-token'},
        data: {'userId': 'user-1'},
        priority: TaskPriority.high,
        status: UploadStatus.running,
        totalBytes: 2048,
        uploadedBytes: 1024,
        speed: 512.0,
        eta: const Duration(seconds: 2),
        retryCount: 1,
        maxRetries: 3,
        error: 'Timeout',
        createdAt: now,
        updatedAt: now,
        tag: 'documents',
        metadata: {'category': 'finance'},
        adapterType: 'resumable',
        resumableSessionId: 'sess-abc',
        resumableOffset: 1024,
        uploadedChunks: [1, 2],
        response: {'url': 'https://example.com/file.png'},
      );

      final json = task.toJson();
      final restored = UploadTask.fromJson(json);

      expect(restored.id, task.id);
      expect(restored.filePath, task.filePath);
      expect(restored.url, task.url);
      expect(restored.method, 'PUT');
      expect(restored.headers['Authorization'], 'Bearer test-token');
      expect(restored.priority, TaskPriority.high);
      expect(restored.status, UploadStatus.running);
      expect(restored.totalBytes, 2048);
      expect(restored.uploadedBytes, 1024);
      expect(restored.speed, 512.0);
      expect(restored.eta?.inSeconds, 2);
      expect(restored.retryCount, 1);
      expect(restored.maxRetries, 3);
      expect(restored.tag, 'documents');
      expect(restored.adapterType, 'resumable');
      expect(restored.resumableSessionId, 'sess-abc');
      expect(restored.resumableOffset, 1024);
      expect(restored.uploadedChunks, [1, 2]);
      expect(restored.response['url'], 'https://example.com/file.png');
    });

    test('formats byte strings properly', () {
      expect(UploadTask.formatBytes(500), '500.0 B');
      expect(UploadTask.formatBytes(1024), '1.0 KB');
      expect(UploadTask.formatBytes(1024 * 1024 * 15), '15.0 MB');
      expect(UploadTask.formatBytes(1024 * 1024 * 1024 * 2), '2.0 GB');
    });

    test('copyWith updates specified fields cleanly', () {
      final task = UploadTask(
        id: '1',
        filePath: '/tmp/file.txt',
        url: 'https://example.com',
      );

      final updated = task.copyWith(
        status: UploadStatus.completed,
        uploadedBytes: 100,
        totalBytes: 100,
      );

      expect(updated.id, '1');
      expect(updated.status, UploadStatus.completed);
      expect(updated.uploadedBytes, 100);
      expect(updated.totalBytes, 100);
      expect(updated.progress, 1.0);
    });
  });
}
