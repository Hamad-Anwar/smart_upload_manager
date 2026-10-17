import 'dart:async';
import 'dart:math';
import 'package:dio/dio.dart';
import '../models/upload_task.dart';
import 'upload_adapter.dart';

/// Simulation upload adapter that mimics realistic network transfers,
/// chunking, speed variations, and optional failure injection.
///
/// Ideal for testing, unit tests, and demo applications without needing a live backend.
class SimulatedUploadAdapter implements UploadAdapter {
  /// Bytes transferred per second (default 1.5 MB/s).
  final int uploadSpeedBytesPerSecond;

  /// Probability (0.0 to 1.0) of simulated random transient network failure.
  final double failureProbability;

  final Map<String, bool> _cancelledTasks = {};
  final Map<String, bool> _pausedTasks = {};
  final Map<String, int> _confirmedOffsets = {};

  SimulatedUploadAdapter({
    this.uploadSpeedBytesPerSecond = 1024 * 1024 * 2, // 2 MB/s
    this.failureProbability = 0.0,
  });

  @override
  String get id => 'simulated';

  @override
  bool get supportsResuming => true;

  @override
  Future<int> getConfirmedOffset(UploadTask task) async {
    return _confirmedOffsets[task.id] ?? task.resumableOffset;
  }

  @override
  Future<UploadResponse> upload({
    required UploadTask task,
    required UploadProgressCallback onProgress,
    required CancelToken cancelToken,
  }) async {
    _cancelledTasks[task.id] = false;
    _pausedTasks[task.id] = false;

    final fileSize = task.totalBytes > 0 ? task.totalBytes : (10 * 1024 * 1024);
    var currentOffset = _confirmedOffsets[task.id] ?? (task.uploadedBytes > 0 ? task.uploadedBytes : task.resumableOffset);
    if (currentOffset >= fileSize) {
      currentOffset = 0;
    }

    final speed = (task.metadata['simulatedSpeed'] as num?)?.toInt() ?? uploadSpeedBytesPerSecond;
    const tickIntervalMs = 100;
    final bytesPerTick = (speed * (tickIntervalMs / 1000.0)).round();

    final random = Random();

    while (currentOffset < fileSize) {
      if (cancelToken.isCancelled || (_cancelledTasks[task.id] ?? false)) {
        throw DioException(
          requestOptions: RequestOptions(path: task.url),
          type: DioExceptionType.cancel,
          message: 'Simulated upload cancelled',
        );
      }

      if (_pausedTasks[task.id] ?? false) {
        throw DioException(
          requestOptions: RequestOptions(path: task.url),
          type: DioExceptionType.cancel,
          message: 'Simulated upload paused',
        );
      }

      // Check simulated failure
      if (failureProbability > 0 && random.nextDouble() < failureProbability) {
        throw DioException(
          requestOptions: RequestOptions(path: task.url),
          type: DioExceptionType.connectionError,
          message: 'Simulated network connection drop',
        );
      }

      await Future<void>.delayed(const Duration(milliseconds: tickIntervalMs));

      currentOffset = min(currentOffset + bytesPerTick, fileSize);
      _confirmedOffsets[task.id] = currentOffset;
      onProgress(currentOffset, fileSize);
    }

    return const UploadResponse(
      statusCode: 200,
      data: {'status': 'success', 'message': 'Simulated upload completed'},
    );
  }

  @override
  Future<void> cancel(String taskId) async {
    _cancelledTasks[taskId] = true;
    _confirmedOffsets.remove(taskId);
  }

  @override
  Future<void> pause(String taskId) async {
    _pausedTasks[taskId] = true;
  }

  @override
  Future<void> dispose() async {
    _cancelledTasks.clear();
    _pausedTasks.clear();
    _confirmedOffsets.clear();
  }
}
