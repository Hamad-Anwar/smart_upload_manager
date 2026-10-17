import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_upload_manager/smart_upload_manager.dart';

void main() {
  test('creates and executes single file upload task', () async {
    final tempDir = Directory.systemTemp;
    final testFile = File('${tempDir.path}/test_single_sample.png');
    const base64Png =
        'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAYAAADED76LAAAAIklEQVR42mNk+M/wHwYGBgYWBgYGYyDDQAYYxWBkYGBg'
        'AQC2jQcB1zNmsQAAAABJRU5ErkJggg==';
    await testFile.writeAsBytes(base64Decode(base64Png));

    final manager = UploadManager(
      storage: InMemoryQueueStorage(),
      connectivityMonitor: MockConnectivityMonitor(initialConnected: true),
      notificationConfig: const NotificationConfig(enabled: false),
    );
    await manager.init();

    final task = await manager.add(
      filePath: testFile.path,
      url: 'https://api.example.com/upload/single',
      protocol: UploadProtocol.simulated,
      simulatedFileSize: 1024,
    );

    expect(task.isMultiFile, isFalse);
    expect(task.filePaths, [testFile.path]);

    final completedTask = await manager.taskStatusStream.firstWhere(
      (t) => t.id == task.id && (t.status == UploadStatus.completed || t.status == UploadStatus.failed),
    );

    expect(completedTask.status, UploadStatus.completed);
    expect(completedTask.error, isNull);

    await manager.dispose();
    if (await testFile.exists()) {
      await testFile.delete();
    }
  });

  test('creates and executes multi-file upload bundle task', () async {
    final tempDir = Directory.systemTemp;
    final testFile1 = File('${tempDir.path}/multi_1.png');
    final testFile2 = File('${tempDir.path}/multi_2.png');
    const base64Png =
        'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAYAAADED76LAAAAIklEQVR42mNk+M/wHwYGBgYWBgYGYyDDQAYYxWBkYGBg'
        'AQC2jQcB1zNmsQAAAABJRU5ErkJggg==';
    await testFile1.writeAsBytes(base64Decode(base64Png));
    await testFile2.writeAsBytes(base64Decode(base64Png));

    final manager = UploadManager(
      storage: InMemoryQueueStorage(),
      connectivityMonitor: MockConnectivityMonitor(initialConnected: true),
      notificationConfig: const NotificationConfig(enabled: false),
    );
    await manager.init();

    final task = await manager.addMultiple(
      filePaths: [testFile1.path, testFile2.path],
      url: 'https://api.example.com/upload/multiple',
      fileFieldName: 'files',
      protocol: UploadProtocol.simulated,
      simulatedFileSize: 2048,
    );

    expect(task.isMultiFile, isTrue);
    expect(task.filePaths.length, 2);
    expect(task.fileName, '2 files');

    final completedTask = await manager.taskStatusStream.firstWhere(
      (t) => t.id == task.id && (t.status == UploadStatus.completed || t.status == UploadStatus.failed),
    );

    expect(completedTask.status, UploadStatus.completed);
    expect(completedTask.error, isNull);

    await manager.dispose();
    if (await testFile1.exists()) await testFile1.delete();
    if (await testFile2.exists()) await testFile2.delete();
  });
}
