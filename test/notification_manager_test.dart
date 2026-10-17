import 'package:flutter_test/flutter_test.dart';
import 'package:smart_upload_manager/smart_upload_manager.dart';

void main() {
  group('UploadNotificationManager', () {
    test('formats default title and body accurately', () {
      const config = NotificationConfig(enabled: true);
      final task = UploadTask(
        id: '1',
        filePath: '/storage/holiday.mp4',
        url: 'https://api.example.com',
        status: UploadStatus.running,
        totalBytes: 100 * 1024 * 1024,
        uploadedBytes: 45 * 1024 * 1024,
        speed: 2 * 1024 * 1024,
      );

      const summary = QueueSummary(
        totalTasks: 1,
        activeTasks: 1,
        enqueuedTasks: 0,
        completedTasks: 0,
        failedTasks: 0,
        pausedTasks: 0,
        totalBytes: 100 * 1024 * 1024,
        uploadedBytes: 45 * 1024 * 1024,
        aggregateSpeed: 2 * 1024 * 1024,
      );

      expect(config.defaultTitle(task, summary), 'Uploading holiday.mp4');
      expect(config.defaultBody(task, summary), contains('45%'));
      expect(config.defaultBody(task, summary), contains('2.0 MB/s'));
    });

    test('generates completed status message when finished', () {
      const config = NotificationConfig(enabled: true);
      const summary = QueueSummary(
        totalTasks: 2,
        activeTasks: 0,
        enqueuedTasks: 0,
        completedTasks: 2,
        failedTasks: 0,
        pausedTasks: 0,
        totalBytes: 5000,
        uploadedBytes: 5000,
        aggregateSpeed: 0,
      );

      expect(config.defaultTitle(null, summary), 'Uploads Completed');
      expect(config.defaultBody(null, summary), 'All 2 files uploaded successfully.');
    });

    test('formats multi-file queue title and body with pending counts accurately', () {
      const config = NotificationConfig(enabled: true);
      const summary = QueueSummary(
        totalTasks: 4,
        activeTasks: 2,
        enqueuedTasks: 2,
        completedTasks: 0,
        failedTasks: 0,
        pausedTasks: 0,
        totalBytes: 200 * 1024 * 1024,
        uploadedBytes: 50 * 1024 * 1024,
        aggregateSpeed: 4 * 1024 * 1024,
      );

      expect(config.defaultTitle(null, summary), 'Uploading 4 files (2 active)');
      expect(config.defaultBody(null, summary), contains('2 pending'));
      expect(config.defaultBody(null, summary), contains('25%'));
    });

    test('generates paused message when uploads are paused', () {
      const config = NotificationConfig(enabled: true);
      final task = UploadTask(
        id: '1',
        filePath: '/storage/holiday.mp4',
        url: 'https://api.example.com',
        status: UploadStatus.paused,
        totalBytes: 100 * 1024 * 1024,
        uploadedBytes: 45 * 1024 * 1024,
      );

      const summary = QueueSummary(
        totalTasks: 1,
        activeTasks: 0,
        enqueuedTasks: 0,
        completedTasks: 0,
        failedTasks: 0,
        pausedTasks: 1,
        totalBytes: 100 * 1024 * 1024,
        uploadedBytes: 45 * 1024 * 1024,
      );

      expect(config.defaultTitle(task, summary), 'Upload Paused: holiday.mp4');
      expect(config.defaultBody(task, summary), 'holiday.mp4 is paused. Tap to resume.');
    });
  });
}
