import 'package:flutter_test/flutter_test.dart';
import 'package:smart_upload_manager/smart_upload_manager.dart';

void main() {
  group('UploadManager', () {
    late InMemoryQueueStorage storage;
    late MockConnectivityMonitor connectivity;
    late UploadManager manager;

    setUp(() async {
      storage = InMemoryQueueStorage();
      connectivity = MockConnectivityMonitor(initialConnected: true);
      manager = UploadManager(
        storage: storage,
        connectivityMonitor: connectivity,
        maxConcurrentUploads: 2,
        notificationConfig: const NotificationConfig(enabled: false),
      );
      // Register fast simulation adapter
      manager.registerAdapter(
        SimulatedUploadAdapter(
          uploadSpeedBytesPerSecond: 10 * 1024 * 1024, // 10 MB/s fast test
        ),
      );
      await manager.init();
    });

    tearDown(() async {
      await manager.dispose();
      connectivity.dispose();
    });

    test('enqueues task and completes simulated upload', () async {
      final completionFuture = manager.taskStatusStream
          .firstWhere((t) => t.status == UploadStatus.completed);

      final task = await manager.add(
        filePath: '/tmp/test.jpg',
        url: 'https://example.com/upload',
        protocol: UploadProtocol.simulated,
        simulatedFileSize: 1024 * 512, // 512 KB
      );

      final completedTask = await completionFuture;
      expect(completedTask.id, task.id);
      expect(completedTask.status, UploadStatus.completed);
      expect(completedTask.progress, 1.0);
    });

    test('pauses and resumes upload successfully', () async {
      final task = await manager.add(
        filePath: '/tmp/large.mp4',
        url: 'https://example.com/upload',
        protocol: UploadProtocol.simulated,
        simulatedFileSize: 100 * 1024 * 1024, // 100 MB
      );

      // Let it start
      await manager.taskStatusStream
          .firstWhere((t) => t.id == task.id && t.status == UploadStatus.running);

      await manager.pause(task.id);
      expect(manager.getTask(task.id)?.status, UploadStatus.paused);

      await manager.resume(task.id);
      expect(manager.getTask(task.id)?.status, isIn([UploadStatus.enqueued, UploadStatus.running]));
    });

    test('cancels active upload', () async {
      final task = await manager.add(
        filePath: '/tmp/cancel_me.pdf',
        url: 'https://example.com/upload',
        protocol: UploadProtocol.simulated,
        simulatedFileSize: 50 * 1024 * 1024,
      );

      await manager.cancel(task.id);
      expect(manager.getTask(task.id)?.status, UploadStatus.cancelled);
    });

    test('handles offline disconnect and auto-resumes on reconnect', () async {
      final task = await manager.add(
        filePath: '/tmp/offline_test.zip',
        url: 'https://example.com/upload',
        protocol: UploadProtocol.simulated,
        simulatedFileSize: 200 * 1024 * 1024,
      );

      // Wait until running
      await manager.taskStatusStream
          .firstWhere((t) => t.id == task.id && t.status == UploadStatus.running);

      // Simulate internet disconnection
      connectivity.setConnected(false);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final offlineTask = manager.getTask(task.id);
      expect(offlineTask?.status, UploadStatus.enqueued);

      // Simulate internet reconnection
      connectivity.setConnected(true);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final resumedTask = manager.getTask(task.id);
      expect(resumedTask?.status, isIn([UploadStatus.enqueued, UploadStatus.running]));
    });
  });
}
