import 'package:flutter_test/flutter_test.dart';
import 'package:smart_upload_manager/smart_upload_manager.dart';

void main() {
  group('UploadQueue', () {
    late UploadQueue queue;

    setUp(() {
      queue = UploadQueue();
    });

    test('orders pending tasks by priority then FIFO creation time', () {
      final now = DateTime.now();

      final lowTask = UploadTask(
        id: 'low',
        filePath: '/tmp/low.mp4',
        url: 'https://example.com',
        priority: TaskPriority.low,
        createdAt: now.add(const Duration(seconds: 1)),
      );

      final normalEarly = UploadTask(
        id: 'normal-1',
        filePath: '/tmp/n1.mp4',
        url: 'https://example.com',
        priority: TaskPriority.normal,
        createdAt: now.add(const Duration(seconds: 2)),
      );

      final normalLater = UploadTask(
        id: 'normal-2',
        filePath: '/tmp/n2.mp4',
        url: 'https://example.com',
        priority: TaskPriority.normal,
        createdAt: now.add(const Duration(seconds: 3)),
      );

      final criticalTask = UploadTask(
        id: 'critical',
        filePath: '/tmp/crit.mp4',
        url: 'https://example.com',
        priority: TaskPriority.critical,
        createdAt: now.add(const Duration(seconds: 4)),
      );

      final highTask = UploadTask(
        id: 'high',
        filePath: '/tmp/high.mp4',
        url: 'https://example.com',
        priority: TaskPriority.high,
        createdAt: now.add(const Duration(seconds: 5)),
      );

      queue.addAll([lowTask, normalEarly, normalLater, criticalTask, highTask]);

      final pending = queue.getPendingTasks();
      expect(pending.map((t) => t.id).toList(), [
        'critical',
        'high',
        'normal-1',
        'normal-2',
        'low',
      ]);
    });

    test('generates accurate QueueSummary snapshot', () {
      final t1 = UploadTask(
        id: '1',
        filePath: '/tmp/1.bin',
        url: 'https://example.com',
        status: UploadStatus.running,
        totalBytes: 1000,
        uploadedBytes: 500,
        speed: 100.0,
      );

      final t2 = UploadTask(
        id: '2',
        filePath: '/tmp/2.bin',
        url: 'https://example.com',
        status: UploadStatus.completed,
        totalBytes: 500,
        uploadedBytes: 500,
      );

      final t3 = UploadTask(
        id: '3',
        filePath: '/tmp/3.bin',
        url: 'https://example.com',
        status: UploadStatus.enqueued,
        totalBytes: 1500,
        uploadedBytes: 0,
      );

      queue.addAll([t1, t2, t3]);

      final summary = queue.createSummary(isConnected: true);
      expect(summary.totalTasks, 3);
      expect(summary.activeTasks, 1);
      expect(summary.completedTasks, 1);
      expect(summary.enqueuedTasks, 1);
      expect(summary.totalBytes, 3000);
      expect(summary.uploadedBytes, 1000);
      expect(summary.overallProgress, closeTo(0.333, 0.01));
      expect(summary.aggregateSpeed, 100.0);
      expect(summary.isUploading, true);
    });

    test('clears terminal tasks successfully', () {
      final t1 = UploadTask(
        id: '1',
        filePath: '/tmp/1.bin',
        url: 'https://example.com',
        status: UploadStatus.completed,
      );
      final t2 = UploadTask(
        id: '2',
        filePath: '/tmp/2.bin',
        url: 'https://example.com',
        status: UploadStatus.running,
      );
      final t3 = UploadTask(
        id: '3',
        filePath: '/tmp/3.bin',
        url: 'https://example.com',
        status: UploadStatus.cancelled,
      );

      queue.addAll([t1, t2, t3]);
      final removed = queue.clearTerminalTasks();

      expect(removed, containsAll(['1', '3']));
      expect(queue.length, 1);
      expect(queue.getTask('2'), isNotNull);
    });
  });
}
